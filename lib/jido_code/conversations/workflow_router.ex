defmodule JidoCode.Conversations.WorkflowRouter do
  # covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned
  # covers: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence
  # covers: architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification
  @moduledoc """
  Canonical deterministic workflow routing for productive conversation turns.

  The router keeps workflow selection product-owned and inspectable. It prefers
  explicit workflow intent and stored routing continuity before falling back to
  deterministic text heuristics.
  """

  @workflows [:plan, :execute, :refactor, :review, :explain]

  @surface_intent_keys ["surface_workflow", "surface_intent", "workflow_hint", "workflow"]

  @heuristic_rules %{
    plan: %{
      phrases: [
        {"implementation plan", 14},
        {"plan the fix", 15},
        {"step by step", 12},
        {"break down", 12},
        {"outline the work", 12},
        {"roadmap", 10}
      ],
      tokens: [{"plan", 8}, {"approach", 6}, {"outline", 6}, {"steps", 5}, {"roadmap", 6}]
    },
    execute: %{
      phrases: [
        {"fix failing tests", 18},
        {"implement this", 16},
        {"make the change", 14},
        {"update the code", 14},
        {"write the code", 16},
        {"apply the patch", 16}
      ],
      tokens: [
        {"implement", 8},
        {"change", 6},
        {"fix", 8},
        {"update", 5},
        {"edit", 5},
        {"write", 5},
        {"add", 4},
        {"remove", 4},
        {"patch", 6}
      ]
    },
    refactor: %{
      phrases: [
        {"refactor this", 18},
        {"refactor the", 16},
        {"behavior preserving", 20},
        {"preserve behavior", 20},
        {"without changing behavior", 20},
        {"extract function", 16},
        {"extract module", 16},
        {"rename without changing", 18},
        {"simplify without changing", 18}
      ],
      tokens: [
        {"refactor", 10},
        {"refactoring", 10},
        {"extract", 8},
        {"rename", 7},
        {"simplify", 6},
        {"deduplicate", 8},
        {"reorganize", 6},
        {"cleanup", 6}
      ]
    },
    review: %{
      phrases: [
        {"review this", 14},
        {"code review", 16},
        {"look for regressions", 16},
        {"audit this", 16},
        {"security review", 18},
        {"review the diff", 18}
      ],
      tokens: [
        {"review", 8},
        {"audit", 7},
        {"risk", 6},
        {"regression", 7},
        {"security", 7},
        {"diff", 6},
        {"critique", 7}
      ]
    },
    explain: %{
      phrases: [
        {"explain this", 14},
        {"why does", 16},
        {"help me understand", 14},
        {"what does this do", 16},
        {"how does this work", 16},
        {"inspect the", 12},
        {"clarify which", 12}
      ],
      tokens: [
        {"explain", 8},
        {"why", 6},
        {"how", 4},
        {"understand", 5},
        {"inspect", 6},
        {"investigate", 6},
        {"clarify", 8},
        {"what", 3}
      ]
    }
  }

  @type workflow :: :plan | :execute | :refactor | :review | :explain

  @type decision :: %{
          workflow: workflow() | nil,
          candidate_workflow: workflow() | nil,
          source: :explicit_payload | :routing_continuity | :surface_intent | :heuristic | :fallback,
          confidence: :high | :medium | :low,
          ambiguous?: boolean(),
          reasons: [String.t()],
          scores: %{workflow() => non_neg_integer()}
        }

  @spec workflows() :: [workflow()]
  def workflows, do: @workflows

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
                scored_decision(input, payload)
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
    |> maybe_put(
      "candidate_workflow",
      decision.candidate_workflow && Atom.to_string(decision.candidate_workflow)
    )
    |> Map.put("source", Atom.to_string(source))
    |> Map.put("confidence", Atom.to_string(decision.confidence))
    |> Map.put("ambiguous", decision.ambiguous?)
    |> Map.put("reasons", List.wrap(decision.reasons))
    |> Map.put(
      "scores",
      Enum.into(decision.scores, %{}, fn {workflow, score} -> {Atom.to_string(workflow), score} end)
    )
  end

  @spec normalize_workflow(term()) :: workflow() | nil
  def normalize_workflow(value) when value in @workflows, do: value

  def normalize_workflow(value) when is_binary(value) do
    case String.trim(value) do
      "plan" -> :plan
      "execute" -> :execute
      "implement" -> :execute
      "implementation" -> :execute
      "refactor" -> :refactor
      "refactoring" -> :refactor
      "refactor_work" -> :refactor
      "review" -> :review
      "explain" -> :explain
      _other -> nil
    end
  end

  def normalize_workflow(_value), do: nil

  defp scored_decision(input, payload) do
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

    {scores, reasons_by_workflow} =
      Enum.reduce(@workflows, {%{}, %{}}, fn workflow, {scores, reasons} ->
        %{score: score, reasons: workflow_reasons} = score_workflow(text, workflow)

        {
          Map.put(scores, workflow, score),
          Map.put(reasons, workflow, workflow_reasons)
        }
      end)

    ranked =
      scores
      |> Enum.sort_by(fn {_workflow, score} -> -score end)

    [{top_workflow, top_score} | rest] = ranked
    {_second_workflow, second_score} = List.first(rest) || {nil, 0}

    multi_intent? =
      String.contains?(text, " and ") or String.contains?(text, " or ")

    conflicting? = multi_intent? and top_score >= 8 and second_score >= 8
    weak? = top_score < 8
    close? = second_score > 0 and top_score - second_score < 4

    cond do
      conflicting? or weak? or close? ->
        ambiguity_reasons =
          []
          |> maybe_add_reason(weak?, "The request does not provide a strong enough workflow signal.")
          |> maybe_add_reason(close?, "The top workflow scores are too close to choose confidently.")
          |> maybe_add_reason(conflicting?, "The request mixes multiple workflow intents in one turn.")
          |> Kernel.++(Map.get(reasons_by_workflow, top_workflow, []))

        ambiguous_decision(top_workflow, ambiguity_reasons, scores)

      true ->
        decision(
          top_workflow,
          :heuristic,
          heuristic_confidence(top_score),
          Map.get(reasons_by_workflow, top_workflow, []),
          scores
        )
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
    decision(workflow, source, confidence, reasons, default_scores(workflow))
  end

  defp decision(workflow, source, confidence, reasons, scores) do
    %{
      workflow: workflow,
      candidate_workflow: workflow,
      source: source,
      confidence: confidence,
      ambiguous?: false,
      reasons: reasons,
      scores: scores
    }
  end

  defp ambiguous_decision(candidate_workflow, reasons, scores) do
    %{
      workflow: nil,
      candidate_workflow: candidate_workflow,
      source: :heuristic,
      confidence: :low,
      ambiguous?: true,
      reasons: reasons,
      scores: scores
    }
  end

  defp score_workflow(text, workflow) do
    rules = Map.fetch!(@heuristic_rules, workflow)

    phrase_matches =
      Enum.filter(rules.phrases, fn {phrase, _weight} -> String.contains?(text, phrase) end)

    token_matches =
      Enum.filter(rules.tokens, fn {token, _weight} -> contains_token?(text, token) end)

    score =
      phrase_matches
      |> Enum.concat(token_matches)
      |> Enum.reduce(0, fn {_cue, weight}, acc -> acc + weight end)

    reasons =
      phrase_matches
      |> Enum.map(fn {phrase, _weight} -> "Matched phrase cue: #{phrase}." end)
      |> Kernel.++(Enum.map(token_matches, fn {token, _weight} -> "Matched token cue: #{token}." end))

    %{score: score, reasons: reasons}
  end

  defp heuristic_confidence(score) when score >= 16, do: :high
  defp heuristic_confidence(score) when score >= 8, do: :medium
  defp heuristic_confidence(_score), do: :low

  defp contains_token?(text, token) when is_binary(text) and is_binary(token) do
    Regex.match?(~r/(^|[^a-z0-9_])#{Regex.escape(token)}([^a-z0-9_]|$)/, text)
  end

  defp contains_token?(_text, _token), do: false

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

  defp default_scores(workflow) when workflow in @workflows,
    do: Enum.into(@workflows, %{}, fn candidate -> {candidate, if(candidate == workflow, do: 100, else: 0)} end)

  defp default_scores(_workflow), do: Enum.into(@workflows, %{}, fn workflow -> {workflow, 0} end)

  defp maybe_add_reason(reasons, true, reason), do: reasons ++ [reason]
  defp maybe_add_reason(reasons, false, _reason), do: reasons

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
