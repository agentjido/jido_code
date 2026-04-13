defmodule JidoCode.MemoryGraph.ViewModel do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  @moduledoc false

  alias JidoCode.MemoryGraph.GovernedReference
  alias JidoCode.MemoryGraph.ProductFeedback

  @known_memory_kind_suffixes ~w(
    Fact
    Decision
    LessonLearned
    Invariant
    Convention
    KnownIssue
    OpenQuestion
    Pattern
    AntiPattern
  )

  @known_provenance_kind_suffixes ~w(
    WorkSession
    AgentRun
    ToolInvocation
    PromptTurn
    Plan
    Patch
    Review
  )

  @type projection :: map()

  @spec status(String.t(), map()) :: projection()
  def status(managed_repo_id, status_result) when is_binary(managed_repo_id) and is_map(status_result) do
    normalized_graph = graph_state(status_result)

    %{
      kind: :memory_graph_status,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph),
      error: nil
    }
  end

  @spec recovery(String.t(), map()) :: projection()
  def recovery(managed_repo_id, graph_status) when is_binary(managed_repo_id) and is_map(graph_status) do
    normalized_graph = graph_state(graph_status)

    %{
      kind: :memory_graph_recovery,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph),
      error: nil
    }
  end

  @spec summary(String.t(), map(), map()) :: projection()
  def summary(managed_repo_id, status_result, groups)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(groups) do
    normalized_graph = graph_state(status_result)

    %{
      kind: :memory_graph_summary,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph),
      groups: groups,
      error: nil
    }
  end

  @spec memories(String.t(), map(), map()) :: projection()
  def memories(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :memories,
      managed_repo_id,
      status_result,
      raw_result,
      raw_result
      |> Map.get(:bindings, [])
      |> group_bindings("memory")
      |> Enum.map(&memory_item(&1, managed_repo_id))
    )
  end

  @spec provenance(String.t(), map(), map()) :: projection()
  def provenance(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :provenance,
      managed_repo_id,
      status_result,
      raw_result,
      raw_result
      |> Map.get(:bindings, [])
      |> group_bindings("resource")
      |> Enum.map(&provenance_item(&1, managed_repo_id))
    )
  end

  @spec cross_links(String.t(), map(), String.t(), map()) :: projection()
  def cross_links(managed_repo_id, status_result, resource_iri, navigation)
      when is_binary(managed_repo_id) and is_map(status_result) and is_binary(resource_iri) and is_map(navigation) do
    normalized_graph = graph_state(status_result)

    %{
      kind: :cross_links,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph),
      resource_iri: resource_iri,
      navigation: navigation,
      error: nil
    }
  end

  @spec error(atom(), String.t(), atom(), String.t(), map() | nil) :: projection()
  def error(kind, managed_repo_id, reason, detail, status_result \\ nil)
      when is_atom(kind) and is_binary(managed_repo_id) and is_atom(reason) and is_binary(detail) do
    normalized_graph = graph_state(status_result, reason)

    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph, %{type: reason, detail: detail}),
      error: %{
        type: reason,
        detail: detail,
        recovery_action: Map.get(normalized_graph, :recovery_action)
      }
    }
  end

  @spec summary_group(map() | nil, (map() -> projection())) :: map()
  def summary_group(nil, _builder), do: %{status: :unavailable, count: 0, items: []}

  def summary_group(raw_result, builder) when is_map(raw_result) and is_function(builder, 1) do
    projection = builder.(raw_result)

    %{
      status: :ok,
      count: projection.result_group.count,
      items: projection.items,
      degraded?: projection.result_group.degraded?,
      stale?: projection.result_group.stale?
    }
  end

  defp helper_projection(kind, managed_repo_id, status_result, raw_result, items) do
    normalized_graph = graph_state(status_result, raw_result)

    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: normalized_graph,
      feedback: ProductFeedback.for_graph(normalized_graph),
      items: items,
      result_group: %{
        helper: kind,
        count: length(items),
        empty?: items == [],
        degraded?: Map.get(normalized_graph, :degraded?, false),
        stale?: Map.get(normalized_graph, :stale?, false)
      },
      error: nil
    }
  end

  defp graph_state(status_result, raw_result_or_reason \\ nil)

  defp graph_state(nil, reason) when is_atom(reason), do: ProductFeedback.fallback_graph(reason)
  defp graph_state(nil, _raw_result_or_reason), do: ProductFeedback.fallback_graph(nil)

  defp graph_state(status_result, raw_result_or_reason) when is_map(status_result) do
    status_result
    |> maybe_overlay_query_state(raw_result_or_reason)
    |> ProductFeedback.normalize_graph()
  end

  defp maybe_overlay_query_state(status_result, raw_result) when is_map(raw_result) do
    stale? = Map.get(raw_result, :stale_graph?, Map.get(status_result, :stale?, false))
    degraded? = Map.get(raw_result, :degraded?, false) or stale?

    status_result
    |> Map.delete(:state)
    |> Map.put(:stale?, stale?)
    |> Map.put(:degraded?, degraded?)
    |> Map.put(:queryable_when_stale?, degraded?)
  end

  defp maybe_overlay_query_state(status_result, _raw_result_or_reason), do: status_result

  defp group_bindings(bindings, key) do
    bindings
    |> Enum.group_by(&value(&1, key))
    |> Enum.reject(fn {group_key, _rows} -> is_nil(group_key) end)
    |> Enum.map(fn {_group_key, rows} -> rows end)
  end

  defp memory_item(rows, managed_repo_id) when is_list(rows) and is_binary(managed_repo_id) do
    kind_iri =
      rows
      |> Enum.map(&value(&1, "kind"))
      |> Enum.find(&known_memory_kind?/1)

    module_iri = first_present_value(rows, "module")
    function_iri = first_present_value(rows, "function")

    %{
      memory_iri: first_present_value(rows, "memory"),
      memory_kind_iri: kind_iri || first_present_value(rows, "kind"),
      memory_kind: compact_name(kind_iri || first_present_value(rows, "kind")),
      content: first_present_value(rows, "content"),
      timestamp: first_present_value(rows, "timestamp"),
      confidence: first_decimal_value(rows, "confidence"),
      decision_status: compact_name(first_present_value(rows, "decisionStatus")),
      freshness_score: first_decimal_value(rows, "freshnessScore"),
      last_validated_at: first_present_value(rows, "lastValidatedAt"),
      stale_reason: first_present_value(rows, "staleReason"),
      module_iri: module_iri,
      module_name: compact_name(module_iri),
      function_iri: function_iri,
      function_name: compact_name(function_iri),
      subject_iri: first_present_value(rows, "subject"),
      governed_context: governed_context(rows, managed_repo_id)
    }
  end

  defp provenance_item(rows, managed_repo_id) when is_list(rows) and is_binary(managed_repo_id) do
    kind_iri =
      rows
      |> Enum.map(&value(&1, "kind"))
      |> Enum.find(&known_provenance_kind?/1)

    module_iri = first_present_value(rows, "module")
    function_iri = first_present_value(rows, "function")

    %{
      resource_iri: first_present_value(rows, "resource"),
      provenance_kind_iri: kind_iri || first_present_value(rows, "kind"),
      provenance_kind: compact_name(kind_iri || first_present_value(rows, "kind")),
      label: first_present_value(rows, "label"),
      content: first_present_value(rows, "content"),
      started_at: first_present_value(rows, "startedAt"),
      ended_at: first_present_value(rows, "endedAt"),
      session_iri: first_present_value(rows, "session"),
      module_iri: module_iri,
      module_name: compact_name(module_iri),
      function_iri: function_iri,
      function_name: compact_name(function_iri),
      subject_iri: first_present_value(rows, "subject"),
      revision_iri: first_present_value(rows, "revision"),
      governed_context: governed_context(rows, managed_repo_id)
    }
  end

  defp governed_context(rows, managed_repo_id) when is_list(rows) and is_binary(managed_repo_id) do
    rows
    |> Enum.flat_map(fn row ->
      governed_context_item(row, managed_repo_id)
    end)
    |> Enum.uniq_by(& &1.iri)
  end

  defp governed_context_item(row, managed_repo_id) when is_map(row) and is_binary(managed_repo_id) do
    case value(row, "governedRecord") do
      governed_iri when is_binary(governed_iri) ->
        case GovernedReference.parse_iri(managed_repo_id, governed_iri) do
          {:ok, reference} ->
            [
              %{
                kind: reference.kind,
                id: reference.id,
                iri: reference.iri,
                label: value(row, "governedLabel") || reference.label,
                route: GovernedReference.route(managed_repo_id, reference)
              }
            ]

          _other ->
            []
        end

      _other ->
        []
    end
  end

  defp first_present_value(rows, key) do
    rows
    |> Enum.map(&value(&1, key))
    |> Enum.find(&(not is_nil(&1)))
  end

  defp first_decimal_value(rows, key) do
    rows
    |> Enum.map(&decimal_value(&1, key))
    |> Enum.find(&(not is_nil(&1)))
  end

  defp known_memory_kind?(value), do: known_kind_suffix?(value, @known_memory_kind_suffixes)
  defp known_provenance_kind?(value), do: known_kind_suffix?(value, @known_provenance_kind_suffixes)

  defp known_kind_suffix?(nil, _suffixes), do: false

  defp known_kind_suffix?(value, suffixes) when is_binary(value) do
    Enum.any?(suffixes, &String.ends_with?(value, "##{&1}") or String.ends_with?(value, "/#{&1}"))
  end

  defp known_kind_suffix?(_value, _suffixes), do: false

  defp value(binding, key) when is_map(binding) do
    binding
    |> Map.get(key, %{})
    |> case do
      %{value: value} -> value
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp decimal_value(binding, key) do
    case value(binding, key) do
      value when is_float(value) -> value
      value when is_integer(value) -> value / 1
      value when is_binary(value) ->
        case Float.parse(value) do
          {parsed, ""} -> parsed
          _other -> nil
        end

      _other -> nil
    end
  end

  defp compact_name(nil), do: nil

  defp compact_name("nil"), do: nil

  defp compact_name(value) when is_binary(value) do
    value
    |> String.split(["#", "/"])
    |> List.last()
  end
end
