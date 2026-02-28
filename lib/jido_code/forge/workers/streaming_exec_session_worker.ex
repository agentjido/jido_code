defmodule JidoCode.Forge.Workers.StreamingExecSessionWorker do
  @moduledoc """
  Worker for streaming command execution with output coalescing and backpressure.

  Handles real-time output streaming from infra commands, coalescing chunks
  to avoid overwhelming subscribers while maintaining responsiveness.
  """

  use GenServer

  require Logger

  alias JidoCode.Forge.ChannelRedaction
  alias JidoCode.Forge.EventLogger
  alias JidoCode.Forge.PubSub, as: ForgePubSub
  alias JidoCode.Forge.Resources.ExecSession

  @chunk_coalesce_ms 50
  @max_buffer_size 64 * 1024
  @max_output_size 1_000_000

  defstruct [
    :session_id,
    :exec_session_id,
    :sequence,
    :command_ref,
    :infra_client,
    :client,
    buffer: "",
    last_flush: 0,
    total_output: "",
    started_at: nil
  ]

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @doc """
  Start a streaming exec session.

  ## Options

    * `:session_id` - The parent session ID (required)
    * `:sequence` - Execution sequence number (required)  
    * `:command` - Command to execute (required)
    * `:client` - Infra client struct (required)
    * `:infra_client` - Infra client module (required)
    * `:sprites_session_id` - Optional sprites API session ID
    * `:metadata` - Optional metadata map
  """
  @spec start(keyword()) :: {:ok, pid()} | {:error, term()}
  def start(opts) do
    DynamicSupervisor.start_child(
      JidoCode.Forge.ExecSessionSupervisor,
      {__MODULE__, opts}
    )
  end

  @impl true
  def init(args) do
    session_id = Keyword.fetch!(args, :session_id)
    sequence = Keyword.fetch!(args, :sequence)
    command = Keyword.fetch!(args, :command)
    client = Keyword.fetch!(args, :client)
    infra_client = Keyword.fetch!(args, :infra_client)
    sprites_session_id = Keyword.get(args, :sprites_session_id)
    metadata = Keyword.get(args, :metadata, %{})

    case create_exec_session_record(session_id, sequence, command, sprites_session_id, metadata) do
      {:ok, exec_session} ->
        case infra_client.spawn(client, "bash", ["-c", command], tty: true) do
          {:ok, cmd_ref} ->
            state = %__MODULE__{
              session_id: session_id,
              exec_session_id: exec_session.id,
              sequence: sequence,
              command_ref: cmd_ref,
              infra_client: infra_client,
              client: client,
              buffer: "",
              last_flush: System.monotonic_time(:millisecond),
              total_output: "",
              started_at: DateTime.utc_now()
            }

            {:ok, state}

          {:error, reason} ->
            Logger.error("Failed to spawn command for session #{session_id}: #{inspect(reason)}")
            {:stop, {:spawn_failed, reason}}
        end

      {:error, reason} ->
        Logger.error("Failed to create exec session record: #{inspect(reason)}")
        {:stop, {:record_failed, reason}}
    end
  end

  @impl true
  def handle_info({:stdout, _ref, data}, state) do
    new_buffer = state.buffer <> data
    new_total = state.total_output <> data
    now = System.monotonic_time(:millisecond)

    state = %{state | buffer: new_buffer, total_output: new_total}

    state =
      if byte_size(new_buffer) >= @max_buffer_size or
           now - state.last_flush >= @chunk_coalesce_ms do
        flush_buffer(state)
      else
        state
      end

    {:noreply, state}
  end

  def handle_info({:stderr, _ref, data}, state) do
    handle_info({:stdout, nil, data}, state)
  end

  def handle_info({:exit, _ref, exit_code}, state) do
    state = if state.buffer != "", do: flush_buffer(state), else: state

    result_status = if exit_code == 0, do: :completed, else: :failed
    duration_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)

    complete_exec_session(state, result_status, exit_code, duration_ms)

    emit_signal(state.session_id, "forge.exec_session.complete", %{
      sequence: state.sequence,
      exit_code: exit_code,
      result_status: result_status,
      duration_ms: duration_ms
    })

    {:stop, :normal, state}
  end

  def handle_info({:error, _ref, reason}, state) do
    state = if state.buffer != "", do: flush_buffer(state), else: state

    duration_ms = DateTime.diff(DateTime.utc_now(), state.started_at, :millisecond)
    complete_exec_session(state, :failed, nil, duration_ms)

    emit_signal(state.session_id, "forge.exec_session.error", %{
      sequence: state.sequence,
      error: inspect(reason)
    })

    {:stop, {:error, reason}, state}
  end

  defp flush_buffer(%{buffer: ""} = state), do: state

  defp flush_buffer(state) do
    log_output_event(state.session_id, state.sequence, state.buffer)

    ForgePubSub.broadcast_session(
      state.session_id,
      {:output,
       %{
         chunk: state.buffer,
         seq: state.sequence
       }}
    )

    %{state | buffer: "", last_flush: System.monotonic_time(:millisecond)}
  end

  defp create_exec_session_record(session_id, sequence, command, sprites_session_id, metadata) do
    ExecSession
    |> Ash.Changeset.for_create(:start, %{
      session_id: session_id,
      sequence: sequence,
      command: command,
      sprites_session_id: sprites_session_id,
      metadata: metadata
    })
    |> Ash.create()
  end

  defp complete_exec_session(state, result_status, exit_code, duration_ms) do
    with {:ok, redacted_output} <- redact_exec_output(state, truncate_output(state.total_output)) do
      ExecSession
      |> Ash.get!(state.exec_session_id)
      |> Ash.Changeset.for_update(:complete, %{
        result_status: result_status,
        exit_code: exit_code,
        output: redacted_output,
        duration_ms: duration_ms
      })
      |> Ash.update()
    end
  end

  defp log_output_event(session_id, sequence, chunk) do
    EventLogger.log_event(
      session_id,
      "exec_session.output",
      %{chunk: chunk, size: byte_size(chunk)},
      exec_session_sequence: sequence
    )
  end

  defp emit_signal(session_id, type, data) do
    ForgePubSub.broadcast_session(session_id, {:signal, %{type: type, data: data}})
  end

  defp redact_exec_output(state, output) do
    case ChannelRedaction.redact_artifact_payload(output, operation: :complete_exec_session_output) do
      {:ok, redacted_output} ->
        {:ok, redacted_output}

      {:error, typed_error} = error ->
        Logger.error(
          "security_audit=forge_artifact_redaction_failed severity=high session_id=#{state.session_id} action=persistence_blocked operation=complete_exec_session_output sequence=#{state.sequence} error_type=#{typed_error.error_type} reason_type=#{typed_error.reason_type}"
        )

        error
    end
  end

  defp truncate_output(output) when byte_size(output) > @max_output_size do
    "...[truncated]...\n" <> binary_part(output, byte_size(output) - @max_output_size, @max_output_size)
  end

  defp truncate_output(output), do: output
end
