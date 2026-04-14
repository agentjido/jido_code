defmodule JidoCode.Conversations.WorkResolution do
  # covers: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
  # covers: architecture.work_synthesis.productive_conversations_route_through_work_resolution
  @moduledoc """
  Product-owned boundary for resolving repository conversation turns onto
  canonical governed work before durable specialist execution continues.
  """

  alias JidoCode.Conversations
  alias JidoCode.Conversations.{Conversation, Turn}

  @governed_workflows [:plan, :execute, :review, :explain]

  @type resolution_summary :: map()

  @spec ensure_turn_attachment(Conversation.t(), Turn.t(), map(), keyword()) ::
          {:ok,
           %{
             conversation: Conversation.t(),
             resolution: resolution_summary()
           }}
          | {:error, term()}
  def ensure_turn_attachment(%Conversation{} = conversation, %Turn{} = turn, shared_context, opts \\ [])
      when is_map(shared_context) and is_list(opts) do
    workflow = workflow_for_turn(turn, conversation)

    cond do
      is_binary(conversation.work_item_id) ->
        {:ok,
         %{
           conversation: conversation,
           resolution: summary(conversation, workflow: workflow)
         }}

      workflow in @governed_workflows ->
        synthesize_turn_attachment(conversation, turn, workflow, shared_context, opts)

      true ->
        {:ok,
         %{
           conversation: conversation,
           resolution: summary(conversation, workflow: workflow)
         }}
    end
  end

  @spec summary(Conversation.t(), keyword()) :: resolution_summary()
  def summary(%Conversation{} = conversation, opts \\ []) when is_list(opts) do
    conversation_metadata = normalize_map(conversation.conversation_metadata)
    last_resolution = conversation_metadata |> Map.get("last_work_resolution") |> normalize_map()
    workflow = normalize_workflow(Keyword.get(opts, :workflow) || Map.get(last_resolution, "workflow"))

    %{
      "action" =>
        normalize_optional_string(Map.get(last_resolution, "action")) || default_action(conversation),
      "detail" => resolution_detail(conversation, last_resolution, workflow),
      "scope" => Atom.to_string(conversation.scope),
      "attachment_mode" => Atom.to_string(conversation.attachment_mode),
      "workflow" => workflow && Atom.to_string(workflow),
      "work_item_id" => conversation.work_item_id,
      "work_action" =>
        normalize_optional_string(Map.get(last_resolution, "work_action")) ||
          normalize_optional_string(Map.get(conversation_metadata, "last_work_action")),
      "turn_id" => normalize_optional_string(Map.get(last_resolution, "turn_id")),
      "command_id" => normalize_optional_string(Map.get(last_resolution, "command_id")),
      "command" => normalize_optional_string(Map.get(last_resolution, "command")),
      "at" => normalize_optional_string(Map.get(last_resolution, "resolved_at"))
    }
    |> reject_nil_values()
  end

  defp synthesize_turn_attachment(conversation, turn, workflow, shared_context, opts) do
    steering_payload =
      %{
        "attach_mode" => "synthesized_work_item",
        "instruction" => instruction_for_turn(turn),
        "workflow_name" => Atom.to_string(workflow),
        "turn_id" => turn.id,
        "command_id" => turn.command_id,
        "resolution_command_type" => turn.command_type,
        "resolution_reason" => workflow_resolution_reason(workflow)
      }

    case Conversations.steer_work(
           conversation,
           steering_payload,
           actor: Keyword.get(opts, :actor, turn.actor),
           shared_context: shared_context
         ) do
      {:ok, %{conversation: %Conversation{} = updated_conversation}} ->
        {:ok,
         %{
           conversation: updated_conversation,
           resolution: summary(updated_conversation, workflow: workflow)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolution_detail(conversation, last_resolution, workflow) do
    normalize_optional_string(Map.get(last_resolution, "detail")) ||
      default_detail(conversation, workflow)
  end

  defp default_action(%Conversation{work_item_id: work_item_id, attachment_mode: :synthesized_work_item})
       when is_binary(work_item_id),
       do: "created"

  defp default_action(%Conversation{work_item_id: work_item_id}) when is_binary(work_item_id),
    do: "attached"

  defp default_action(_conversation), do: "repo_scoped"

  defp default_detail(%Conversation{work_item_id: work_item_id, attachment_mode: attachment_mode}, workflow)
       when is_binary(work_item_id) do
    case attachment_mode do
      :synthesized_work_item ->
        "Governed #{workflow_label(workflow)} work is attached to WorkItem #{work_item_id}."

      :existing_work_item ->
        "This conversation is attached to existing governed work item #{work_item_id}."

      _other ->
        "This conversation is attached to governed work item #{work_item_id}."
    end
  end

  defp default_detail(_conversation, workflow) do
    "No governed work item is attached yet; the conversation remains repo-scoped until #{workflow_label(workflow)} work is promoted."
  end

  defp workflow_label(nil), do: "governed"
  defp workflow_label(:plan), do: "planning"
  defp workflow_label(:execute), do: "implementation"
  defp workflow_label(:review), do: "review"
  defp workflow_label(:explain), do: "follow-up"
  defp workflow_label(_workflow), do: "governed"

  defp workflow_resolution_reason(:plan),
    do: "Planning work is durable governed work and must attach to a canonical WorkItem."

  defp workflow_resolution_reason(:execute),
    do: "Implementation work must continue through the canonical governed WorkItem loop."

  defp workflow_resolution_reason(:review),
    do: "Review work must remain attached to canonical governed WorkItem scope."

  defp workflow_resolution_reason(:explain),
    do: "Governed follow-up and explanation work should remain linked to canonical WorkItem scope."

  defp workflow_resolution_reason(_workflow),
    do: "Conversation work should remain attached to canonical governed WorkItem scope."

  defp workflow_for_turn(%Turn{} = turn, %Conversation{} = conversation) do
    text =
      [
        instruction_for_turn(turn),
        normalize_optional_string(conversation.objective),
        conversation
        |> Map.get(:conversation_metadata, %{})
        |> normalize_map()
        |> Map.get("last_work_action")
      ]
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.downcase()

    cond do
      contains_any?(text, ["plan", "approach", "break down", "step-by-step", "roadmap", "outline"]) ->
        :plan

      contains_any?(text, ["review", "audit", "critique", "risk", "regression", "security"]) ->
        :review

      contains_any?(text, ["implement", "change", "fix", "update", "edit", "refactor", "write", "add", "remove", "patch"]) ->
        :execute

      true ->
        :explain
    end
  end

  defp instruction_for_turn(%Turn{payload: payload}) when is_map(payload) do
    payload = normalize_map(payload)

    payload["instruction"] ||
      payload["intent"] ||
      payload["reason"] ||
      payload["summary"] ||
      "Continue the repository conversation."
  end

  defp contains_any?(text, phrases) when is_binary(text) and is_list(phrases) do
    Enum.any?(phrases, &String.contains?(text, &1))
  end

  defp normalize_workflow(value) when value in @governed_workflows, do: value

  defp normalize_workflow(value) when is_binary(value) do
    case value do
      "plan" -> :plan
      "execute" -> :execute
      "review" -> :review
      "explain" -> :explain
      _other -> nil
    end
  end

  defp normalize_workflow(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        case nested_value do
          nested when is_map(nested) -> normalize_map(nested)
          nested when is_list(nested) -> Enum.map(nested, &normalize_nested_value/1)
          other -> other
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp reject_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
