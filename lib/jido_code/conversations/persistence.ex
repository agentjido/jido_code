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
  alias JidoCode.Conversations.{Conversation, Event, EventRecord, Snapshot, SnapshotRecord}
  alias JidoCode.Repo

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

      case Repo.transaction(fn ->
             with :ok <- persist_events(new_events),
                  {:ok, _record} <- upsert_snapshot(Snapshot.from_state(next_state)) do
               :ok
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec persist_snapshot(map()) :: :ok | {:error, term()}
  def persist_snapshot(snapshot) when is_map(snapshot) do
    if enabled?() do
      case Repo.transaction(fn ->
             case upsert_snapshot(snapshot) do
               {:ok, _record} -> :ok
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, :ok} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  @spec fetch_snapshot(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def fetch_snapshot(conversation_id, actor \\ @persistence_actor) when is_binary(conversation_id) and is_map(actor) do
    if enabled?() do
      case SnapshotRecord.get_by_conversation_id(conversation_id, actor: actor) do
        {:ok, %SnapshotRecord{} = record} -> {:ok, snapshot_from_record(record)}
        {:error, %Ash.Error.Query.NotFound{}} -> {:error, :conversation_snapshot_not_found}
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
      case EventRecord.after_sequence(conversation_id, after_sequence, actor: actor) do
        {:ok, records} -> {:ok, Enum.map(records, &event_from_record/1)}
        {:error, reason} -> {:error, reason}
      end
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

  defp persist_events(events) when is_list(events) do
    Enum.reduce_while(events, :ok, fn %Event{} = event, :ok ->
      case EventRecord.append(event_record_attrs(event), actor: @persistence_actor) do
        {:ok, _record} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp upsert_snapshot(snapshot) do
    SnapshotRecord.upsert_for_conversation(snapshot_record_attrs(snapshot), actor: @persistence_actor)
  end

  defp event_record_attrs(%Event{} = event) do
    %{
      id: event.id,
      conversation_id: event.conversation_id,
      sequence: event.sequence,
      name: event.name,
      actor: event.actor,
      message_id: event.message_id,
      turn_id: event.turn_id,
      child_work_id: event.child_work_id,
      tool_call_id: event.tool_call_id,
      correlation: event.correlation,
      payload: event.payload,
      occurred_at: event.occurred_at
    }
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
    %{
      conversation_id: record.conversation_id,
      managed_repo_id: record.managed_repo_id,
      work_item_id: record.work_item_id,
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
      shared_context: record.shared_context
    }
  end

  defp event_from_record(%EventRecord{} = record) do
    %{
      id: record.id,
      sequence: record.sequence,
      conversation_id: record.conversation_id,
      name: record.name,
      occurred_at: record.occurred_at,
      actor: record.actor,
      message_id: record.message_id,
      turn_id: record.turn_id,
      child_work_id: record.child_work_id,
      tool_call_id: record.tool_call_id,
      correlation: record.correlation,
      payload: record.payload
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
