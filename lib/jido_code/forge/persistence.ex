defmodule JidoCode.Forge.Persistence do
  @moduledoc """
  Persistence layer for Forge sessions.

  Centralizes all Ash resource updates for session state transitions.
  This module is called by InfraSession to keep the database in sync
  with runtime state.

  Design contract: Runtime (GenServer) is the source of truth for "what is
  happening now". Ash is the durable record for audit, resume, and observability.
  Updates are best-effort and don't block the runtime.

  ## Configuration

  Persistence can be disabled via application config:

      config :jido_code, JidoCode.Forge.Persistence, enabled: false

  This is useful for integration tests that don't need DB persistence.
  """

  require Logger

  alias JidoCode.Forge.ChannelRedaction
  alias JidoCode.Forge.EventLogger
  alias JidoCode.Forge.Resources.{Session, ExecSession}

  @doc """
  Check if persistence is enabled.
  """
  def enabled? do
    Application.get_env(:jido_code, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Record that a session has started (provisioning phase).
  Called from Manager.start_session or InfraSession.init.
  """
  @spec record_session_started(String.t(), map()) :: {:ok, Session.t()} | {:error, term()} | :noop
  def record_session_started(session_id, spec) do
    if enabled?() do
      runner_type = Map.get(spec, :runner) || Map.get(spec, :runner_type, :shell)
      runner_config = Map.get(spec, :runner_config, %{})

      Session
      |> Ash.Changeset.for_create(:create, %{
        name: session_id,
        runner_type: runner_type,
        runner_config: runner_config,
        spec: spec,
        metadata: %{created_at: DateTime.utc_now()}
      })
      |> Ash.create()
      |> tap_log("session.started", session_id)
    else
      :noop
    end
  end

  @doc """
  Record that provisioning is complete with infra info.
  """
  @spec record_provision_complete(String.t(), String.t(), String.t() | nil) ::
          {:ok, Session.t()} | {:error, term()} | :noop
  def record_provision_complete(session_id, sprite_id, sprite_name \\ nil) do
    if enabled?() do
      with {:ok, session} <- find_session(session_id) do
        session
        |> Ash.Changeset.for_update(:provision_complete, %{
          sprite_id: sprite_id,
          sprite_name: sprite_name || "forge-#{sprite_id}"
        })
        |> Ash.update()
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
        |> Ash.Changeset.for_update(:bootstrap_complete)
        |> Ash.update()
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
        session
        |> Ash.Changeset.for_update(:begin_execution)
        |> Ash.update()

        ExecSession
        |> Ash.Changeset.for_create(:start, %{
          session_id: session.id,
          sequence: iteration,
          command: Keyword.get(opts, :command),
          sprites_session_id: Keyword.get(opts, :sprites_session_id),
          metadata: Keyword.get(opts, :metadata, %{})
        })
        |> Ash.create()
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

        session
        |> Ash.Changeset.for_update(:execution_complete, %{
          result_status: result_status,
          runner_state: redacted_result[:runner_state],
          output_buffer: truncate_output(redacted_result[:output])
        })
        |> Ash.update()
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
        |> Ash.Changeset.for_update(:apply_input, %{runner_state: runner_state})
        |> Ash.update()
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
        |> Ash.Changeset.for_update(:mark_failed, %{last_error: error_details})
        |> Ash.update()
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
    require Ash.Query

    Session
    |> Ash.Query.filter(name == ^session_id)
    |> Ash.read_one()
    |> case do
      {:ok, nil} -> {:error, :session_not_found}
      {:ok, session} -> {:ok, session}
      error -> error
    end
  end

  defp map_result_status(%{status: :done}), do: :completed
  defp map_result_status(%{status: :continue}), do: :needs_continuation
  defp map_result_status(%{continue: true}), do: :needs_continuation
  defp map_result_status(%{status: :needs_input}), do: :needs_input
  defp map_result_status(%{status: :error}), do: :failed
  defp map_result_status(%{status: :blocked}), do: :needs_input
  defp map_result_status(_), do: :completed

  defp truncate_output(nil), do: nil

  defp truncate_output(output) when byte_size(output) > 10_000 do
    String.slice(output, -10_000, 10_000)
  end

  defp truncate_output(output), do: output

  defp normalize_error(reason) when is_binary(reason), do: %{message: reason}
  defp normalize_error(reason) when is_atom(reason), do: %{type: reason}
  defp normalize_error({type, details}), do: %{type: type, details: inspect(details)}
  defp normalize_error(reason), do: %{raw: inspect(reason)}

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
