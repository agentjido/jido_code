defmodule JidoCode.Conversations.Persistence do
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  @moduledoc """
  Durable boundary for conversation history and snapshots.

  The append-only event log is the durable history. Snapshot records are a
  derived projection used for cold load and degraded continuity. Active worker
  bindings remain transient runtime state and are not re-created from persisted
  snapshots alone.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Conversations.{Conversation, RecordStore, Snapshot, SnapshotRecord}

  @persistence_actor Actor.factory_system_actor(%{
                       "id" => "system:conversation-persistence",
                       "email" => "conversation-persistence@system.local"
                     })

  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:jido_code, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @spec persist_transition(map(), map()) :: :ok | {:error, term()}
  def persist_transition(previous_state, next_state) when is_map(previous_state) and is_map(next_state) do
    if enabled?() do
      new_events =
        next_state.events
        |> Enum.filter(&(&1.sequence > Map.get(previous_state, :event_sequence, 0)))

      with {:ok, _event_records} <- RecordStore.append_events(new_events, actor: @persistence_actor),
           {:ok, _snapshot_record} <-
             RecordStore.upsert_snapshot(snapshot_record_attrs(Snapshot.from_state(next_state)),
               actor: @persistence_actor
             ) do
        :ok
      end
    else
      :ok
    end
  end

  @spec persist_snapshot(map()) :: :ok | {:error, term()}
  def persist_snapshot(snapshot) when is_map(snapshot) do
    if enabled?() do
      case RecordStore.upsert_snapshot(snapshot_record_attrs(snapshot), actor: @persistence_actor) do
        {:ok, _record} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec fetch_snapshot(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def fetch_snapshot(conversation_id, actor \\ @persistence_actor) when is_binary(conversation_id) and is_map(actor) do
    if enabled?() do
      case RecordStore.get_snapshot_by_conversation_id(conversation_id, actor: actor) do
        {:ok, %SnapshotRecord{} = record} -> {:ok, snapshot_from_record(record)}
        {:ok, nil} -> {:error, :conversation_snapshot_not_found}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, :conversation_persistence_disabled}
    end
  end

  @spec events_since(String.t(), non_neg_integer(), map()) :: {:ok, [map()]} | {:error, term()}
  def events_since(conversation_id, after_sequence, actor \\ @persistence_actor)
      when is_binary(conversation_id) and is_integer(after_sequence) and after_sequence >= 0 and is_map(actor) do
    if enabled?() do
      RecordStore.events_since(conversation_id, after_sequence, actor: actor)
    else
      {:error, :conversation_persistence_disabled}
    end
  end

  @spec restore_state(Conversation.t()) :: {:ok, map()} | {:ok, nil} | {:error, term()}
  def restore_state(%Conversation{} = conversation) do
    if enabled?() do
      with {:ok, snapshot} <- fetch_snapshot(conversation.id),
           {:ok, event_summaries} <- events_since(conversation.id, 0) do
        {:ok, Snapshot.restore_state(conversation, snapshot, event_summaries)}
      else
        {:error, :conversation_snapshot_not_found} -> {:ok, nil}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, nil}
    end
  end

  defp snapshot_record_attrs(snapshot) do
    %{
      conversation_id: map_get(snapshot, :conversation_id),
      managed_repo_id: map_get(snapshot, :managed_repo_id),
      work_item_id: map_get(snapshot, :work_item_id),
      status: map_get(snapshot, :status),
      admission_paused: map_get(snapshot, :admission_paused, false),
      child_execution_paused: map_get(snapshot, :child_execution_paused, false),
      active_turn_id: map_get(snapshot, :active_turn_id),
      active_child_work_id: map_get(snapshot, :active_child_work_id),
      queued_turn_ids: map_get(snapshot, :queued_turn_ids, []),
      turns: map_get(snapshot, :turns, []),
      child_works: map_get(snapshot, :child_works, []),
      control_history: map_get(snapshot, :control_history, []),
      last_event_sequence: map_get(snapshot, :last_event_sequence, 0),
      event_count: map_get(snapshot, :event_count, 0),
      events: map_get(snapshot, :events, []),
      shared_context: map_get(snapshot, :shared_context, %{}),
      captured_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
    }
  end

  defp snapshot_from_record(%SnapshotRecord{} = record) do
    shared_context = record.shared_context || %{}

    %{
      conversation_id: record.conversation_id,
      managed_repo_id: record.managed_repo_id,
      work_item_id: record.work_item_id,
      scope: map_get(shared_context, "scope"),
      attachment_mode: map_get(shared_context, "attachment_mode"),
      work_resolution: map_get(shared_context, "work_resolution"),
      status: record.status,
      admission_paused: record.admission_paused,
      child_execution_paused: record.child_execution_paused,
      active_turn_id: record.active_turn_id,
      active_turn:
        record.active_turn_id &&
          Enum.find(record.turns, fn turn -> map_get(turn, :id) == record.active_turn_id end),
      active_child_work_id: record.active_child_work_id,
      active_child_work:
        record.active_child_work_id &&
          Enum.find(record.child_works, fn child_work -> map_get(child_work, :id) == record.active_child_work_id end),
      queued_turn_ids: record.queued_turn_ids,
      turns: record.turns,
      child_works: record.child_works,
      control_history: record.control_history,
      last_event_sequence: record.last_event_sequence,
      event_count: record.event_count,
      events: record.events,
      shared_context: shared_context
    }
  end

  defp map_get(map, key, default \\ nil) when is_map(map) do
    string_key =
      case key do
        atom when is_atom(atom) -> Atom.to_string(atom)
        binary when is_binary(binary) -> binary
      end

    cond do
      Map.has_key?(map, key) -> Map.get(map, key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end
end
