defmodule JidoCode.Conversations.RecordStore do
  @moduledoc """
  Store-backed conversation records, event log, and snapshots.
  """

  alias JidoCode.ControlPlane.RecordStore, as: Store
  alias JidoCode.Conversations.{Conversation, Event, EventRecord, SnapshotRecord}

  @conversation_statuses %{
    "active" => :active,
    "paused" => :paused,
    "completed" => :completed,
    "cancelled" => :cancelled
  }

  @conversation_scopes %{
    "repo_scoped" => :repo_scoped,
    "work_item_scoped" => :work_item_scoped
  }

  @attachment_modes %{
    "pre_work" => :pre_work,
    "existing_work_item" => :existing_work_item,
    "synthesized_work_item" => :synthesized_work_item
  }

  @atom_key_aliases %{
    id: :id
  }

  @top_level_key_aliases %{
    "id" => :id,
    "conversation_id" => :conversation_id,
    "conversationId" => :conversation_id,
    "conversation_event_id" => :conversation_event_id,
    "conversationEventId" => :conversation_event_id,
    "conversation_snapshot_id" => :conversation_snapshot_id,
    "conversationSnapshotId" => :conversation_snapshot_id,
    "managed_repo_id" => :managed_repo_id,
    "managedRepoId" => :managed_repo_id,
    "work_item_id" => :work_item_id,
    "workItemId" => :work_item_id,
    "source_key" => :source_key,
    "conversationEventSourceKey" => :source_key,
    "conversationSnapshotSourceKey" => :source_key,
    "status" => :status,
    "recordStatus" => :status,
    "scope" => :scope,
    "conversationScope" => :scope,
    "attachment_mode" => :attachment_mode,
    "attachmentMode" => :attachment_mode,
    "source" => :source,
    "title" => :title,
    "objective" => :objective,
    "initiating_actor" => :initiating_actor,
    "initiatingActorJson" => :initiating_actor,
    "source_metadata" => :source_metadata,
    "sourceMetadataJson" => :source_metadata,
    "conversation_metadata" => :conversation_metadata,
    "conversationMetadataJson" => :conversation_metadata,
    "started_at" => :started_at,
    "startedAt" => :started_at,
    "last_activity_at" => :last_activity_at,
    "lastActivityAt" => :last_activity_at,
    "sequence" => :sequence,
    "name" => :name,
    "eventName" => :name,
    "actor" => :actor,
    "actorJson" => :actor,
    "message_id" => :message_id,
    "messageId" => :message_id,
    "turn_id" => :turn_id,
    "turnId" => :turn_id,
    "child_work_id" => :child_work_id,
    "childWorkId" => :child_work_id,
    "tool_call_id" => :tool_call_id,
    "toolCallId" => :tool_call_id,
    "correlation" => :correlation,
    "correlationJson" => :correlation,
    "payload" => :payload,
    "payloadJson" => :payload,
    "occurred_at" => :occurred_at,
    "occurredAt" => :occurred_at,
    "admission_paused" => :admission_paused,
    "admissionPaused" => :admission_paused,
    "child_execution_paused" => :child_execution_paused,
    "childExecutionPaused" => :child_execution_paused,
    "active_turn_id" => :active_turn_id,
    "activeTurnId" => :active_turn_id,
    "active_child_work_id" => :active_child_work_id,
    "activeChildWorkId" => :active_child_work_id,
    "queued_turn_ids" => :queued_turn_ids,
    "queuedTurnIdsJson" => :queued_turn_ids,
    "turns" => :turns,
    "turnsJson" => :turns,
    "child_works" => :child_works,
    "childWorksJson" => :child_works,
    "control_history" => :control_history,
    "controlHistoryJson" => :control_history,
    "last_event_sequence" => :last_event_sequence,
    "lastEventSequence" => :last_event_sequence,
    "event_count" => :event_count,
    "eventCount" => :event_count,
    "events" => :events,
    "eventsJson" => :events,
    "shared_context" => :shared_context,
    "sharedContextJson" => :shared_context,
    "captured_at" => :captured_at,
    "capturedAt" => :captured_at,
    "inserted_at" => :inserted_at,
    "insertedAt" => :inserted_at,
    "updated_at" => :updated_at,
    "updatedAt" => :updated_at,
    "metadata" => :metadata,
    "metadataJson" => :metadata,
    "subject_iri" => :subject_iri
  }

  @map_fields [
    :initiating_actor,
    :source_metadata,
    :conversation_metadata,
    :actor,
    :correlation,
    :payload,
    :shared_context,
    :metadata
  ]

  @list_fields [
    :queued_turn_ids,
    :turns,
    :child_works,
    :control_history,
    :events
  ]

  @spec create_conversation(map(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def create_conversation(attrs, opts \\ []) when is_map(attrs) do
    attrs
    |> Map.put_new(:conversation_id, map_get(attrs, :conversation_id) || map_get(attrs, :id) || Ecto.UUID.generate())
    |> upsert_conversation(opts)
  end

  @spec upsert_conversation(map(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def upsert_conversation(attrs, opts \\ [])

  def upsert_conversation(attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)

    with {:ok, existing} <- get_existing(:conversation, attrs, opts),
         record <- conversation_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:conversation, record, opts) do
      {:ok, to_conversation(saved_record)}
    end
  end

  def upsert_conversation(_attrs, _opts), do: {:error, :invalid_conversation_attrs}

  @spec update_conversation(Conversation.t(), map(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def update_conversation(%Conversation{} = conversation, attrs, opts \\ []) when is_map(attrs) do
    conversation
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__])
    |> Map.merge(attrs)
    |> Map.put(:conversation_id, conversation.id)
    |> upsert_conversation(opts)
  end

  @spec get_conversation(String.t(), keyword()) :: {:ok, Conversation.t() | nil} | {:error, term()}
  def get_conversation(conversation_id, opts \\ []) do
    with {:ok, record} <-
           Store.get_by_identity(:conversation, :unique_conversation_id, "conversationId", conversation_id, opts) do
      {:ok, record && to_conversation(record)}
    end
  end

  @spec list_conversations(map(), keyword()) :: {:ok, [Conversation.t()]} | {:error, term()}
  def list_conversations(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:conversation, filters, opts, &to_conversation/1)
  end

  @spec append_event(Event.t() | map(), keyword()) :: {:ok, EventRecord.t()} | {:error, term()}
  def append_event(event, opts \\ [])

  def append_event(%Event{} = event, opts), do: event |> Event.summary() |> append_event(opts)

  def append_event(attrs, opts) when is_map(attrs) do
    attrs = normalize_record_map(attrs)
    conversation_id = normalize_optional_string(map_get(attrs, :conversation_id))

    attrs =
      case normalize_positive_integer(map_get(attrs, :sequence)) do
        nil -> Map.put(attrs, :sequence, next_sequence(conversation_id, opts))
        sequence -> Map.put(attrs, :sequence, sequence)
      end
      |> put_conversation_scope(opts)

    with {:ok, existing} <- get_existing(:conversation_event, attrs, opts),
         record <- event_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:conversation_event, record, opts) do
      {:ok, to_event_record(saved_record)}
    end
  end

  def append_event(_attrs, _opts), do: {:error, :invalid_conversation_event_attrs}

  @spec append_events([Event.t() | map()], keyword()) :: {:ok, [EventRecord.t()]} | {:error, term()}
  def append_events(events, opts \\ []) when is_list(events) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, acc} ->
      case append_event(event, opts) do
        {:ok, record} -> {:cont, {:ok, [record | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, records} -> {:ok, Enum.reverse(records)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec list_event_records(map(), keyword()) :: {:ok, [EventRecord.t()]} | {:error, term()}
  def list_event_records(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:conversation_event, filters, opts, &to_event_record/1)
  end

  @spec events_since(String.t(), non_neg_integer(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def events_since(conversation_id, after_sequence, opts \\ [])
      when is_binary(conversation_id) and is_integer(after_sequence) and after_sequence >= 0 do
    with {:ok, event_records} <-
           list_event_records(%{conversation_id: conversation_id}, Keyword.put(opts, :query, sort: [sequence: :asc])) do
      events =
        event_records
        |> Enum.filter(&(&1.sequence > after_sequence))
        |> Enum.map(&event_record_summary/1)

      {:ok, events}
    end
  end

  @spec upsert_snapshot(map(), keyword()) :: {:ok, SnapshotRecord.t()} | {:error, term()}
  def upsert_snapshot(attrs, opts \\ [])

  def upsert_snapshot(attrs, opts) when is_map(attrs) do
    attrs =
      attrs
      |> normalize_record_map()
      |> put_conversation_scope(opts)

    with {:ok, existing} <- get_existing(:conversation_snapshot, attrs, opts),
         record <- snapshot_record(attrs, existing),
         {:ok, saved_record} <- Store.upsert(:conversation_snapshot, record, opts) do
      {:ok, to_snapshot_record(saved_record)}
    end
  end

  def upsert_snapshot(_attrs, _opts), do: {:error, :invalid_conversation_snapshot_attrs}

  @spec get_snapshot_by_conversation_id(String.t(), keyword()) :: {:ok, SnapshotRecord.t() | nil} | {:error, term()}
  def get_snapshot_by_conversation_id(conversation_id, opts \\ []) do
    with {:ok, record} <-
           Store.get_by_identity(
             :conversation_snapshot,
             :unique_conversation,
             "conversationSnapshotSourceKey",
             conversation_id,
             opts
           ) do
      {:ok, record && to_snapshot_record(record)}
    end
  end

  @spec list_snapshot_records(map(), keyword()) :: {:ok, [SnapshotRecord.t()]} | {:error, term()}
  def list_snapshot_records(filters \\ %{}, opts \\ []) when is_map(filters) do
    list(:conversation_snapshot, filters, opts, &to_snapshot_record/1)
  end

  defp get_existing(:conversation, attrs, opts) do
    Store.get_by_identity(
      :conversation,
      :unique_conversation_id,
      "conversationId",
      normalize_optional_string(map_get(attrs, :conversation_id) || map_get(attrs, :id)),
      opts
    )
  end

  defp get_existing(:conversation_event, attrs, opts) do
    Store.get_by_identity(
      :conversation_event,
      :unique_conversation_sequence,
      "conversationEventSourceKey",
      conversation_event_source_key(attrs),
      opts
    )
  end

  defp get_existing(:conversation_snapshot, attrs, opts) do
    Store.get_by_identity(
      :conversation_snapshot,
      :unique_conversation,
      "conversationSnapshotSourceKey",
      conversation_snapshot_source_key(attrs),
      opts
    )
  end

  defp conversation_record(attrs, existing) do
    now = now()
    started_at = normalize_datetime(map_get(attrs, :started_at)) || existing_datetime(existing, :started_at) || now

    %{
      conversation_id:
        existing_id(existing, :conversation_id) ||
          normalize_optional_string(map_get(attrs, :conversation_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      status: normalize_atom(map_get(attrs, :status), @conversation_statuses, :active),
      scope: normalize_atom(map_get(attrs, :scope), @conversation_scopes, :repo_scoped),
      attachment_mode: normalize_atom(map_get(attrs, :attachment_mode), @attachment_modes, :pre_work),
      source: normalize_string(map_get(attrs, :source), "conversation"),
      title: normalize_optional_string(map_get(attrs, :title)),
      objective: normalize_optional_string(map_get(attrs, :objective)),
      initiating_actor: decode_json_map(map_get(attrs, :initiating_actor, %{})),
      source_metadata: decode_json_map(map_get(attrs, :source_metadata, %{})),
      conversation_metadata: decode_json_map(map_get(attrs, :conversation_metadata, %{})),
      started_at: started_at,
      last_activity_at: normalize_datetime(map_get(attrs, :last_activity_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp event_record(attrs, existing) do
    now = now()

    %{
      conversation_event_id:
        existing_id(existing, :conversation_event_id) ||
          normalize_optional_string(map_get(attrs, :conversation_event_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      conversation_id: normalize_optional_string(map_get(attrs, :conversation_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      source_key: conversation_event_source_key(attrs),
      sequence: normalize_positive_integer(map_get(attrs, :sequence)) || 1,
      name: normalize_string(map_get(attrs, :name), "unknown"),
      actor: decode_json_map(map_get(attrs, :actor, %{})),
      message_id: normalize_optional_string(map_get(attrs, :message_id)),
      turn_id: normalize_optional_string(map_get(attrs, :turn_id)),
      child_work_id: normalize_optional_string(map_get(attrs, :child_work_id)),
      tool_call_id: normalize_optional_string(map_get(attrs, :tool_call_id)),
      correlation: decode_json_map(map_get(attrs, :correlation, %{})),
      payload: decode_json_map(map_get(attrs, :payload, %{})),
      occurred_at: normalize_datetime(map_get(attrs, :occurred_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp snapshot_record(attrs, existing) do
    now = now()

    %{
      conversation_snapshot_id:
        existing_id(existing, :conversation_snapshot_id) ||
          normalize_optional_string(map_get(attrs, :conversation_snapshot_id) || map_get(attrs, :id)) ||
          Ecto.UUID.generate(),
      conversation_id: normalize_optional_string(map_get(attrs, :conversation_id)),
      managed_repo_id: normalize_optional_string(map_get(attrs, :managed_repo_id)),
      work_item_id: normalize_optional_string(map_get(attrs, :work_item_id)),
      source_key: conversation_snapshot_source_key(attrs),
      status: normalize_atom(map_get(attrs, :status), @conversation_statuses, :active),
      admission_paused: normalize_boolean(map_get(attrs, :admission_paused), false),
      child_execution_paused: normalize_boolean(map_get(attrs, :child_execution_paused), false),
      active_turn_id: normalize_optional_string(map_get(attrs, :active_turn_id)),
      active_child_work_id: normalize_optional_string(map_get(attrs, :active_child_work_id)),
      queued_turn_ids: decode_json_list(map_get(attrs, :queued_turn_ids, []), []),
      turns: decode_json_list(map_get(attrs, :turns, []), []),
      child_works: decode_json_list(map_get(attrs, :child_works, []), []),
      control_history: decode_json_list(map_get(attrs, :control_history, []), []),
      last_event_sequence: normalize_non_negative_integer(map_get(attrs, :last_event_sequence), 0),
      event_count: normalize_non_negative_integer(map_get(attrs, :event_count), 0),
      events: decode_json_list(map_get(attrs, :events, []), []),
      shared_context: decode_json_map(map_get(attrs, :shared_context, %{})),
      captured_at: normalize_datetime(map_get(attrs, :captured_at)) || now,
      inserted_at: existing_datetime(existing, :inserted_at) || normalize_datetime(map_get(attrs, :inserted_at)) || now,
      updated_at: now,
      metadata: decode_json_map(map_get(attrs, :metadata, %{}))
    }
  end

  defp list(record_type, filters, opts, mapper) do
    query = Keyword.get(opts, :query)
    merged_filters = Map.merge(query_filter(query), normalize_filter_map(filters))
    store_opts = opts |> Keyword.delete(:query) |> Keyword.put(:query, %{limit: 500, offset: 0})

    with {:ok, records} <- Store.list(record_type, %{}, store_opts) do
      results =
        records
        |> Enum.map(mapper)
        |> Enum.filter(&matches_filters?(&1, merged_filters))
        |> sort_records(query_sort(query))
        |> limit_records(query_limit(query))

      {:ok, results}
    end
  end

  defp to_conversation(record) do
    record = normalize_record_map(record)

    %Conversation{
      id: map_get(record, :conversation_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      work_item_id: map_get(record, :work_item_id),
      status: normalize_atom(map_get(record, :status), @conversation_statuses, :active),
      scope: normalize_atom(map_get(record, :scope), @conversation_scopes, :repo_scoped),
      attachment_mode: normalize_atom(map_get(record, :attachment_mode), @attachment_modes, :pre_work),
      source: normalize_string(map_get(record, :source), "conversation"),
      title: normalize_optional_string(map_get(record, :title)),
      objective: normalize_optional_string(map_get(record, :objective)),
      initiating_actor: decode_json_map(map_get(record, :initiating_actor, %{})),
      source_metadata: decode_json_map(map_get(record, :source_metadata, %{})),
      conversation_metadata: decode_json_map(map_get(record, :conversation_metadata, %{})),
      started_at: normalize_datetime(map_get(record, :started_at)),
      last_activity_at: normalize_datetime(map_get(record, :last_activity_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp to_event_record(record) do
    record = normalize_record_map(record)

    %EventRecord{
      id: map_get(record, :conversation_event_id),
      conversation_id: map_get(record, :conversation_id),
      sequence: normalize_positive_integer(map_get(record, :sequence)) || 1,
      name: normalize_string(map_get(record, :name), "unknown"),
      actor: decode_json_map(map_get(record, :actor, %{})),
      message_id: normalize_optional_string(map_get(record, :message_id)),
      turn_id: normalize_optional_string(map_get(record, :turn_id)),
      child_work_id: normalize_optional_string(map_get(record, :child_work_id)),
      tool_call_id: normalize_optional_string(map_get(record, :tool_call_id)),
      correlation: decode_json_map(map_get(record, :correlation, %{})),
      payload: decode_json_map(map_get(record, :payload, %{})),
      occurred_at: normalize_datetime(map_get(record, :occurred_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp to_snapshot_record(record) do
    record = normalize_record_map(record)

    %SnapshotRecord{
      id: map_get(record, :conversation_snapshot_id),
      conversation_id: map_get(record, :conversation_id),
      managed_repo_id: map_get(record, :managed_repo_id),
      work_item_id: map_get(record, :work_item_id),
      status: normalize_atom(map_get(record, :status), @conversation_statuses, :active),
      admission_paused: normalize_boolean(map_get(record, :admission_paused), false),
      child_execution_paused: normalize_boolean(map_get(record, :child_execution_paused), false),
      active_turn_id: normalize_optional_string(map_get(record, :active_turn_id)),
      active_child_work_id: normalize_optional_string(map_get(record, :active_child_work_id)),
      queued_turn_ids: decode_json_list(map_get(record, :queued_turn_ids, []), []),
      turns: decode_json_list(map_get(record, :turns, []), []),
      child_works: decode_json_list(map_get(record, :child_works, []), []),
      control_history: decode_json_list(map_get(record, :control_history, []), []),
      last_event_sequence: normalize_non_negative_integer(map_get(record, :last_event_sequence), 0),
      event_count: normalize_non_negative_integer(map_get(record, :event_count), 0),
      events: decode_json_list(map_get(record, :events, []), []),
      shared_context: decode_json_map(map_get(record, :shared_context, %{})),
      captured_at: normalize_datetime(map_get(record, :captured_at)),
      inserted_at: normalize_datetime(map_get(record, :inserted_at)),
      updated_at: normalize_datetime(map_get(record, :updated_at))
    }
    |> Map.put(:__metadata__, %{control_plane_record: record})
  end

  defp event_record_summary(%EventRecord{} = record) do
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

  defp next_sequence(nil, _opts), do: 1

  defp next_sequence(conversation_id, opts) do
    case list_event_records(%{conversation_id: conversation_id}, opts) do
      {:ok, event_records} ->
        event_records
        |> Enum.map(& &1.sequence)
        |> Enum.max(fn -> 0 end)
        |> Kernel.+(1)

      {:error, _reason} ->
        1
    end
  end

  defp conversation_event_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      compact_join([map_get(record, :conversation_id), normalize_positive_integer(map_get(record, :sequence))])
  end

  defp conversation_snapshot_source_key(record) do
    normalize_optional_string(map_get(record, :source_key)) ||
      normalize_optional_string(map_get(record, :conversation_id))
  end

  defp put_conversation_scope(attrs, opts) do
    conversation_id = normalize_optional_string(map_get(attrs, :conversation_id))

    cond do
      is_nil(conversation_id) ->
        attrs

      normalize_optional_string(map_get(attrs, :managed_repo_id)) ->
        attrs

      true ->
        case get_conversation(conversation_id, opts) do
          {:ok, %Conversation{} = conversation} ->
            attrs
            |> put_if_missing(:managed_repo_id, conversation.managed_repo_id)
            |> put_if_missing(:work_item_id, conversation.work_item_id)

          _other ->
            attrs
        end
    end
  end

  defp put_if_missing(attrs, _key, nil), do: attrs

  defp put_if_missing(attrs, key, value) do
    case normalize_optional_string(map_get(attrs, key)) do
      nil -> Map.put(attrs, key, value)
      _existing -> attrs
    end
  end

  defp compact_join(values) do
    values
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(":")
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp existing_id(nil, _field), do: nil
  defp existing_id(existing, field), do: normalize_optional_string(map_get(existing, field) || map_get(existing, :id))

  defp existing_datetime(nil, _field), do: nil
  defp existing_datetime(existing, field), do: normalize_datetime(map_get(existing, field))

  defp query_filter(query) when is_list(query), do: query |> Keyword.get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(query) when is_map(query), do: query |> map_get(:filter, %{}) |> normalize_filter_map()
  defp query_filter(_query), do: %{}

  defp query_sort(query) when is_list(query), do: Keyword.get(query, :sort, [])
  defp query_sort(query) when is_map(query), do: map_get(query, :sort, [])
  defp query_sort(_query), do: []

  defp query_limit(query) when is_list(query), do: Keyword.get(query, :limit)
  defp query_limit(query) when is_map(query), do: map_get(query, :limit)
  defp query_limit(_query), do: nil

  defp normalize_filter_map(filters) when is_list(filters), do: Map.new(filters)
  defp normalize_filter_map(filters) when is_map(filters), do: filters
  defp normalize_filter_map(_filters), do: %{}

  defp sort_records(records, [{field, direction} | _rest]) do
    sorter = if direction == :desc or direction == "desc", do: :desc, else: :asc
    Enum.sort_by(records, &sort_value(Map.get(&1, field)), sorter)
  rescue
    _error -> records
  end

  defp sort_records(records, _sort), do: records

  defp sort_value(%DateTime{} = value), do: DateTime.to_unix(value, :microsecond)
  defp sort_value(nil), do: -1
  defp sort_value(value) when is_atom(value), do: Atom.to_string(value)
  defp sort_value(value), do: value

  defp limit_records(records, limit) when is_integer(limit) and limit >= 0, do: Enum.take(records, limit)
  defp limit_records(records, _limit), do: records

  defp matches_filters?(record, filters) do
    Enum.all?(filters, fn {key, expected} ->
      actual = Map.get(record, key) || Map.get(record, to_string(key))
      values_equal?(actual, expected)
    end)
  end

  defp values_equal?(actual, expected) when is_list(expected), do: Enum.any?(expected, &values_equal?(actual, &1))
  defp values_equal?(actual, expected), do: normalize_comparable(actual) == normalize_comparable(expected)

  defp normalize_comparable(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_comparable(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_comparable(value), do: value

  defp normalize_record_map(%Ash.NotLoaded{}), do: %{}

  defp normalize_record_map(%_{} = value) do
    value
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__])
    |> normalize_record_map()
  end

  defp normalize_record_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key = normalize_key(key)
      normalized_value = normalize_record_value(normalized_key, nested_value)
      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_key(key) when is_atom(key), do: Map.get(@atom_key_aliases, key, key)

  defp normalize_key(key) when is_binary(key) do
    Map.get(@top_level_key_aliases, key) ||
      Map.get(@top_level_key_aliases, Macro.underscore(key)) ||
      key
  end

  defp normalize_key(key), do: key |> to_string() |> normalize_key()

  defp normalize_record_value(key, value) when key in @map_fields, do: decode_json_map(value)
  defp normalize_record_value(key, value) when key in @list_fields, do: decode_json_list(value, [])
  defp normalize_record_value(_key, %Ash.NotLoaded{}), do: nil
  defp normalize_record_value(_key, %Ecto.Schema.Metadata{}), do: nil
  defp normalize_record_value(_key, %DateTime{} = value), do: DateTime.truncate(value, :microsecond)
  defp normalize_record_value(_key, %NaiveDateTime{} = value), do: value
  defp normalize_record_value(_key, value) when is_map(value), do: normalize_map(value)
  defp normalize_record_value(_key, value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_record_value(_key, value), do: value

  defp decode_json_map(value) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_map(decoded) -> normalize_map(decoded)
      _other -> %{}
    end
  end

  defp decode_json_map(%Ash.NotLoaded{}), do: %{}
  defp decode_json_map(%Ecto.Schema.Metadata{}), do: %{}
  defp decode_json_map(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp decode_json_map(value) when is_map(value), do: normalize_map(value)
  defp decode_json_map(_value), do: %{}

  defp decode_json_list(value, default) when is_binary(value) do
    case Jason.decode(value) do
      {:ok, decoded} when is_list(decoded) -> Enum.map(decoded, &normalize_nested_value/1)
      _other -> default
    end
  end

  defp decode_json_list(value, _default) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp decode_json_list(_value, default), do: default

  defp normalize_map(%Ash.NotLoaded{}), do: %{}
  defp normalize_map(%Ecto.Schema.Metadata{}), do: %{}

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      Map.put(acc, to_string(key), normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(%Ash.NotLoaded{}), do: nil
  defp normalize_nested_value(%Ecto.Schema.Metadata{}), do: nil

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp normalize_nested_value(%_{} = value), do: value |> Map.from_struct() |> normalize_map()
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)

  defp normalize_datetime(%NaiveDateTime{} = datetime) do
    case DateTime.from_naive(datetime, "Etc/UTC") do
      {:ok, parsed_datetime} -> normalize_datetime(parsed_datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> normalize_datetime(datetime)
      _other -> nil
    end
  end

  defp normalize_datetime(_value), do: nil

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_positive_integer(value) when is_integer(value) and value > 0, do: value

  defp normalize_positive_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> nil
    end
  end

  defp normalize_positive_integer(_value), do: nil

  defp normalize_non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp normalize_non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> default
    end
  end

  defp normalize_non_negative_integer(_value, default), do: default

  defp normalize_boolean(value, _default) when is_boolean(value), do: value
  defp normalize_boolean("true", _default), do: true
  defp normalize_boolean("false", _default), do: false
  defp normalize_boolean(_value, default), do: default

  defp normalize_atom(value, known_atoms, default) when is_atom(value) do
    if value in Map.values(known_atoms), do: value, else: default
  end

  defp normalize_atom(value, known_atoms, default) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
    |> case do
      "" -> default
      normalized -> Map.get(known_atoms, normalized, default)
    end
  end

  defp normalize_atom(_value, _known_atoms, default), do: default

  defp map_get(map, key, default \\ nil)
  defp map_get(map, key, default) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
