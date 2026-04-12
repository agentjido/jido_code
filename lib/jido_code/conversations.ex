defmodule JidoCode.Conversations do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  use Ash.Domain, otp_app: :jido_code, extensions: [AshAdmin.Domain]

  alias JidoCode.Control.Actor
  alias JidoCode.Conversations.{Conversation, EventRecord, SnapshotRecord}
  alias JidoCode.Operations.{Ingress, WorkItem}

  admin do
    show? true
  end

  resources do
    resource Conversation
    resource EventRecord
    resource SnapshotRecord
  end

  @type start_result :: %{
          conversation: Conversation.t(),
          work_item: WorkItem.t() | nil,
          work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped | nil
        }

  @type steer_result :: %{
          conversation: Conversation.t(),
          work_item: WorkItem.t() | nil,
          work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped | nil
        }

  @spec start(map()) :: {:ok, start_result()} | {:error, term()}
  def start(%{} = attrs) do
    with {:ok, context} <- build_start_context(attrs),
         {:ok, conversation} <- Conversation.create(conversation_attrs(context), actor: context.actor) do
      {:ok,
       %{
         conversation: conversation,
         work_item: context.work_item,
         work_action: context.work_action
       }}
    end
  end

  def start(_attrs), do: {:error, :invalid_conversation_start}

  @spec resume(String.t(), keyword()) :: {:ok, Conversation.t()} | {:error, term()}
  def resume(conversation_id, opts \\ []) when is_binary(conversation_id) and is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))

    with {:ok, %Conversation{} = conversation} <- fetch_conversation(conversation_id, actor),
         {:ok, resumed} <-
           Conversation.update(
             conversation,
             %{last_activity_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)},
             actor: actor
           ) do
      {:ok, resumed}
    end
  end

  @spec steer_work(Conversation.t(), map(), keyword()) :: {:ok, steer_result()} | {:error, term()}
  def steer_work(%Conversation{} = conversation, %{} = payload, opts \\ []) when is_list(opts) do
    actor = normalize_actor(Keyword.get(opts, :actor))
    payload = normalize_map(payload)
    shared_context = normalize_map(Keyword.get(opts, :shared_context))
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    requested_work_item_id = optional_string(payload, :work_item_id)

    case normalize_steering_attach_mode(map_get(payload, :attach_mode), requested_work_item_id, conversation) do
      :existing_work_item ->
        steer_existing_work_item(
          conversation,
          payload,
          requested_work_item_id || conversation.work_item_id,
          shared_context,
          actor,
          now
        )

      :synthesized_work_item ->
        synthesize_conversation_work_item(conversation, payload, shared_context, actor, now)

      :pre_work ->
        with {:ok, updated_conversation} <-
               update_conversation_for_steering(
                 conversation,
                 payload,
                 shared_context,
                 conversation.work_item_id && %{id: conversation.work_item_id},
                 nil,
                 conversation.attachment_mode,
                 conversation.scope,
                 actor,
                 now
               ) do
          {:ok, %{conversation: updated_conversation, work_item: nil, work_action: nil}}
        end
    end
  end

  def steer_work(_conversation, _payload, _opts), do: {:error, :invalid_conversation_steering}

  defp build_start_context(attrs) do
    actor = normalize_actor(Map.get(attrs, :actor) || Map.get(attrs, "actor"))
    source = required_string(attrs, :source)
    objective = optional_string(attrs, :objective)
    title = optional_string(attrs, :title) || objective
    source_metadata = normalize_map(Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata"))

    conversation_metadata =
      normalize_map(Map.get(attrs, :conversation_metadata) || Map.get(attrs, "conversation_metadata"))

    work_item_id = optional_string(attrs, :work_item_id)
    managed_repo_id = optional_string(attrs, :managed_repo_id)
    attach_mode = normalize_attach_mode(Map.get(attrs, :attach_mode) || Map.get(attrs, "attach_mode"), work_item_id)
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    with {:ok, source} <- validate_required_string(source, :source),
         {:ok, resolved} <- resolve_work_attachment(attach_mode, managed_repo_id, work_item_id, attrs, actor) do
      {:ok,
       %{
         actor: actor,
         source: source,
         title: title,
         objective: objective,
         source_metadata: source_metadata,
         conversation_metadata: conversation_metadata,
         managed_repo_id: resolved.managed_repo_id,
         work_item: resolved.work_item,
         work_action: resolved.work_action,
         attachment_mode: resolved.attachment_mode,
         scope: resolved.scope,
         started_at: now,
         last_activity_at: now
       }}
    end
  end

  defp resolve_work_attachment(:existing_work_item, managed_repo_id, work_item_id, _attrs, actor) do
    with {:ok, work_item_id} <- validate_required_string(work_item_id, :work_item_id),
         {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor),
         :ok <- validate_managed_repo_scope(managed_repo_id, work_item.managed_repo_id) do
      {:ok,
       %{
         managed_repo_id: work_item.managed_repo_id,
         work_item: work_item,
         work_action: nil,
         attachment_mode: :existing_work_item,
         scope: :work_item_scoped
       }}
    end
  end

  defp resolve_work_attachment(:synthesized_work_item, managed_repo_id, _work_item_id, attrs, actor) do
    with {:ok, managed_repo_id} <- validate_required_string(managed_repo_id, :managed_repo_id),
         {:ok, %{work_item: %WorkItem{} = work_item, work_action: work_action}} <-
           Ingress.record_operator_intake(%{
             managed_repo_id: managed_repo_id,
             channel: optional_string(attrs, :source) || "conversation",
             intent: optional_string(attrs, :intent) || "conversation_work_kickoff",
             actor: actor,
             payload:
               %{}
               |> maybe_put("objective", optional_string(attrs, :objective))
               |> maybe_put("title", optional_string(attrs, :title))
               |> maybe_put(
                 "context_item",
                 normalize_map(Map.get(attrs, :context_item) || Map.get(attrs, "context_item"))
               ),
             source_metadata:
               normalize_map(Map.get(attrs, :source_metadata) || Map.get(attrs, "source_metadata"))
               |> Map.put("conversation_entry", true)
           }) do
      {:ok,
       %{
         managed_repo_id: work_item.managed_repo_id,
         work_item: work_item,
         work_action: work_action,
         attachment_mode: :synthesized_work_item,
         scope: :work_item_scoped
       }}
    end
  end

  defp resolve_work_attachment(:pre_work, managed_repo_id, _work_item_id, _attrs, _actor) do
    with {:ok, managed_repo_id} <- validate_required_string(managed_repo_id, :managed_repo_id) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         work_item: nil,
         work_action: nil,
         attachment_mode: :pre_work,
         scope: :repo_scoped
       }}
    end
  end

  defp steer_existing_work_item(conversation, payload, work_item_id, shared_context, actor, now) do
    with {:ok, work_item_id} <- validate_required_string(work_item_id, :work_item_id),
         {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id, actor),
         :ok <- validate_managed_repo_scope(conversation.managed_repo_id, work_item.managed_repo_id),
         :ok <- validate_work_item_open(work_item),
         {:ok, %{work_item: %WorkItem{} = steered_work_item, work_action: work_action}} <-
           record_conversation_intake(
             conversation,
             payload,
             shared_context,
             actor,
             work_item.id,
             "conversation_steer_work"
           ),
         next_attachment_mode <- steering_attachment_mode(conversation, work_item.id),
         {:ok, updated_conversation} <-
           update_conversation_for_steering(
             conversation,
             payload,
             shared_context,
             steered_work_item,
             work_action,
             next_attachment_mode,
             :work_item_scoped,
             actor,
             now
           ) do
      {:ok,
       %{
         conversation: updated_conversation,
         work_item: steered_work_item,
         work_action: work_action
       }}
    end
  end

  defp synthesize_conversation_work_item(conversation, payload, shared_context, actor, now) do
    with {:ok, %{work_item: %WorkItem{} = work_item, work_action: work_action}} <-
           record_conversation_intake(
             conversation,
             payload,
             shared_context,
             actor,
             nil,
             "conversation_work_kickoff"
           ),
         {:ok, updated_conversation} <-
           update_conversation_for_steering(
             conversation,
             payload,
             shared_context,
             work_item,
             work_action,
             :synthesized_work_item,
             :work_item_scoped,
             actor,
             now
           ) do
      {:ok,
       %{
         conversation: updated_conversation,
         work_item: work_item,
         work_action: work_action
       }}
    end
  end

  defp record_conversation_intake(conversation, payload, shared_context, actor, work_item_id, intent) do
    Ingress.record_operator_intake(%{
      managed_repo_id: conversation.managed_repo_id,
      channel: "conversation",
      intent: intent,
      actor: actor,
      payload: steering_payload(conversation, payload, shared_context, work_item_id),
      source_metadata: steering_source_metadata(conversation, payload, shared_context, work_item_id, intent)
    })
  end

  defp steering_payload(conversation, payload, shared_context, work_item_id) do
    %{}
    |> maybe_put("work_item_id", work_item_id)
    |> maybe_put("instruction", optional_string(payload, :instruction))
    |> maybe_put("reason", optional_string(payload, :reason))
    |> maybe_put("workflow_name", optional_string(payload, :workflow_name))
    |> maybe_put("shared_context", shared_context)
    |> Map.put("context_item", %{
      "type" => "conversation",
      "conversation_id" => conversation.id,
      "conversation_scope" => Atom.to_string(conversation.scope),
      "attachment_mode" => Atom.to_string(conversation.attachment_mode),
      "shared_context_summary" => shared_context_summary(shared_context)
    })
  end

  defp steering_source_metadata(conversation, payload, shared_context, work_item_id, intent) do
    %{}
    |> Map.put("conversation_entry", true)
    |> Map.put("conversation_id", conversation.id)
    |> Map.put("conversation_control_command", "turn.steer")
    |> Map.put("conversation_scope", Atom.to_string(conversation.scope))
    |> Map.put("conversation_attachment_mode", Atom.to_string(conversation.attachment_mode))
    |> Map.put("steering_intent", intent)
    |> maybe_put("target_work_item_id", work_item_id)
    |> maybe_put("instruction", optional_string(payload, :instruction))
    |> maybe_put("shared_context_summary", shared_context_summary(shared_context))
  end

  defp update_conversation_for_steering(
         conversation,
         payload,
         shared_context,
         work_item,
         work_action,
         attachment_mode,
         scope,
         actor,
         now
       ) do
    Conversation.update(
      conversation,
      %{
        work_item_id: optional_id(work_item),
        attachment_mode: attachment_mode,
        scope: scope,
        conversation_metadata:
          steering_conversation_metadata(
            conversation,
            payload,
            shared_context,
            work_item,
            work_action,
            attachment_mode,
            scope,
            now
          ),
        last_activity_at: now
      },
      actor: actor
    )
  end

  defp steering_conversation_metadata(
         conversation,
         payload,
         shared_context,
         work_item,
         work_action,
         attachment_mode,
         scope,
         now
       ) do
    current_metadata = normalize_map(conversation.conversation_metadata)
    instruction = optional_string(payload, :instruction) || optional_string(payload, :reason)

    steering_entry =
      %{
        "at" => DateTime.to_iso8601(now),
        "command" => "turn.steer",
        "work_item_id" => optional_id(work_item) || conversation.work_item_id,
        "attachment_mode" => Atom.to_string(attachment_mode),
        "scope" => Atom.to_string(scope)
      }
      |> maybe_put("work_action", work_action && Atom.to_string(work_action))
      |> maybe_put("instruction", instruction)

    current_metadata
    |> Map.put("canonical_work_surface", "work_item")
    |> Map.put("shared_context_contract", "bounded")
    |> Map.put("active_work_item_id", optional_id(work_item) || conversation.work_item_id)
    |> Map.put("last_steer_command", "turn.steer")
    |> Map.put("last_steered_at", DateTime.to_iso8601(now))
    |> maybe_put("last_steer_instruction", instruction)
    |> maybe_put("last_work_action", work_action && Atom.to_string(work_action))
    |> Map.put("shared_context_summary", shared_context_summary(shared_context))
    |> Map.put("steering_history", steering_history(current_metadata, steering_entry))
  end

  defp steering_history(current_metadata, steering_entry) do
    current_metadata
    |> Map.get("steering_history", [])
    |> List.wrap()
    |> Enum.filter(&is_map/1)
    |> Kernel.++([steering_entry])
    |> Enum.take(-10)
  end

  defp shared_context_summary(shared_context) do
    %{
      "referenced_file_count" =>
        shared_context
        |> Map.get("referenced_files", [])
        |> List.wrap()
        |> length(),
      "accepted_tool_result_count" =>
        shared_context
        |> Map.get("accepted_tool_results", [])
        |> List.wrap()
        |> length(),
      "pending_clarification" => is_map(Map.get(shared_context, "pending_clarification"))
    }
  end

  defp steering_attachment_mode(conversation, work_item_id) do
    if conversation.work_item_id == work_item_id and conversation.attachment_mode in [:existing_work_item, :synthesized_work_item] do
      conversation.attachment_mode
    else
      :existing_work_item
    end
  end

  defp normalize_steering_attach_mode(:synthesized_work_item, _requested_work_item_id, _conversation),
    do: :synthesized_work_item

  defp normalize_steering_attach_mode("synthesized_work_item", _requested_work_item_id, _conversation),
    do: :synthesized_work_item

  defp normalize_steering_attach_mode(_attach_mode, requested_work_item_id, _conversation)
       when is_binary(requested_work_item_id),
       do: :existing_work_item

  defp normalize_steering_attach_mode(_attach_mode, _requested_work_item_id, %Conversation{work_item_id: work_item_id})
       when is_binary(work_item_id),
       do: :existing_work_item

  defp normalize_steering_attach_mode(_attach_mode, _requested_work_item_id, _conversation), do: :pre_work

  defp validate_work_item_open(%WorkItem{status: :open}), do: :ok
  defp validate_work_item_open(%WorkItem{}), do: {:error, :work_item_not_open}

  defp conversation_attrs(context) do
    %{
      managed_repo_id: context.managed_repo_id,
      work_item_id: optional_id(context.work_item),
      status: :active,
      scope: context.scope,
      attachment_mode: context.attachment_mode,
      source: context.source,
      title: context.title,
      objective: context.objective,
      initiating_actor: context.actor,
      source_metadata: context.source_metadata,
      conversation_metadata: context.conversation_metadata,
      started_at: context.started_at,
      last_activity_at: context.last_activity_at
    }
  end

  defp fetch_conversation(conversation_id, actor) do
    case Conversation.read(query: [filter: [id: conversation_id], limit: 1], actor: actor) do
      {:ok, [%Conversation{} = conversation | _rest]} -> {:ok, conversation}
      {:ok, []} -> {:error, :conversation_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_work_item(work_item_id, actor) do
    case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: actor) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      {:ok, []} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_managed_repo_scope(nil, _resolved_managed_repo_id), do: :ok

  defp validate_managed_repo_scope(managed_repo_id, resolved_managed_repo_id)
       when managed_repo_id == resolved_managed_repo_id,
       do: :ok

  defp validate_managed_repo_scope(_managed_repo_id, _resolved_managed_repo_id),
    do: {:error, :managed_repo_scope_mismatch}

  defp normalize_attach_mode(nil, work_item_id) when is_binary(work_item_id), do: :existing_work_item
  defp normalize_attach_mode(nil, _work_item_id), do: :pre_work
  defp normalize_attach_mode(:existing_work_item, _work_item_id), do: :existing_work_item
  defp normalize_attach_mode("existing_work_item", _work_item_id), do: :existing_work_item
  defp normalize_attach_mode(:synthesized_work_item, _work_item_id), do: :synthesized_work_item
  defp normalize_attach_mode("synthesized_work_item", _work_item_id), do: :synthesized_work_item
  defp normalize_attach_mode(:pre_work, _work_item_id), do: :pre_work
  defp normalize_attach_mode("pre_work", _work_item_id), do: :pre_work
  defp normalize_attach_mode(_other, work_item_id), do: normalize_attach_mode(nil, work_item_id)

  defp normalize_actor(nil), do: Actor.operator_actor()

  defp normalize_actor(%{} = actor) do
    actor
    |> stringify_keys()
    |> Actor.operator_actor()
  end

  defp validate_required_string(value, _field_name) when is_binary(value) and value != "", do: {:ok, value}
  defp validate_required_string(_value, field_name), do: {:error, {:missing_required_field, field_name}}

  defp required_string(attrs, key) do
    attrs
    |> map_get(key)
    |> optional_string()
  end

  defp optional_string(attrs, key) when is_map(attrs) do
    attrs
    |> map_get(key)
    |> optional_string()
  end

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> optional_string()
  defp optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: stringify_keys(value)
  defp normalize_map(_value), do: %{}

  defp stringify_keys(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, stringify_nested_value(nested_value))
    end)
  end

  defp stringify_keys(_value), do: %{}

  defp stringify_nested_value(value) when is_map(value), do: stringify_keys(value)
  defp stringify_nested_value(value) when is_list(value), do: Enum.map(value, &stringify_nested_value/1)
  defp stringify_nested_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp optional_id(nil), do: nil
  defp optional_id(%{id: id}), do: id

  defp map_get(map, atom_key) when is_map(map) do
    string_key = Atom.to_string(atom_key)

    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> nil
    end
  end
end
