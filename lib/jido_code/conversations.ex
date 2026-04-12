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
