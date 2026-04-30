defmodule JidoCode.MemoryGraph.RetrievalPolicy do
  @moduledoc false

  @type workflow_kind :: :plan | :execute | :review | :explain
  @type freshness_mode :: :ready_only | :allow_stale
  @type provenance_scope :: :none | :workflow_history | :workflow_and_governed_history
  @type policy :: %{
          workflow: workflow_kind(),
          intent: atom(),
          memory_kinds: [atom()],
          provenance_kinds: [atom()],
          freshness: freshness_mode(),
          provenance_scope: provenance_scope(),
          allow_stale?: boolean(),
          follow_up_intent: atom(),
          limit: pos_integer()
        }

  @default_limits %{
    plan: 8,
    execute: 8,
    review: 10,
    explain: 6
  }

  @default_policies %{
    plan: %{
      intent: :planning_constraints,
      memory_kinds: [:decision, :invariant, :convention, :known_issue, :open_question],
      provenance_kinds: [:plan, :review, :patch],
      freshness: :ready_only,
      provenance_scope: :workflow_history,
      follow_up_intent: :work_item
    },
    execute: %{
      intent: :implementation_constraints,
      memory_kinds: [:decision, :invariant, :convention, :known_issue, :pattern],
      provenance_kinds: [:plan, :review, :patch],
      freshness: :ready_only,
      provenance_scope: :workflow_and_governed_history,
      follow_up_intent: :work_item
    },
    review: %{
      intent: :review_risks,
      memory_kinds: [:known_issue, :anti_pattern, :decision, :lesson_learned],
      provenance_kinds: [:review, :patch, :agent_run],
      freshness: :ready_only,
      provenance_scope: :workflow_and_governed_history,
      follow_up_intent: :review_support
    },
    explain: %{
      intent: :explanation_context,
      memory_kinds: [:fact, :decision, :lesson_learned, :pattern, :convention],
      provenance_kinds: [:plan, :review, :prompt_turn],
      freshness: :ready_only,
      provenance_scope: :workflow_history,
      follow_up_intent: :explanation
    }
  }

  @memory_kind_map %{
    "fact" => :fact,
    "decision" => :decision,
    "lesson_learned" => :lesson_learned,
    "invariant" => :invariant,
    "convention" => :convention,
    "known_issue" => :known_issue,
    "open_question" => :open_question,
    "pattern" => :pattern,
    "anti_pattern" => :anti_pattern
  }

  @provenance_kind_map %{
    "work_session" => :work_session,
    "agent_run" => :agent_run,
    "tool_invocation" => :tool_invocation,
    "prompt_turn" => :prompt_turn,
    "plan" => :plan,
    "patch" => :patch,
    "review" => :review
  }

  @intent_map %{
    "planning_constraints" => :planning_constraints,
    "implementation_constraints" => :implementation_constraints,
    "review_risks" => :review_risks,
    "explanation_context" => :explanation_context,
    "work_item" => :work_item,
    "review_support" => :review_support,
    "explanation" => :explanation
  }

  @spec normalize(workflow_kind(), keyword() | map() | nil) :: {:ok, policy()} | {:error, atom()}
  def normalize(workflow, nil) when workflow in [:plan, :execute, :review, :explain] do
    {:ok, default_policy(workflow)}
  end

  def normalize(workflow, opts) when workflow in [:plan, :execute, :review, :explain] and is_list(opts) do
    normalize(workflow, Map.new(opts))
  end

  def normalize(workflow, attrs) when workflow in [:plan, :execute, :review, :explain] and is_map(attrs) do
    defaults = default_policy(workflow)

    with {:ok, intent} <- normalize_atom(Map.get(attrs, :intent) || Map.get(attrs, "intent"), defaults.intent),
         {:ok, memory_kinds} <-
           normalize_kinds(
             Map.get(attrs, :memory_kinds) || Map.get(attrs, "memory_kinds"),
             defaults.memory_kinds
           ),
         {:ok, provenance_kinds} <-
           normalize_kinds(
             Map.get(attrs, :provenance_kinds) || Map.get(attrs, "provenance_kinds"),
             defaults.provenance_kinds
           ),
         {:ok, freshness} <-
           normalize_freshness(Map.get(attrs, :freshness) || Map.get(attrs, "freshness"), defaults.freshness),
         {:ok, provenance_scope} <-
           normalize_provenance_scope(
             Map.get(attrs, :provenance_scope) || Map.get(attrs, "provenance_scope"),
             defaults.provenance_scope
           ),
         {:ok, follow_up_intent} <-
           normalize_atom(
             Map.get(attrs, :follow_up_intent) || Map.get(attrs, "follow_up_intent"),
             defaults.follow_up_intent
           ) do
      {:ok,
       %{
         workflow: workflow,
         intent: intent,
         memory_kinds: memory_kinds,
         provenance_kinds: provenance_kinds,
         freshness: freshness,
         provenance_scope: provenance_scope,
         allow_stale?: freshness == :allow_stale,
         follow_up_intent: follow_up_intent,
         limit: positive_limit(Map.get(attrs, :limit) || Map.get(attrs, "limit"), defaults.limit)
       }}
    end
  end

  @spec apply_defaults(keyword(), policy()) :: keyword()
  def apply_defaults(memory_opts, %{limit: limit} = policy) when is_list(memory_opts) do
    memory_opts
    |> Keyword.put_new(:allow_stale?, policy.allow_stale?)
    |> maybe_put_memories(policy, limit)
    |> maybe_put_provenance(policy, limit)
  end

  @spec selection(policy(), map()) :: map()
  def selection(policy, result_projections) when is_map(result_projections) do
    memory_items =
      result_projections
      |> Map.get(:memories, %{})
      |> Map.get(:items, [])
      |> Enum.filter(&selected_memory?(&1, policy))

    provenance_items =
      result_projections
      |> Map.get(:provenance, %{})
      |> Map.get(:items, [])
      |> Enum.filter(&selected_provenance?(&1, policy))

    conversation_items =
      result_projections
      |> Map.get(:conversation_recall, %{})
      |> Map.get(:items, [])
      |> Enum.take(policy.limit)

    governed_references =
      [memory_items, provenance_items, conversation_items]
      |> List.flatten()
      |> Enum.flat_map(&item_governed_references/1)
      |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)

    conversation_resources =
      conversation_items
      |> Enum.flat_map(&(Map.get(&1, :resource_iris, []) |> List.wrap()))
      |> compact_strings()

    %{
      state: selection_state(result_projections, memory_items, provenance_items, conversation_items),
      retrieval_policy: summary(policy),
      memory_count: length(memory_items),
      provenance_count: length(provenance_items),
      conversation_count: length(conversation_items),
      governed_reference_count: length(governed_references),
      governed_references: governed_references,
      memory_resources: Enum.map(memory_items, &Map.get(&1, :memory_iri)) |> compact_strings(),
      provenance_resources: Enum.map(provenance_items, &Map.get(&1, :resource_iri)) |> compact_strings(),
      conversation_resources: conversation_resources,
      related_resources:
        [
          Enum.map(memory_items, &Map.get(&1, :memory_iri)),
          Enum.map(provenance_items, &Map.get(&1, :resource_iri)),
          conversation_resources
        ]
        |> List.flatten()
        |> compact_strings(),
      selected_items: %{
        memories: Enum.take(memory_items, policy.limit),
        provenance: Enum.take(provenance_items, policy.limit),
        conversation_recall: conversation_items
      }
    }
  end

  @spec summary(policy()) :: map()
  def summary(policy) do
    %{
      workflow: policy.workflow,
      intent: policy.intent,
      memory_kinds: policy.memory_kinds,
      provenance_kinds: policy.provenance_kinds,
      freshness: policy.freshness,
      provenance_scope: policy.provenance_scope,
      follow_up_intent: policy.follow_up_intent,
      limit: policy.limit,
      allow_stale?: policy.allow_stale?
    }
  end

  defp default_policy(workflow) do
    defaults = Map.fetch!(@default_policies, workflow)

    Map.put(defaults, :workflow, workflow)
    |> Map.put(:allow_stale?, defaults.freshness == :allow_stale)
    |> Map.put(:limit, Map.fetch!(@default_limits, workflow))
  end

  defp maybe_put_memories(memory_opts, policy, limit) do
    Keyword.put_new_lazy(memory_opts, :memories, fn ->
      [kinds: policy.memory_kinds, limit: limit]
    end)
  end

  defp maybe_put_provenance(memory_opts, %{provenance_scope: :none}, _limit), do: memory_opts

  defp maybe_put_provenance(memory_opts, policy, limit) do
    Keyword.put_new_lazy(memory_opts, :provenance, fn ->
      [kinds: policy.provenance_kinds, limit: limit]
    end)
  end

  defp selected_memory?(item, policy) when is_map(item) do
    ready? =
      case policy.freshness do
        :allow_stale ->
          true

        :ready_only ->
          is_nil(Map.get(item, :stale_reason)) and
            not stale_score?(Map.get(item, :freshness_score))
      end

    ready? and kind_selected?(Map.get(item, :memory_kind), policy.memory_kinds)
  end

  defp selected_memory?(_item, _policy), do: false

  defp selected_provenance?(item, policy) when is_map(item) do
    policy.provenance_scope != :none and
      kind_selected?(Map.get(item, :provenance_kind), policy.provenance_kinds)
  end

  defp selected_provenance?(_item, _policy), do: false

  defp kind_selected?(kind_name, allowed_kinds) when is_binary(kind_name) do
    normalized_name = Macro.underscore(kind_name)
    normalized = Map.get(@memory_kind_map, normalized_name, Map.get(@provenance_kind_map, normalized_name))

    normalized in allowed_kinds
  end

  defp kind_selected?(_kind_name, _allowed_kinds), do: false

  defp selection_state(result_projections, memory_items, provenance_items, conversation_items) do
    had_items? =
      Enum.any?(
        [
          get_in(result_projections, [:memories, :items]) || [],
          get_in(result_projections, [:provenance, :items]) || [],
          get_in(result_projections, [:conversation_recall, :items]) || []
        ],
        &(&1 != [])
      )

    cond do
      memory_items != [] or provenance_items != [] or conversation_items != [] -> :selected
      had_items? -> :filtered
      true -> :empty
    end
  end

  defp compact_strings(values) do
    values
    |> List.wrap()
    |> Enum.flat_map(fn
      value when is_binary(value) -> [String.trim(value)]
      _other -> []
    end)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp item_governed_references(item) when is_map(item) do
    item
    |> Map.get(:governed_context, [])
    |> List.wrap()
    |> Enum.flat_map(fn link ->
      case {Map.get(link, :kind), Map.get(link, :id), Map.get(link, :iri), Map.get(link, :label), Map.get(link, :route)} do
        {kind, id, iri, label, route} when is_atom(kind) and is_binary(id) ->
          [
            %{
              kind: kind,
              id: id,
              iri: iri,
              label: label,
              route: route
            }
          ]

        _other ->
          []
      end
    end)
  end

  defp item_governed_references(_item), do: []

  defp normalize_kinds(nil, default), do: {:ok, default}

  defp normalize_kinds(values, _default) when is_list(values) do
    normalized =
      values
      |> Enum.map(&normalize_kind/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized == [], do: {:error, :invalid_memory_retrieval_policy}, else: {:ok, normalized}
  end

  defp normalize_kinds(value, default), do: normalize_kinds([value], default)

  defp normalize_kind(value) when is_atom(value), do: value

  defp normalize_kind(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace("-", "_")
    |> Macro.underscore()
    |> case do
      "" -> nil
      normalized -> Map.get(@memory_kind_map, normalized, Map.get(@provenance_kind_map, normalized))
    end
  end

  defp normalize_kind(_value), do: nil

  defp normalize_freshness(nil, default), do: {:ok, default}
  defp normalize_freshness(:ready_only, _default), do: {:ok, :ready_only}
  defp normalize_freshness(:allow_stale, _default), do: {:ok, :allow_stale}

  defp normalize_freshness(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, default}
      "ready_only" -> {:ok, :ready_only}
      "allow_stale" -> {:ok, :allow_stale}
      _other -> {:error, :invalid_memory_retrieval_policy}
    end
  end

  defp normalize_freshness(_value, _default), do: {:error, :invalid_memory_retrieval_policy}

  defp normalize_provenance_scope(nil, default), do: {:ok, default}
  defp normalize_provenance_scope(:none, _default), do: {:ok, :none}
  defp normalize_provenance_scope(:workflow_history, _default), do: {:ok, :workflow_history}

  defp normalize_provenance_scope(:workflow_and_governed_history, _default),
    do: {:ok, :workflow_and_governed_history}

  defp normalize_provenance_scope(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, default}
      "none" -> {:ok, :none}
      "workflow_history" -> {:ok, :workflow_history}
      "workflow_and_governed_history" -> {:ok, :workflow_and_governed_history}
      _other -> {:error, :invalid_memory_retrieval_policy}
    end
  end

  defp normalize_provenance_scope(_value, _default), do: {:error, :invalid_memory_retrieval_policy}

  defp normalize_atom(nil, default), do: {:ok, default}
  defp normalize_atom(value, _default) when is_atom(value), do: {:ok, value}

  defp normalize_atom(value, default) when is_binary(value) do
    case String.trim(value) do
      "" -> {:ok, default}
      normalized -> Map.fetch(@intent_map, normalized)
    end
    |> case do
      {:ok, normalized} -> {:ok, normalized}
      :error -> {:error, :invalid_memory_retrieval_policy}
    end
  end

  defp normalize_atom(_value, _default), do: {:error, :invalid_memory_retrieval_policy}

  defp positive_limit(value, _default) when is_integer(value) and value > 0, do: value

  defp positive_limit(value, default) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} when parsed > 0 -> parsed
      _other -> default
    end
  end

  defp positive_limit(_value, default), do: default

  defp stale_score?(nil), do: false
  defp stale_score?(value) when is_number(value), do: value <= 0
  defp stale_score?(_value), do: false
end
