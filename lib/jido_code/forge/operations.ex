defmodule JidoCode.Forge.Operations do
  @moduledoc """
  Orchestration layer for Forge session operations.

  Coordinates between runtime persistence records and runtime concerns
  (Sprites API, PubSub events, session lifecycle).
  """

  require Logger

  alias JidoCode.ExecutionRuntime.RecordStore
  alias JidoCode.Forge.{ChannelRedaction, EventLogger, Manager, PubSub}
  alias JidoCode.Forge.Resources.{Checkpoint, Session}

  @doc """
  Resume a session from its last checkpoint.

  1. Loads session and validates it has a checkpoint
  2. Updates session state to :resuming through the product store
  3. Logs resume event
  4. Starts a new SpriteSession process with checkpoint restoration

  Returns `{:ok, pid}` on success or `{:error, reason}` on failure.
  """
  @spec resume(String.t()) :: {:ok, pid()} | {:error, term()}
  def resume(session_id) do
    with {:ok, session} <- load_session(session_id),
         :ok <- validate_resumable(session),
         {:ok, checkpoint} <- load_latest_checkpoint(session.id),
         {:ok, session} <- transition_to_resuming(session),
         :ok <- log_event(session.id, "session.resuming", %{checkpoint_id: checkpoint.sprites_checkpoint_id}),
         {:ok, pid} <- start_resumed_session(session, checkpoint) do
      PubSub.broadcast_session(to_string(session.id), {:resumed, %{checkpoint_id: checkpoint.sprites_checkpoint_id}})
      {:ok, pid}
    end
  end

  @doc """
  Cancel a running session.

  1. Updates session state to :cancelled through the product store
  2. Logs cancellation event
  3. Stops the session process (which triggers sprite cleanup)
  4. Broadcasts cancellation

  Returns `:ok` on success or `{:error, reason}` on failure.
  """
  @spec cancel(String.t()) :: :ok | {:error, term()}
  def cancel(session_id) do
    with {:ok, session} <- load_session(session_id),
         :ok <- validate_cancellable(session),
         {:ok, _session} <- transition_to_cancelled(session),
         :ok <-
           log_event(session.id, "session.cancelled", %{phase: session.phase, execution_count: session.execution_count}),
         :ok <- stop_session_process(session) do
      PubSub.broadcast_session(to_string(session.id), {:cancelled, %{}})
      :ok
    end
  end

  @doc """
  Create a checkpoint for an active session.

  1. Validates session is in a checkpointable state
  2. Calls Sprites API to create checkpoint
  3. Records checkpoint in database
  4. Updates session with last_checkpoint_id

  Returns `{:ok, checkpoint}` on success.
  """
  @spec create_checkpoint(String.t(), keyword()) :: {:ok, Checkpoint.t()} | {:error, term()}
  def create_checkpoint(session_id, opts \\ []) do
    name = Keyword.get(opts, :name)

    with {:ok, session} <- load_session(session_id),
         :ok <- validate_checkpointable(session),
         {:ok, sprites_checkpoint_id} <- create_sprites_checkpoint(session),
         {:ok, checkpoint} <- save_checkpoint(session, sprites_checkpoint_id, name),
         {:ok, _session} <- update_session_checkpoint(session, sprites_checkpoint_id) do
      log_event(session.id, "checkpoint.created", %{checkpoint_id: sprites_checkpoint_id, name: name})
      PubSub.broadcast_session(to_string(session.id), {:checkpoint_created, %{id: checkpoint.id}})
      {:ok, checkpoint}
    end
  end

  @doc """
  Mark a session as failed with error details.
  """
  @spec mark_failed(String.t(), map()) :: {:ok, Session.t()} | {:error, term()}
  def mark_failed(session_id, error_details) do
    with {:ok, session} <- load_session(session_id),
         {:ok, redacted_error_details} <- redact_failure_details(session.id, error_details),
         {:ok, session} <- do_mark_failed(session, redacted_error_details),
         :ok <- log_event(session.id, "session.failed", redacted_error_details),
         :ok <- PubSub.broadcast_session(to_string(session.id), {:failed, redacted_error_details}) do
      {:ok, session}
    end
  end

  @doc """
  Mark a session as completed.
  """
  @spec complete(String.t()) :: {:ok, Session.t()} | {:error, term()}
  def complete(session_id) do
    with {:ok, session} <- load_session(session_id),
         {:ok, session} <- do_complete(session),
         :ok <- log_event(session.id, "session.completed", %{execution_count: session.execution_count}) do
      PubSub.broadcast_session(to_string(session.id), {:completed, %{}})
      {:ok, session}
    end
  end

  # Private helpers

  defp load_session(session_id) when is_binary(session_id) do
    case RecordStore.get_sandbox_session(session_id) do
      {:ok, nil} -> {:error, :session_not_found}
      {:ok, session} -> {:ok, session}
      error -> error
    end
  end

  defp load_latest_checkpoint(session_id) do
    case RecordStore.latest_checkpoint(session_id) do
      {:ok, nil} -> {:error, :no_checkpoint_available}
      {:ok, checkpoint} -> {:ok, checkpoint}
      error -> error
    end
  end

  defp validate_resumable(%{phase: phase, last_checkpoint_id: nil}) do
    {:error, {:not_resumable, "no checkpoint available", phase}}
  end

  defp validate_resumable(%{phase: phase}) when phase in [:failed, :cancelled] do
    :ok
  end

  defp validate_resumable(%{phase: phase}) do
    {:error, {:not_resumable, "session in phase #{phase}", phase}}
  end

  defp validate_cancellable(%{phase: phase}) when phase in [:completed, :failed, :cancelled] do
    {:error, {:already_terminal, phase}}
  end

  defp validate_cancellable(_session), do: :ok

  defp validate_checkpointable(%{phase: phase}) when phase in [:ready, :running, :needs_input] do
    :ok
  end

  defp validate_checkpointable(%{phase: phase}) do
    {:error, {:not_checkpointable, phase}}
  end

  defp transition_to_resuming(session) do
    RecordStore.update_sandbox_session(session, %{phase: :resuming, last_activity_at: DateTime.utc_now()})
  end

  defp transition_to_cancelled(session) do
    RecordStore.update_sandbox_session(session, %{
      phase: :cancelled,
      last_activity_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    })
  end

  defp do_mark_failed(session, error_details) do
    RecordStore.update_sandbox_session(session, %{
      phase: :failed,
      last_error: error_details,
      last_activity_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    })
  end

  defp redact_failure_details(session_id, error_details) do
    case ChannelRedaction.redact_artifact_payload(error_details, operation: :mark_failed) do
      {:ok, redacted_error_details} ->
        {:ok, redacted_error_details}

      {:error, typed_error} = error ->
        Logger.error(
          "security_audit=forge_artifact_redaction_failed severity=high session_id=#{session_id} action=persistence_blocked operation=mark_failed error_type=#{typed_error.error_type} reason_type=#{typed_error.reason_type}"
        )

        error
    end
  end

  defp do_complete(session) do
    RecordStore.update_sandbox_session(session, %{
      phase: :completed,
      last_activity_at: DateTime.utc_now(),
      completed_at: DateTime.utc_now()
    })
  end

  defp update_session_checkpoint(session, checkpoint_id) do
    RecordStore.update_sandbox_session(session, %{
      last_checkpoint_id: checkpoint_id,
      last_activity_at: DateTime.utc_now()
    })
  end

  defp log_event(session_id, event_type, data) do
    EventLogger.log_event(session_id, event_type, data)
  end

  defp start_resumed_session(session, checkpoint) do
    spec =
      session.spec
      |> Map.put(:resume_from_checkpoint, checkpoint.sprites_checkpoint_id)
      |> Map.put(:runner_state, checkpoint.runner_state_snapshot || %{})

    Manager.start_session(to_string(session.id), spec)
  end

  defp stop_session_process(session) do
    case Manager.get_session(to_string(session.id)) do
      {:ok, _pid} -> Manager.stop_session(to_string(session.id), :cancelled)
      {:error, :not_found} -> :ok
    end
  end

  defp create_sprites_checkpoint(%{sprite_id: nil}) do
    {:error, :no_sprite_provisioned}
  end

  defp create_sprites_checkpoint(%{sprite_id: sprite_id}) do
    # TODO: Integrate with actual Sprites API checkpoint creation
    # For now, generate a placeholder checkpoint ID
    checkpoint_id = "chk_#{sprite_id}_#{System.system_time(:millisecond)}"
    {:ok, checkpoint_id}
  end

  defp save_checkpoint(session, sprites_checkpoint_id, name) do
    RecordStore.create_checkpoint(%{
      managed_repo_id: Map.get(session, :managed_repo_id),
      session_id: session.id,
      sprites_checkpoint_id: sprites_checkpoint_id,
      name: name,
      exec_session_sequence: session.execution_count,
      runner_state_snapshot: session.runner_state,
      metadata: %{created_at: DateTime.utc_now()}
    })
  end
end
