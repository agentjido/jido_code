defmodule JidoCode.MemoryGraph.SurfaceFeedback do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  @moduledoc false

  alias JidoCode.MemoryGraph.ProductFeedback

  @spec recovery_result(map() | nil, keyword()) :: map()
  def recovery_result(graph, opts \\ []) do
    normalized_graph = ProductFeedback.normalize_graph(graph)

    %{
      kind: :info,
      error_type: "memory_graph_recovered",
      detail: "#{completed_recovery_label(opts, normalized_graph)} completed successfully for #{surface_label(opts)}.",
      remediation: state_summary(normalized_graph)
    }
  end

  @spec recovery_error(term(), map() | nil, keyword()) :: map()
  def recovery_error(reason, diagnostics, opts \\ []) do
    normalized_graph = ProductFeedback.normalize_graph(Keyword.get(opts, :graph))

    %{
      kind: :error,
      error_type: normalize_error_type(reason, "memory_graph_recovery_failed"),
      detail: recovery_error_detail(reason, diagnostics, surface_label(opts)),
      remediation: recovery_guidance(normalized_graph)
    }
  end

  @spec action_result(atom(), keyword()) :: map()
  def action_result(action, opts \\ []) do
    normalized_graph = ProductFeedback.normalize_graph(Keyword.get(opts, :graph))

    %{
      kind: :info,
      error_type: action_error_type(action),
      detail: action_detail(action, opts),
      remediation: state_summary(normalized_graph)
    }
  end

  @spec action_error(term(), keyword()) :: map()
  def action_error(reason, opts \\ []) do
    normalized_graph = ProductFeedback.normalize_graph(Keyword.get(opts, :graph))

    %{
      kind: :error,
      error_type: normalize_error_type(reason, "memory_action_failed"),
      detail: action_error_detail(reason, surface_label(opts)),
      remediation: recovery_guidance(normalized_graph)
    }
  end

  defp action_error_type(:validate), do: "memory_validation_recorded"
  defp action_error_type(:invalidate), do: "memory_invalidation_recorded"
  defp action_error_type(:promote_follow_up), do: "memory_follow_up_created"
  defp action_error_type(:supersede_with_governed_decision), do: "memory_supersession_recorded"
  defp action_error_type(_action), do: "memory_action_recorded"

  defp action_detail(:validate, opts) do
    "Recorded durable memory validation for #{surface_label(opts)}."
  end

  defp action_detail(:invalidate, opts) do
    "Recorded durable memory invalidation for #{surface_label(opts)}."
  end

  defp action_detail(:promote_follow_up, opts) do
    case normalize_optional_string(Keyword.get(opts, :work_item_id)) do
      nil ->
        "Created a governed follow-up work item from durable memory on #{surface_label(opts)}."

      work_item_id ->
        "Created governed follow-up work item #{work_item_id} from durable memory on #{surface_label(opts)}."
    end
  end

  defp action_detail(:supersede_with_governed_decision, opts) do
    "Superseded durable decision memory with the latest governed decision on #{surface_label(opts)}."
  end

  defp action_detail(_action, opts) do
    "Completed the requested durable memory update on #{surface_label(opts)}."
  end

  defp action_error_detail(:memory_item_not_found, surface_label) do
    "The selected durable memory could not be found on #{surface_label}."
  end

  defp action_error_detail(:governed_decision_not_found, surface_label) do
    "The latest governed decision was unavailable for durable supersession on #{surface_label}."
  end

  defp action_error_detail(:memory_supersession_requires_decision, surface_label) do
    "Only durable decision memories can be superseded from #{surface_label}."
  end

  defp action_error_detail(:unsupported_memory_promotion_target, surface_label) do
    "The requested durable memory promotion target is not available on #{surface_label}."
  end

  defp action_error_detail({:missing_memory_operator_context, field}, surface_label) do
    "The durable memory action is missing #{field} for #{surface_label}."
  end

  defp action_error_detail(reason, surface_label) when is_atom(reason) do
    "The durable memory action could not be completed on #{surface_label} (#{reason})."
  end

  defp action_error_detail(_reason, surface_label) do
    "The durable memory action could not be completed on #{surface_label}."
  end

  defp recovery_error_detail(_reason, diagnostics, surface_label) when is_map(diagnostics) do
    map_get(diagnostics, :message, "message") ||
      map_get(diagnostics, :detail, "detail") ||
      map_get(diagnostics, :reason, "reason") ||
      "Repository memory recovery failed for #{surface_label}."
  end

  defp recovery_error_detail(reason, _diagnostics, surface_label) do
    "Repository memory recovery failed for #{surface_label} (#{reason})."
  end

  defp completed_recovery_label(opts, normalized_graph) do
    opts
    |> Keyword.get(:action)
    |> case do
      action when is_atom(action) ->
        ProductFeedback.recovery_label(action)

      _other ->
        ProductFeedback.recovery_label(Map.get(normalized_graph, :recovery_action, :recover))
    end || "Recover memory graph"
  end

  defp surface_label(opts) do
    normalize_optional_string(Keyword.get(opts, :surface_label)) || "this governed surface"
  end

  defp state_summary(normalized_graph) do
    "Current repository memory state: #{ProductFeedback.state_label(normalized_graph)}."
  end

  defp recovery_guidance(normalized_graph) do
    case ProductFeedback.recovery(normalized_graph) do
      %{available?: true, label: label} when is_binary(label) ->
        "If repository memory still looks stale or unavailable, #{String.downcase(label)} from the surface notice."

      _other ->
        ProductFeedback.for_graph(normalized_graph).remediation ||
          "Review repository memory status and retry once bounded graph inputs are available."
    end
  end

  defp normalize_error_type(reason, _fallback) when is_atom(reason), do: Atom.to_string(reason)

  defp normalize_error_type(reason, fallback) when is_binary(reason) do
    case String.trim(reason) do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_error_type(_reason, fallback), do: fallback

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

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
