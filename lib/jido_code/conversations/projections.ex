defmodule JidoCode.Conversations.Projections do
  @moduledoc """
  Product-shaped conversation read projections for operator surfaces.
  """

  alias JidoCode.Conversations.{Conversation, EventRecord, RecordStore, SnapshotRecord}

  @active_statuses [:active, :paused]
  @default_limit 25
  @default_event_limit 50

  @spec active_for_managed_repo(String.t(), keyword()) :: {:ok, map()}
  def active_for_managed_repo(managed_repo_id, opts \\ []) when is_binary(managed_repo_id) do
    limit = limit(opts, @default_limit)

    case RecordStore.list_conversations(
           %{managed_repo_id: managed_repo_id, status: @active_statuses},
           Keyword.merge([query: [sort: [last_activity_at: :desc], limit: limit]], store_opts(opts))
         ) do
      {:ok, conversations} ->
        {:ok,
         ready_projection(:active_conversations, %{
           managed_repo_id: managed_repo_id,
           result_group: result_group(conversations, limit),
           conversations: Enum.map(conversations, &conversation_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:active_conversations, %{managed_repo_id: managed_repo_id}, reason)}
    end
  end

  @spec active_for_work_item(String.t(), keyword()) :: {:ok, map()}
  def active_for_work_item(work_item_id, opts \\ []) when is_binary(work_item_id) do
    limit = 1

    case RecordStore.list_conversations(
           %{work_item_id: work_item_id, status: @active_statuses},
           Keyword.merge([query: [sort: [last_activity_at: :desc], limit: limit]], store_opts(opts))
         ) do
      {:ok, conversations} ->
        {:ok,
         ready_projection(:active_conversation, %{
           work_item_id: work_item_id,
           result_group: result_group(conversations, limit),
           conversation: conversations |> List.first() |> maybe_summary()
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:active_conversation, %{work_item_id: work_item_id}, reason)}
    end
  end

  @spec historical_for_work_item(String.t(), keyword()) :: {:ok, map()}
  def historical_for_work_item(work_item_id, opts \\ []) when is_binary(work_item_id) do
    limit = limit(opts, @default_limit)

    case RecordStore.list_conversations(
           %{work_item_id: work_item_id},
           Keyword.merge([query: [sort: [last_activity_at: :desc]]], store_opts(opts))
         ) do
      {:ok, conversations} ->
        historical =
          conversations
          |> Enum.reject(&(&1.status in @active_statuses))
          |> Enum.take(limit)

        {:ok,
         ready_projection(:historical_conversations, %{
           work_item_id: work_item_id,
           result_group: result_group(historical, limit),
           conversations: Enum.map(historical, &conversation_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:historical_conversations, %{work_item_id: work_item_id}, reason)}
    end
  end

  @spec clarification_for_managed_repo(String.t(), keyword()) :: {:ok, map()}
  def clarification_for_managed_repo(managed_repo_id, opts \\ []) when is_binary(managed_repo_id) do
    limit = limit(opts, @default_limit)

    case RecordStore.list_snapshot_records(
           %{managed_repo_id: managed_repo_id},
           Keyword.merge([query: [sort: [captured_at: :desc]]], store_opts(opts))
         ) do
      {:ok, snapshots} ->
        clarification_snapshots =
          snapshots
          |> Enum.filter(&clarification_snapshot?/1)
          |> Enum.take(limit)

        {:ok,
         ready_projection(:clarification_conversations, %{
           managed_repo_id: managed_repo_id,
           result_group: result_group(clarification_snapshots, limit),
           snapshots: Enum.map(clarification_snapshots, &snapshot_summary/1)
         })}

      {:error, reason} ->
        {:ok, degraded_projection(:clarification_conversations, %{managed_repo_id: managed_repo_id}, reason)}
    end
  end

  @spec event_window(String.t(), keyword()) :: {:ok, map()}
  def event_window(conversation_id, opts \\ []) when is_binary(conversation_id) do
    after_sequence = non_negative_integer(Keyword.get(opts, :after_sequence), 0)
    limit = limit(opts, @default_event_limit)

    case RecordStore.list_event_records(
           %{conversation_id: conversation_id},
           Keyword.merge([query: [sort: [sequence: :asc]]], store_opts(opts))
         ) do
      {:ok, event_records} ->
        window =
          event_records
          |> Enum.filter(&(&1.sequence > after_sequence))
          |> Enum.sort_by(& &1.sequence, :asc)
          |> Enum.take(limit + 1)

        events = Enum.take(window, limit)

        {:ok,
         ready_projection(:conversation_event_window, %{
           conversation_id: conversation_id,
           after_sequence: after_sequence,
           limit: limit,
           has_more?: length(window) > limit,
           next_after_sequence: events |> List.last() |> event_sequence(after_sequence),
           events: Enum.map(events, &event_summary/1)
         })}

      {:error, reason} ->
        {:ok,
         degraded_projection(
           :conversation_event_window,
           %{conversation_id: conversation_id, after_sequence: after_sequence, limit: limit},
           reason
         )}
    end
  end

  @spec latest_snapshot_prompt(String.t(), keyword()) :: {:ok, map()}
  def latest_snapshot_prompt(conversation_id, opts \\ []) when is_binary(conversation_id) do
    case RecordStore.get_snapshot_by_conversation_id(conversation_id, store_opts(opts)) do
      {:ok, %SnapshotRecord{} = snapshot} ->
        {:ok,
         ready_projection(:conversation_snapshot_prompt, %{
           conversation_id: conversation_id,
           snapshot: snapshot_summary(snapshot),
           prompt_projection: prompt_projection(snapshot)
         })}

      {:ok, nil} ->
        {:ok,
         ready_projection(:conversation_snapshot_prompt, %{
           conversation_id: conversation_id,
           snapshot: nil,
           prompt_projection: empty_prompt_projection()
         })}

      {:error, reason} ->
        {:ok,
         degraded_projection(
           :conversation_snapshot_prompt,
           %{conversation_id: conversation_id, snapshot: nil, prompt_projection: empty_prompt_projection()},
           reason
         )}
    end
  end

  defp ready_projection(kind, fields) do
    Map.merge(
      %{
        kind: kind,
        status: :ready,
        degraded?: false,
        stale?: false
      },
      fields
    )
  end

  defp degraded_projection(kind, fields, reason) do
    Map.merge(
      %{
        kind: kind,
        status: :degraded,
        degraded?: true,
        stale?: true,
        result_group: result_group([], 0),
        error: %{type: :conversation_projection_failed, detail: inspect(reason)}
      },
      fields
    )
  end

  defp result_group(items, limit) do
    %{
      count: length(items),
      limit: limit,
      empty?: items == []
    }
  end

  defp conversation_summary(%Conversation{} = conversation) do
    %{
      id: conversation.id,
      managed_repo_id: conversation.managed_repo_id,
      work_item_id: conversation.work_item_id,
      status: conversation.status,
      scope: conversation.scope,
      attachment_mode: conversation.attachment_mode,
      title: conversation.title,
      objective: conversation.objective,
      source: conversation.source,
      started_at: conversation.started_at,
      last_activity_at: conversation.last_activity_at
    }
  end

  defp maybe_summary(%Conversation{} = conversation), do: conversation_summary(conversation)
  defp maybe_summary(_conversation), do: nil

  defp event_summary(%EventRecord{} = event_record) do
    %{
      id: event_record.id,
      conversation_id: event_record.conversation_id,
      sequence: event_record.sequence,
      name: event_record.name,
      actor: event_record.actor,
      message_id: event_record.message_id,
      turn_id: event_record.turn_id,
      child_work_id: event_record.child_work_id,
      tool_call_id: event_record.tool_call_id,
      correlation: event_record.correlation,
      payload: event_record.payload,
      occurred_at: event_record.occurred_at
    }
  end

  defp snapshot_summary(%SnapshotRecord{} = snapshot) do
    %{
      id: snapshot.id,
      conversation_id: snapshot.conversation_id,
      managed_repo_id: snapshot.managed_repo_id,
      work_item_id: snapshot.work_item_id,
      status: snapshot.status,
      admission_paused: snapshot.admission_paused,
      child_execution_paused: snapshot.child_execution_paused,
      active_turn_id: snapshot.active_turn_id,
      active_child_work_id: snapshot.active_child_work_id,
      queued_turn_count: length(snapshot.queued_turn_ids || []),
      turn_count: length(snapshot.turns || []),
      child_work_count: length(snapshot.child_works || []),
      last_event_sequence: snapshot.last_event_sequence,
      event_count: snapshot.event_count,
      captured_at: snapshot.captured_at
    }
  end

  defp prompt_projection(%SnapshotRecord{} = snapshot) do
    latest_reset =
      snapshot.shared_context
      |> normalize_map()
      |> Map.get("latest_context_reset")
      |> normalize_map()

    %{
      reset_aware?: latest_reset != %{},
      latest_context_reset: latest_reset_or_nil(latest_reset),
      history_start_sequence: history_start_sequence(latest_reset),
      last_event_sequence: snapshot.last_event_sequence,
      event_count: snapshot.event_count
    }
  end

  defp empty_prompt_projection do
    %{
      reset_aware?: false,
      latest_context_reset: nil,
      history_start_sequence: 0,
      last_event_sequence: 0,
      event_count: 0
    }
  end

  defp clarification_snapshot?(%SnapshotRecord{} = snapshot) do
    snapshot.admission_paused || snapshot.child_execution_paused || is_binary(snapshot.active_child_work_id)
  end

  defp event_sequence(nil, fallback), do: fallback
  defp event_sequence(%EventRecord{} = event_record, _fallback), do: event_record.sequence

  defp latest_reset_or_nil(reset) when reset == %{}, do: nil
  defp latest_reset_or_nil(reset), do: reset

  defp history_start_sequence(%{"reset_sequence" => sequence}), do: non_negative_integer(sequence, 0)
  defp history_start_sequence(_latest_reset), do: 0

  defp limit(opts, default) do
    opts
    |> Keyword.get(:limit, default)
    |> non_negative_integer(default)
  end

  defp non_negative_integer(value, _default) when is_integer(value) and value >= 0, do: value

  defp non_negative_integer(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed >= 0 -> parsed
      _other -> default
    end
  end

  defp non_negative_integer(_value, default), do: default

  defp normalize_map(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} -> {to_string(key), nested_value} end)
  end

  defp normalize_map(_value), do: %{}

  defp store_opts(opts) do
    case Keyword.get(opts, :actor) do
      nil -> []
      actor -> [actor: actor]
    end
  end
end
