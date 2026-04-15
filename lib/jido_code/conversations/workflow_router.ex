defmodule JidoCode.Conversations.WorkflowRouter do
  # covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
  @moduledoc """
  Canonical deterministic workflow routing for productive conversation turns.

  The router keeps workflow selection product-owned and inspectable. It prefers
  explicit workflow intent and stored routing continuity before falling back to
  deterministic text heuristics.
  """

  @workflows [:plan, :execute, :review, :explain]

  @plan_cues ["plan", "approach", "break down", "step-by-step", "roadmap", "outline"]
  @review_cues ["review", "audit", "critique", "risk", "regression", "security"]

  @execute_cues [
    "implement",
    "change",
    "fix",
    "update",
    "edit",
    "refactor",
    "write",
    "add",
    "remove",
    "patch"
  ]

  @surface_intent_keys ["surface_workflow", "surface_intent", "workflow_hint", "workflow"]

  @type workflow :: :plan | :execute | :review | :explain

  @type decision :: %{
          workflow: workflow() | nil,
          source: :explicit_payload | :routing_continuity | :surface_intent | :heuristic | :fallback,
          confidence: :high | :medium | :low,
          ambiguous?: boolean(),
          reasons: [String.t()]
        }

  @spec resolve(map()) :: decision()
  def resolve(input) when is_map(input) do
    payload = normalize_map(Map.get(input, :payload) || Map.get(input, "payload"))

    source_metadata =
      normalize_map(Map.get(input, :source_metadata) || Map.get(input, "source_metadata"))

    case explicit_workflow(payload) do
      workflow when workflow in @workflows ->
        decision(workflow, :explicit_payload, :high, [
          "Using explicit workflow from the command payload."
        ])

      _no_explicit_workflow ->
        case stored_routing_workflow(payload) do
          workflow when workflow in @workflows ->
            decision(workflow, :routing_continuity, :high, [
              "Reusing stored workflow routing continuity for the active turn."
            ])

          _no_continuity ->
            case surface_intent_workflow(payload, source_metadata) do
              workflow when workflow in @workflows ->
                decision(workflow, :surface_intent, :medium, [
                  "Using bounded surface workflow intent supplied by the product entrypoint."
                ])

              _no_surface_intent ->
                heuristic_decision(input, payload)
            end
        end
    end
  end

  @spec attach_payload(map(), decision()) :: map()
  def attach_payload(payload, %{source: _source} = decision) when is_map(payload) do
    payload = normalize_map(payload)
    runtime_payload = normalize_map(Map.get(payload, "conversation_runtime"))

    Map.put(payload, "conversation_runtime", Map.put(runtime_payload, "routing", metadata(decision)))
  end

  @spec metadata(decision()) :: map()
  def metadata(%{source: source} = decision) do
    %{}
    |> maybe_put("workflow", decision.workflow && Atom.to_string(decision.workflow))
    |> Map.put("source", Atom.to_string(source))
    |> Map.put("confidence", Atom.to_string(decision.confidence))
    |> Map.put("ambiguous", decision.ambiguous?)
    |> Map.put("reasons", List.wrap(decision.reasons))
  end

  @spec normalize_workflow(term()) :: workflow() | nil
  def normalize_workflow(value) when value in @workflows, do: value

  def normalize_workflow(value) when is_binary(value) do
    case String.trim(value) do
      "plan" -> :plan
      "execute" -> :execute
      "review" -> :review
      "explain" -> :explain
      _other -> nil
    end
  end

  def normalize_workflow(_value), do: nil

  defp heuristic_decision(input, payload) do
    text =
      [
        instruction_text(payload),
        optional_string(Map.get(input, :objective) || Map.get(input, "objective")),
        input
        |> Map.get(:conversation_metadata, Map.get(input, "conversation_metadata"))
        |> normalize_map()
        |> Map.get("last_work_action")
      ]
      |> Enum.map(&optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.join("\n")
      |> String.downcase()

    cond do
      contains_any?(text, @plan_cues) ->
        decision(:plan, :heuristic, :medium, ["Matched planning cues in the request text."])

      contains_any?(text, @review_cues) ->
        decision(:review, :heuristic, :medium, ["Matched review cues in the request text."])

      contains_any?(text, @execute_cues) ->
        decision(:execute, :heuristic, :medium, ["Matched implementation cues in the request text."])

      contains_any?(text, ["explain", "inspect", "clarify", "understand", "how", "why", "what"]) ->
        decision(:explain, :heuristic, :medium, ["Matched explanation cues in the request text."])

      true ->
        decision(:explain, :fallback, :low, [
          "No explicit or continuity workflow signal was available, so the request falls back to explanation."
        ])
    end
  end

  defp explicit_workflow(payload) do
    payload
    |> Enum.find_value(fn {key, value} ->
      if key in ["workflow", "workflow_name"], do: normalize_workflow(value), else: nil
    end)
  end

  defp stored_routing_workflow(payload) do
    payload
    |> Map.get("conversation_runtime")
    |> normalize_map()
    |> Map.get("routing")
    |> normalize_map()
    |> Map.get("workflow")
    |> normalize_workflow()
  end

  defp surface_intent_workflow(payload, source_metadata) do
    Enum.find_value(@surface_intent_keys, fn key ->
      normalize_workflow(Map.get(payload, key) || Map.get(source_metadata, key))
    end)
  end

  defp instruction_text(payload) do
    clarification_resume = normalize_map(Map.get(payload, "clarification_resume"))

    optional_string(Map.get(clarification_resume, "response")) ||
      optional_string(Map.get(payload, "instruction")) ||
      optional_string(Map.get(payload, "intent")) ||
      optional_string(Map.get(payload, "reason")) ||
      optional_string(Map.get(payload, "summary")) ||
      "Continue the repository conversation."
  end

  defp decision(workflow, source, confidence, reasons) do
    %{
      workflow: workflow,
      source: source,
      confidence: confidence,
      ambiguous?: false,
      reasons: reasons
    }
  end

  defp contains_any?(text, phrases) when is_binary(text) and is_list(phrases) do
    Enum.any?(phrases, &String.contains?(text, &1))
  end

  defp contains_any?(_text, _phrases), do: false

  defp optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp optional_string(nil), do: nil

  defp optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> optional_string()

  defp optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
