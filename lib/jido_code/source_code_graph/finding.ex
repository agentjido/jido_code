defmodule JidoCode.SourceCodeGraph.Finding do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  @moduledoc """
  Builds bounded semantic findings from product-shaped source-code graph projections.
  """

  @supported_projection_kinds [:modules, :functions, :runtime_patterns, :impact]

  @spec from_projection(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def from_projection(projection, opts \\ [])

  def from_projection(%{managed_repo_id: managed_repo_id, kind: kind} = projection, opts)
      when is_binary(managed_repo_id) and kind in @supported_projection_kinds do
    selected_items =
      opts
      |> Keyword.get(:selected_items, Map.get(projection, :items, []))
      |> List.wrap()
      |> Enum.take(Keyword.get(opts, :item_limit, 10))

    graph = normalize_graph(Map.get(projection, :graph, %{}))
    provenance = provenance(projection, opts, selected_items)

    finding =
      %{
        kind: :semantic_finding,
        finding_type: Keyword.get(opts, :finding_type, kind),
        managed_repo_id: managed_repo_id,
        summary: finding_summary(projection, selected_items, opts),
        category: Keyword.get(opts, :category, default_category(kind)),
        priority: Keyword.get(opts, :priority, default_priority(kind)),
        urgency: Keyword.get(opts, :urgency, default_urgency(kind)),
        recommended_action: Keyword.get(opts, :recommended_action, default_recommended_action(kind)),
        graph: graph,
        provenance: provenance,
        payload: %{
          items: selected_items,
          result_group: normalize_map(Map.get(projection, :result_group, %{})),
          error: normalize_map(Map.get(projection, :error, %{}))
        }
      }
      |> Map.put(
        :digest,
        digest(%{
          managed_repo_id: managed_repo_id,
          finding_type: kind,
          summary: finding_summary(projection, selected_items, opts),
          graph: graph,
          provenance: provenance,
          payload: selected_items
        })
      )

    {:ok, finding}
  end

  def from_projection(_projection, _opts), do: {:error, :invalid_semantic_projection}

  defp finding_summary(projection, selected_items, opts) do
    case normalize_optional_string(Keyword.get(opts, :summary)) do
      nil -> default_summary(projection, selected_items)
      summary -> summary
    end
  end

  defp default_summary(%{kind: :modules}, [%{module_name: module_name} | _rest])
       when is_binary(module_name) do
    "Inspect semantic module finding for #{module_name}."
  end

  defp default_summary(%{kind: :functions}, [%{module_name: module_name, function_name: function_name} | _rest])
       when is_binary(module_name) and is_binary(function_name) do
    "Inspect semantic function finding for #{module_name}.#{function_name}."
  end

  defp default_summary(%{kind: :runtime_patterns}, [%{pattern_name: pattern_name} | _rest])
       when is_binary(pattern_name) do
    "Inspect semantic runtime pattern finding for #{pattern_name}."
  end

  defp default_summary(%{kind: :impact}, [%{predicate_name: predicate_name} | _rest])
       when is_binary(predicate_name) do
    "Inspect semantic impact finding for #{predicate_name}."
  end

  defp default_summary(%{kind: kind}, selected_items) do
    "Inspect #{length(selected_items)} #{kind} semantic findings for the managed repository."
  end

  defp default_category(:modules), do: "semantic_module_finding"
  defp default_category(:functions), do: "semantic_function_finding"
  defp default_category(:runtime_patterns), do: "semantic_runtime_pattern_finding"
  defp default_category(:impact), do: "semantic_impact_finding"

  defp default_priority(:runtime_patterns), do: :high
  defp default_priority(:impact), do: :high
  defp default_priority(:functions), do: :medium
  defp default_priority(_kind), do: :medium

  defp default_urgency(:runtime_patterns), do: :high
  defp default_urgency(:impact), do: :high
  defp default_urgency(_kind), do: :medium

  defp default_recommended_action(:modules), do: "review_semantic_module_finding"
  defp default_recommended_action(:functions), do: "review_semantic_function_finding"
  defp default_recommended_action(:runtime_patterns), do: "review_semantic_runtime_pattern"
  defp default_recommended_action(:impact), do: "review_semantic_impact_finding"

  defp provenance(projection, opts, selected_items) do
    %{
      projection_kind: Map.get(projection, :kind),
      result_count: get_in(projection, [:result_group, :count]) || length(Map.get(projection, :items, [])),
      selected_count: length(selected_items),
      query: normalize_map(Keyword.get(opts, :query, %{})),
      requested_by: normalize_map(Keyword.get(opts, :requested_by, %{}))
    }
  end

  defp normalize_graph(graph) when is_map(graph) do
    %{
      graph_name: Map.get(graph, :graph_name, "source_code"),
      state: Map.get(graph, :state),
      ready?: Map.get(graph, :ready?, false),
      stale?: Map.get(graph, :stale?, false),
      degraded?: Map.get(graph, :degraded?, false),
      imported_revision: Map.get(graph, :imported_revision),
      current_revision: Map.get(graph, :current_revision),
      latest_failure: normalize_map(Map.get(graph, :latest_failure, %{})),
      recovery_action: Map.get(graph, :recovery_action)
    }
  end

  defp normalize_graph(_graph) do
    %{
      graph_name: "source_code",
      state: :not_ready,
      ready?: false,
      stale?: false,
      degraded?: false,
      imported_revision: nil,
      current_revision: nil,
      latest_failure: %{},
      recovery_action: :load
    }
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value), do: value

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
