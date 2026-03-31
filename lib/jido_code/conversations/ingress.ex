defmodule JidoCode.Conversations.Ingress do
  # covers: architecture.demand_ingress.conversation_turns_become_durable_intake
  # covers: architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
  # covers: architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering
  # covers: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  @moduledoc """
  Normalizes coding conversation turns into the durable control-plane ingress loop.

  Conversation turns are treated as operator-originated demand that either creates
  new work or explicitly steers an existing work item while preserving session,
  request, correlation, and managed-repository context.
  """

  alias JidoCode.Control.RepoBridge
  alias JidoCode.Operations.Ingress, as: OperationsIngress

  @new_work_intent "coding_turn_request"
  @steering_intent "work_item_steering"
  @conversation_channel "conversation"
  @conversation_entrypoint "conversation_driver"
  @coding_turn_kind "coding"

  @type turn_mode :: :new_demand | :steer_existing_work

  @type record_turn_result ::
          {:ok,
           %{
             turn_mode: turn_mode(),
             intake: JidoCode.Operations.Intake.t(),
             event: JidoCode.Operations.Event.t(),
             assessment: JidoCode.Operations.Assessment.t(),
             work_item: JidoCode.Operations.WorkItem.t() | nil,
             work_action: :created | :reprioritized | :suppressed_duplicate | :steered | :unscoped
           }}
          | {:error, term()}

  @spec record_turn(map()) :: record_turn_result()
  def record_turn(%{} = attrs) do
    with {:ok, actor} <- actor_attrs(attrs),
         {:ok, conversation_id} <- fetch_required_string(attrs, :conversation_id),
         {:ok, message_content} <- fetch_required_string(attrs, :content),
         turn_mode <- turn_mode(attrs),
         managed_repo_id <- resolve_managed_repo_id(attrs),
         operator_intake_attrs <-
           %{
             managed_repo_id: managed_repo_id,
             project_id: get_string(attrs, :project_id),
             channel: @conversation_channel,
             intent: intent_for(turn_mode),
             actor: actor,
             payload: turn_payload(attrs, conversation_id, message_content, turn_mode),
             source_metadata: turn_source_metadata(attrs, conversation_id, turn_mode)
           }
           |> compact_nil_values(),
         {:ok, result} <- OperationsIngress.record_operator_intake(operator_intake_attrs) do
      {:ok, Map.put(result, :turn_mode, turn_mode)}
    end
  end

  def record_turn(_attrs), do: {:error, :invalid_conversation_turn}

  defp actor_attrs(attrs) do
    actor_id = get_string(attrs, :actor_id)
    actor_email = get_string(attrs, :actor_email)

    if is_binary(actor_id) do
      {:ok, %{id: actor_id, email: actor_email}}
    else
      {:error, :missing_actor_id}
    end
  end

  defp turn_mode(attrs) do
    if get_string(attrs, :work_item_id) do
      :steer_existing_work
    else
      :new_demand
    end
  end

  defp intent_for(:steer_existing_work), do: @steering_intent
  defp intent_for(_turn_mode), do: @new_work_intent

  defp resolve_managed_repo_id(attrs) when is_map(attrs) do
    case get_string(attrs, :managed_repo_id) do
      managed_repo_id when is_binary(managed_repo_id) ->
        managed_repo_id

      nil ->
        case get_string(attrs, :project_id) do
          nil ->
            nil

          project_id ->
            case RepoBridge.managed_repo_for_project(project_id) do
              {:ok, managed_repo} -> get_string(managed_repo, :id)
              _other -> nil
            end
        end
    end
  end

  defp resolve_managed_repo_id(_attrs), do: nil

  defp turn_payload(attrs, conversation_id, message_content, turn_mode) do
    %{
      "turn_kind" => @coding_turn_kind,
      "turn_mode" => turn_mode |> Atom.to_string(),
      "conversation_id" => conversation_id,
      "session_id" => conversation_id,
      "message_content" => message_content,
      "managed_repo_id" => resolve_managed_repo_id(attrs),
      "operation" => get_string(attrs, :operation),
      "work_item_id" => get_string(attrs, :work_item_id),
      "policy_action" => get_string(attrs, :policy_action),
      "policy_reason_code" => get_string(attrs, :policy_reason_code)
    }
    |> compact_nil_values()
  end

  defp turn_source_metadata(attrs, conversation_id, turn_mode) do
    %{
      "entrypoint" => @conversation_entrypoint,
      "turn_kind" => @coding_turn_kind,
      "turn_mode" => turn_mode |> Atom.to_string(),
      "conversation_id" => conversation_id,
      "session_id" => conversation_id,
      "managed_repo_id" => resolve_managed_repo_id(attrs),
      "project_id" => get_string(attrs, :project_id),
      "request_id" => get_string(attrs, :request_id),
      "correlation_id" => get_string(attrs, :correlation_id),
      "workspace_id" => get_string(attrs, :workspace_id),
      "work_item_id" => get_string(attrs, :work_item_id),
      "policy_action" => get_string(attrs, :policy_action),
      "policy_reason_code" => get_string(attrs, :policy_reason_code),
      "review_policy" => get_map(attrs, :review_policy)
    }
    |> compact_nil_values()
  end

  defp compact_nil_values(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_map(value) ->
        Map.put(acc, key, compact_nil_values(value))

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end

  defp fetch_required_string(attrs, key) do
    case get_string(attrs, key) do
      nil -> {:error, {:missing_required_field, key}}
      value -> {:ok, value}
    end
  end

  defp get_string(attrs, key) when is_map(attrs) do
    attrs
    |> Map.get(key)
    |> case do
      nil -> Map.get(attrs, Atom.to_string(key))
      value -> value
    end
    |> normalize_optional_string()
  end

  defp get_string(_attrs, _key), do: nil

  defp get_map(attrs, key) when is_map(attrs) do
    value =
      Map.get(attrs, key) ||
        Map.get(attrs, Atom.to_string(key))

    if is_map(value), do: value, else: nil
  end

  defp get_map(_attrs, _key), do: nil

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
end
