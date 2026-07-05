defmodule JidoCode.Forge.Persistence do
  @moduledoc """
  Persistence layer for Forge sessions.

  Centralizes all embedded product-store updates for session state transitions.
  This module is called by SpriteSession to keep the database in sync
  with runtime state.

  Design contract: Runtime (GenServer) is the source of truth for "what is
  happening now". Runtime semantic records are the durable audit, resume, and observability projection.
  Updates are best-effort and don't block the runtime.

  ## Configuration

  Persistence can be disabled via application config:

      config :jido_code, JidoCode.Forge.Persistence, enabled: false

  This is useful for integration tests that don't need DB persistence.
  """

  require Logger

  alias JidoCode.ExecutionRuntime.RecordStore
  alias JidoCode.Forge.ChannelRedaction
  alias JidoCode.Forge.EventLogger
  alias JidoCode.Forge.Resources.{ExecSession, Session}

  @doc """
  Check if persistence is enabled.
  """
  def enabled? do
    Application.get_env(:jido_code, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Record that a session has started (provisioning phase).
  Called from Manager.start_session or SpriteSession.init.
  """
  @spec record_session_started(String.t(), map()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_session_started(session_id, spec) do
    if enabled?() do
      runner_type = Map.get(spec, :runner) || Map.get(spec, :runner_type, :shell)
      runner_config = Map.get(spec, :runner_config, %{})

      RecordStore.upsert_sandbox_session(%{
        managed_repo_id: managed_repo_id_from(spec),
        name: session_id,
        runner_type: runner_type,
        runner_config: runner_config,
        spec: spec,
        phase: :created,
        metadata: %{created_at: DateTime.utc_now()}
      })
      |> tap_log("session.started", session_id)
    else
      :noop
    end
  end

  @doc """
  Record that provisioning is complete with sprite info.
  """
  @spec record_provision_complete(String.t(), String.t(), String.t() | nil) ::
          {:ok, Session.t()} | {:error, term()} | :noop
  def record_provision_complete(session_id, sprite_id, sprite_name \\ nil) do
    if enabled?() do
      with {:ok, session} <- find_session(session_id) do
        session
        |> RecordStore.update_sandbox_session(%{
          phase: :bootstrapping,
          sprite_id: sprite_id,
          sprite_name: sprite_name || "forge-#{sprite_id}",
          last_activity_at: DateTime.utc_now()
        })
        |> tap_log("session.provisioned", session_id, %{sprite_id: sprite_id})
      end
    else
      :noop
    end
  end

  @doc """
  Record that bootstrap is complete and session is ready.
  """
  @spec record_bootstrap_complete(String.t()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_bootstrap_complete(session_id) do
    if enabled?() do
      with {:ok, session} <- find_session(session_id) do
        session
        |> RecordStore.update_sandbox_session(%{phase: :ready, last_activity_at: DateTime.utc_now()})
        |> tap_log("session.bootstrap_complete", session_id)
      end
    else
      :noop
    end
  end

  @doc """
  Record the start of an execution iteration.
  Returns the ExecSession record for tracking completion.
  """
  @spec record_execution_start(String.t(), integer(), keyword()) ::
          {:ok, ExecSession.t()} | {:error, term()} | :noop
  def record_execution_start(session_id, iteration, opts \\ []) do
    if enabled?() do
      with {:ok, session} <- find_session(session_id) do
        execution_count = (session.execution_count || 0) + 1

        with {:ok, _session} <-
               RecordStore.update_sandbox_session(session, %{
                 phase: :running,
                 execution_count: execution_count,
                 last_activity_at: DateTime.utc_now()
               }) do
          RecordStore.create_exec_session(%{
            managed_repo_id: Map.get(session, :managed_repo_id),
            session_id: session.id,
            sequence: iteration,
            command: Keyword.get(opts, :command),
            sprites_session_id: Keyword.get(opts, :sprites_session_id),
            metadata: Keyword.get(opts, :metadata, %{})
          })
        end
      end
    else
      :noop
    end
  end

  @doc """
  Record the completion of an execution iteration.
  """
  @spec record_execution_complete(String.t(), map()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_execution_complete(session_id, result) do
    if enabled?() do
      with {:ok, redacted_result} <- redact_artifact_payload(result, session_id, :record_execution_complete),
           {:ok, session} <- find_session(session_id) do
        result_status = map_result_status(redacted_result)

        with {:ok, updated_session} <-
               RecordStore.update_sandbox_session(session, %{
                 phase: phase_for_result_status(result_status),
                 runner_state: result_value(redacted_result, :runner_state),
                 output_buffer: truncate_output(result_value(redacted_result, :output)),
                 last_activity_at: DateTime.utc_now()
               }),
             :ok <- complete_latest_exec_session(session, redacted_result, result_status) do
          {:ok, updated_session}
        end
        |> tap_log("session.execution_complete", session_id, %{status: result_status})
      end
    else
      :noop
    end
  end

  @doc """
  Record that input has been applied and session is ready again.
  """
  @spec record_input_applied(String.t(), map()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_input_applied(session_id, runner_state) do
    if enabled?() do
      with {:ok, session} <- find_session(session_id) do
        session
        |> RecordStore.update_sandbox_session(%{
          phase: :ready,
          runner_state: runner_state,
          last_activity_at: DateTime.utc_now()
        })
        |> tap_log("session.input_applied", session_id)
      end
    else
      :noop
    end
  end

  @doc """
  Record a session failure.
  """
  @spec record_failure(String.t(), term()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_failure(session_id, reason) do
    if enabled?() do
      with {:ok, error_details} <- reason |> normalize_error() |> redact_artifact_payload(session_id, :record_failure),
           {:ok, session} <- find_session(session_id) do
        session
        |> RecordStore.update_sandbox_session(%{
          phase: :failed,
          last_error: error_details,
          last_activity_at: DateTime.utc_now(),
          completed_at: DateTime.utc_now()
        })
        |> tap_log("session.failed", session_id, error_details)
      end
    else
      :noop
    end
  end

  @doc """
  Log an event for a session.
  """
  @spec log_event(String.t(), String.t(), map()) :: :ok
  def log_event(session_id, event_type, data \\ %{}) do
    if enabled?() do
      Task.start(fn ->
        with {:ok, session} <- find_session(session_id) do
          EventLogger.log_event(session.id, event_type, data)
        end
      end)
    end

    :ok
  end

  # Private helpers

  defp find_session(session_id) when is_binary(session_id) do
    session_id
    |> RecordStore.get_sandbox_session()
    |> require_session()
  end

  defp require_session({:ok, nil}), do: {:error, :session_not_found}
  defp require_session({:ok, %Session{} = session}), do: {:ok, session}
  defp require_session(other), do: other

  defp map_result_status(result) when is_map(result) do
    case {result_value(result, :status), result_value(result, :continue)} do
      {:done, _continue} -> :completed
      {"done", _continue} -> :completed
      {:continue, _continue} -> :needs_continuation
      {"continue", _continue} -> :needs_continuation
      {:needs_input, _continue} -> :needs_input
      {"needs_input", _continue} -> :needs_input
      {:error, _continue} -> :failed
      {"error", _continue} -> :failed
      {:blocked, _continue} -> :needs_input
      {"blocked", _continue} -> :needs_input
      {_status, true} -> :needs_continuation
      {_status, "true"} -> :needs_continuation
      _other -> :completed
    end
  end

  defp map_result_status(_), do: :completed

  defp phase_for_result_status(:completed), do: :completed
  defp phase_for_result_status(:needs_continuation), do: :ready
  defp phase_for_result_status(:needs_input), do: :needs_input
  defp phase_for_result_status(:failed), do: :failed

  defp complete_latest_exec_session(session, result, result_status) do
    with {:ok, exec_sessions} <- RecordStore.list_exec_sessions(%{sandbox_session_id: session.id}) do
      case latest_exec_session(exec_sessions) do
        %ExecSession{} = exec_session ->
          attrs =
            %{
              status: result_status,
              exit_code: result_value(result, :exit_code),
              output: truncate_output(result_value(result, :output)),
              cost_usd: result_value(result, :cost_usd),
              duration_ms: result_value(result, :duration_ms),
              completed_at: DateTime.utc_now()
            }
            |> Enum.reject(fn {_key, value} -> is_nil(value) end)
            |> Map.new()

          case RecordStore.update_exec_session(exec_session.id, attrs) do
            {:ok, _exec_session} -> :ok
            {:error, reason} -> {:error, reason}
          end

        nil ->
          :ok
      end
    end
  end

  defp latest_exec_session(exec_sessions) do
    exec_sessions
    |> Enum.sort_by(fn exec_session -> exec_session.sequence || 0 end, :desc)
    |> List.first()
  end

  defp truncate_output(nil), do: nil

  defp truncate_output(output) when byte_size(output) > 10_000 do
    String.slice(output, -10_000, 10_000)
  end

  defp truncate_output(output), do: output

  defp normalize_error(reason) when is_binary(reason), do: %{message: reason}
  defp normalize_error(reason) when is_atom(reason), do: %{type: reason}
  defp normalize_error({type, details}), do: %{type: type, details: inspect(details)}
  defp normalize_error(reason), do: %{raw: inspect(reason)}

  defp result_value(result, key) when is_map(result), do: Map.get(result, key) || Map.get(result, to_string(key))

  defp managed_repo_id_from(spec) when is_map(spec) do
    Map.get(spec, :managed_repo_id) ||
      Map.get(spec, "managed_repo_id") ||
      spec
      |> Map.get(:metadata, Map.get(spec, "metadata", %{}))
      |> managed_repo_id_from()
  end

  defp managed_repo_id_from(_spec), do: nil

  defp redact_artifact_payload(payload, session_id, operation) do
    case ChannelRedaction.redact_artifact_payload(payload, operation: operation) do
      {:ok, redacted_payload} ->
        {:ok, redacted_payload}

      {:error, typed_error} = error ->
        Logger.error(
          "security_audit=forge_artifact_redaction_failed severity=high session_id=#{session_id} action=persistence_blocked operation=#{operation} error_type=#{typed_error.error_type} reason_type=#{typed_error.reason_type}"
        )

        error
    end
  end

  defp tap_log(result, event_type, session_id, data \\ %{})

  defp tap_log({:ok, _} = result, event_type, session_id, data) do
    log_event(session_id, event_type, data)
    result
  end

  defp tap_log({:error, reason} = result, event_type, session_id, _data) do
    Logger.warning("Failed to persist #{event_type} for #{session_id}: #{inspect(reason)}")
    result
  end
end
