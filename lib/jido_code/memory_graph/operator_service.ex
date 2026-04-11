defmodule JidoCode.MemoryGraph.OperatorService do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  @moduledoc """
  Product-owned operator action boundary for durable memory mutation and follow-up.

  Operator-facing surfaces use this module to evolve repository memory without
  performing direct graph writes from LiveView or calling pod internals.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{DurableMemoryEnvelope, DurableMemoryUpdateEnvelope, GovernedAdoption, GovernedReference}

  @operator_actor Actor.operator_actor(%{
                    "id" => "system:memory-graph-operator",
                    "email" => "memory-graph-operator@system.local"
                  })

  @type projection :: map()
  @type memory_item :: map()

  @spec validate(projection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def validate(projection, memory_iri, opts \\ [])

  def validate(%{kind: :memories} = projection, memory_iri, opts) when is_binary(memory_iri) do
    with {:ok, item} <- select_memory(projection, memory_iri),
         {:ok, context} <- action_context(projection, item, opts),
         {:ok, record} <-
           AgentWorkspace.record_memory_graph(
             context.managed_repo_id,
             context.workspace_path,
             DurableMemoryUpdateEnvelope.memory_validation(
               memory_iri: memory_iri,
               actor_id: context.actor_id,
               session_id: operator_session_id(:validate, memory_iri, context.revision),
               revision: context.revision,
               freshness_score: Keyword.get(opts, :freshness_score, 1.0),
               governed_references: context.governed_references
             ),
             revision: context.revision
           ) do
      {:ok,
       %{
         status: :memory_validated,
         memory: item,
         record: record
       }}
    end
  end

  def validate(_projection, _memory_iri, _opts), do: {:error, :invalid_memory_projection}

  @spec invalidate(projection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def invalidate(projection, memory_iri, opts \\ [])

  def invalidate(%{kind: :memories} = projection, memory_iri, opts) when is_binary(memory_iri) do
    with {:ok, item} <- select_memory(projection, memory_iri),
         {:ok, context} <- action_context(projection, item, opts),
         {:ok, stale_reason} <- stale_reason(opts),
         {:ok, record} <-
           AgentWorkspace.record_memory_graph(
             context.managed_repo_id,
             context.workspace_path,
             DurableMemoryUpdateEnvelope.memory_invalidation(
               memory_iri: memory_iri,
               actor_id: context.actor_id,
               session_id: operator_session_id(:invalidate, memory_iri, context.revision),
               revision: context.revision,
               stale_reason: stale_reason,
               governed_references: context.governed_references
             ),
             revision: context.revision
           ) do
      {:ok,
       %{
         status: :memory_invalidated,
         memory: item,
         record: record
       }}
    end
  end

  def invalidate(_projection, _memory_iri, _opts), do: {:error, :invalid_memory_projection}

  @spec supersede_with_governed_decision(projection(), String.t(), map(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def supersede_with_governed_decision(projection, memory_iri, decision, opts \\ [])

  def supersede_with_governed_decision(%{kind: :memories} = projection, memory_iri, decision, opts)
      when is_binary(memory_iri) and is_map(decision) do
    with {:ok, item} <- select_memory(projection, memory_iri),
         :ok <- ensure_decision_memory(item),
         {:ok, context} <- action_context(projection, item, opts),
         {:ok, decision_id} <- required_string(map_get(decision, :id, "id"), :decision_id),
         {:ok, successor_capture} <-
           successor_decision_capture(context, item, decision, decision_id, opts),
         {:ok, successor_record} <-
           AgentWorkspace.record_memory_graph(
             context.managed_repo_id,
             context.workspace_path,
             successor_capture,
             revision: context.revision
           ),
         {:ok, update_record} <-
           AgentWorkspace.record_memory_graph(
             context.managed_repo_id,
             context.workspace_path,
             DurableMemoryUpdateEnvelope.decision_supersession(
               memory_iri: successor_record.capture.resource_iri,
               superseded_memory_iri: memory_iri,
               actor_id: context.actor_id,
               session_id: operator_session_id(:supersede, memory_iri, context.revision),
               revision: context.revision,
               governed_references: context.governed_references ++ [%{kind: :decision, id: decision_id}]
             ),
             revision: context.revision
           ) do
      {:ok,
       %{
         status: :memory_superseded,
         memory: item,
         successor_record: successor_record,
         update_record: update_record
       }}
    end
  end

  def supersede_with_governed_decision(_projection, _memory_iri, _decision, _opts),
    do: {:error, :invalid_memory_projection}

  @spec promote_follow_up(projection(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def promote_follow_up(projection, memory_iri, opts \\ [])

  def promote_follow_up(%{kind: :memories} = projection, memory_iri, opts) when is_binary(memory_iri) do
    with {:ok, item} <- select_memory(projection, memory_iri),
         {:ok, context} <- action_context(projection, item, opts),
         {:ok, result} <- promote(selected_projection(projection, item), item, context, opts) do
      {:ok,
       %{
         status: :memory_promoted,
         target: Keyword.get(opts, :target, :work_item),
         memory: item,
         result: result
       }}
    end
  end

  def promote_follow_up(_projection, _memory_iri, _opts), do: {:error, :invalid_memory_projection}

  defp promote(projection, item, context, opts) do
    target = Keyword.get(opts, :target, :work_item)
    query = promotion_query(item)

    shared_opts =
      [
        selected_items: [item],
        actor: context.actor,
        workspace_path: context.workspace_path,
        query: query,
        run_id: Keyword.get(opts, :run_id),
        work_item_id: Keyword.get(opts, :work_item_id),
        evidence_id: Keyword.get(opts, :evidence_id),
        decision_id: Keyword.get(opts, :decision_id),
        assessment_id: Keyword.get(opts, :assessment_id),
        observation_id: Keyword.get(opts, :observation_id)
      ]

    case target do
      :work_item -> GovernedAdoption.adopt_work_item(projection, shared_opts)
      :evidence -> GovernedAdoption.adopt_evidence(projection, shared_opts)
      :review_support -> GovernedAdoption.review_support(projection, shared_opts)
      _other -> {:error, :unsupported_memory_promotion_target}
    end
  end

  defp selected_projection(projection, item) do
    result_group =
      projection
      |> Map.get(:result_group, %{})
      |> Map.put(:count, 1)
      |> Map.put(:empty?, false)

    projection
    |> Map.put(:items, [item])
    |> Map.put(:result_group, result_group)
  end

  defp action_context(projection, item, opts) do
    with {:ok, managed_repo_id} <- required_string(Map.get(projection, :managed_repo_id), :managed_repo_id),
         {:ok, workspace_path} <- MemoryGraph.normalize_workspace_path(Keyword.get(opts, :workspace_path)),
         {:ok, revision} <- revision(workspace_path, projection, opts) do
      actor = actor(opts)

      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         workspace_path: workspace_path,
         revision: revision,
         actor: actor,
         actor_id: actor_id(actor, opts),
         governed_references: governed_references(item, opts)
       }}
    end
  end

  defp select_memory(%{items: items}, memory_iri) when is_list(items) do
    case Enum.find(items, &(Map.get(&1, :memory_iri) == memory_iri)) do
      nil -> {:error, :memory_item_not_found}
      item -> {:ok, item}
    end
  end

  defp select_memory(_projection, _memory_iri), do: {:error, :memory_item_not_found}

  defp ensure_decision_memory(item) do
    if decision_memory?(item), do: :ok, else: {:error, :memory_supersession_requires_decision}
  end

  defp successor_decision_capture(context, item, decision, decision_id, opts) do
    content =
      normalize_optional_string(map_get(decision, :decision, "decision")) ||
        "Governed decision #{decision_id}"

    rationale =
      normalize_optional_string(map_get(decision, :rationale, "rationale")) ||
        "An operator superseded older durable decision memory using the current governed decision."

    {:ok,
     DurableMemoryEnvelope.decision(
       session_id: operator_session_id(:successor_decision, item.memory_iri, context.revision),
       actor_id: context.actor_id,
       workflow: :review,
       work_item_id: Keyword.get(opts, :work_item_id),
       revision: context.revision,
       content: content,
       rationale: rationale,
       decision_status: :accepted,
       anchors: %{
         module_name: Map.get(item, :module_name),
         subject_iri: Map.get(item, :subject_iri)
       },
       governed_references:
         (context.governed_references ++ [%{kind: :decision, id: decision_id}])
         |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end),
       classification: %{
         source: "memory_graph_operator_service",
         reason: "Operator superseded a durable decision memory with the current governed decision."
       }
     )}
  end

  defp promotion_query(item) do
    %{}
    |> maybe_put(:resource_iri, Map.get(item, :memory_iri))
    |> maybe_put(:subject_iri, Map.get(item, :subject_iri))
    |> maybe_put(:module_name, Map.get(item, :module_name))
    |> maybe_put(:function_name, Map.get(item, :function_name))
  end

  defp governed_references(item, opts) do
    explicit =
      opts
      |> Keyword.take([:run_id, :work_item_id, :evidence_id, :decision_id, :observation_id, :assessment_id])
      |> GovernedReference.explicit_many()

    inherited =
      item
      |> Map.get(:navigation, %{})
      |> Map.get(:governed_records, [])
      |> Enum.flat_map(fn link ->
        case {Map.get(link, :kind), normalize_optional_string(Map.get(link, :id))} do
          {kind, id}
          when kind in [:run, :work_item, :evidence, :decision, :observation, :assessment] and is_binary(id) ->
            [%{kind: kind, id: id}]

          _other ->
            []
        end
      end)

    (explicit ++ inherited)
    |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)
  end

  defp stale_reason(opts) do
    case normalize_optional_string(Keyword.get(opts, :stale_reason) || "operator_review_required") do
      nil -> {:error, :invalid_memory_stale_reason}
      value -> {:ok, value}
    end
  end

  defp revision(workspace_path, projection, opts) do
    candidate =
      Keyword.get(opts, :revision) ||
        get_in(projection, [:graph, :current_revision]) ||
        get_in(projection, [:graph, :validated_revision])

    case normalize_optional_string(candidate) do
      nil ->
        with {:ok, revision_metadata} <- MemoryGraph.current_revision_metadata(workspace_path),
             {:ok, revision} <- required_string(revision_metadata.current_revision, :revision) do
          {:ok, revision}
        end

      revision ->
        {:ok, revision}
    end
  end

  defp actor(opts) do
    opts
    |> Keyword.get(:actor)
    |> Actor.effective_actor()
    |> case do
      nil -> @operator_actor
      actor -> actor
    end
  end

  defp actor_id(actor, opts) do
    normalize_optional_string(
      Keyword.get(opts, :actor_id) || map_get(actor, :id, "id") || map_get(actor, :actor_id, "actor_id")
    ) || "system:memory-graph-operator"
  end

  defp operator_session_id(kind, memory_iri, revision) do
    suffix =
      [kind, memory_iri, revision, System.unique_integer([:positive])]
      |> Enum.join(":")
      |> then(&:crypto.hash(:sha256, &1))
      |> Base.encode16(case: :lower)
      |> binary_part(0, 12)

    "memory-operator-#{kind}-#{suffix}"
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp required_string(value, field) do
    case normalize_optional_string(value) do
      nil -> {:error, {:missing_memory_operator_context, field}}
      normalized -> {:ok, normalized}
    end
  end

  defp map_get(map, atom_key, string_key) when is_map(map) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

  defp decision_memory?(item) when is_map(item) do
    normalize_optional_string(map_get(item, :memory_kind, "memory_kind")) == "Decision" ||
      kind_from_memory_iri(map_get(item, :memory_iri, "memory_iri")) == "Decision"
  end

  defp decision_memory?(_item), do: false

  defp kind_from_memory_iri(value) when is_binary(value) do
    value
    |> String.split("#")
    |> List.last()
    |> case do
      nil -> nil
      fragment -> fragment |> String.split("/") |> List.first()
    end
    |> normalize_optional_string()
    |> case do
      nil -> nil
      segment -> segment |> String.replace("-", "_") |> Macro.camelize()
    end
  end

  defp kind_from_memory_iri(_value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
