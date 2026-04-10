defmodule JidoCode.MemoryGraph.GovernedSurfaceContext do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  @moduledoc """
  Product-owned memory context shaping for governed product surfaces.

  Governed surfaces remain canonical product routes while this boundary loads
  bounded memory and workflow-provenance context for the records already in view.
  """

  alias JidoCode.MemoryGraph.ProductFeedback
  alias JidoCode.MemoryGraph.ProductService
  alias JidoCode.Orchestration.Run

  @default_graph %{
    graph_name: "memory",
    ready?: false,
    stale?: false,
    degraded?: false,
    queryable_when_stale?: false,
    state: :unavailable,
    current_revision: nil,
    validated_revision: nil,
    latest_failure: nil,
    recovery_action: :none,
    cross_graph: %{consistency: %{state: :unknown, explainable?: true}}
  }

  @spec load_run_detail(map(), Run.t(), [map()], [map()], keyword()) :: map()
  def load_run_detail(scope, %Run{} = run, evidence_records, decisions, opts \\ []) do
    case run_scope(scope, run, opts) do
      {:ok, managed_repo_id, workspace_path} ->
        status = projection_for(ProductService.status(managed_repo_id, workspace_path, opts))
        graph = Map.get(status, :graph, @default_graph)
        lookup_opts = Keyword.put_new(opts, :allow_stale?, true)
        artifact_paths = run_artifact_paths(run, evidence_records, decisions)
        run_route = "/repos/#{managed_repo_id}/runs/#{run.run_id}"

        {memories, provenance} =
          if queryable_graph?(graph) and artifact_paths != [] do
            {
              navigation_projection(
                ProductService.memories_for_governed_artifacts(
                  managed_repo_id,
                  workspace_path,
                  artifact_paths,
                  Keyword.put_new(lookup_opts, :limit, 8)
                ),
                managed_repo_id,
                workspace_path,
                run_route,
                lookup_opts
              ),
              navigation_projection(
                ProductService.provenance_for_governed_artifacts(
                  managed_repo_id,
                  workspace_path,
                  artifact_paths,
                  Keyword.put_new(lookup_opts, :limit, 8)
                ),
                managed_repo_id,
                workspace_path,
                run_route,
                lookup_opts
              )
            }
          else
            {
              empty_lookup(:memories, managed_repo_id, graph),
              empty_lookup(:provenance, managed_repo_id, graph)
            }
          end

        %{
          available?: true,
          managed_repo_id: managed_repo_id,
          workspace_path: workspace_path,
          graph: graph,
          memories: memories,
          provenance: provenance,
          governed_history: %{
            evidence: history_summary(evidence_records, memories.items, provenance.items, :evidence),
            decisions: history_summary(decisions, memories.items, provenance.items, :decision)
          },
          notice: governed_notice(status),
          notice_kind: ProductFeedback.notice_kind(graph),
          recovery: ProductFeedback.recovery(graph)
        }

      {:error, notice} ->
        unavailable_context(notice)
    end
  end

  defp run_scope(scope, %Run{} = run, opts) do
    managed_repo_id =
      normalize_optional_string(Keyword.get(opts, :managed_repo_id)) ||
        normalize_optional_string(map_get(run, :managed_repo_id, "managed_repo_id")) ||
        normalize_optional_string(map_get(scope, :managed_repo_id, "managed_repo_id"))

    workspace_path =
      normalize_optional_string(Keyword.get(opts, :workspace_path)) ||
        normalize_optional_string(map_get(scope, :workspace_path, "workspace_path")) ||
        managed_workspace_path(map_get(scope, :managed_repo, "managed_repo"))

    cond do
      is_nil(managed_repo_id) ->
        {:error,
         %{
           error_type: "memory_governed_scope_unavailable",
           detail: "Governed memory context needs a managed repository identifier.",
           remediation: "Open this run from a canonical managed-repository route and retry."
         }}

      is_nil(workspace_path) ->
        {:error,
         %{
           error_type: "memory_workspace_unavailable",
           detail: "Governed memory context needs a repository workspace path before it can load memory graph state.",
           remediation: "Complete workspace import for this managed repository and retry."
         }}

      true ->
        {:ok, managed_repo_id, workspace_path}
    end
  end

  defp managed_workspace_path(managed_repo) when is_map(managed_repo) do
    managed_repo
    |> map_get(:workspace_settings, "workspace_settings", %{})
    |> map_get(:workspace_path, "workspace_path")
    |> normalize_optional_string()
  end

  defp managed_workspace_path(_managed_repo), do: nil

  defp run_artifact_paths(%Run{} = run, evidence_records, decisions) do
    []
    |> maybe_add_artifact(:run, normalize_optional_string(run.run_id))
    |> add_artifacts(evidence_records, :evidence)
    |> add_artifacts(decisions, :decision)
  end

  defp maybe_add_artifact(paths, _kind, nil), do: paths

  defp maybe_add_artifact(paths, kind, id) do
    case JidoCode.MemoryGraph.artifact_path(kind, id) do
      nil -> paths
      path -> paths ++ [path]
    end
  end

  defp add_artifacts(paths, records, kind) when is_list(records) do
    Enum.reduce(records, paths, fn record, acc ->
      maybe_add_artifact(acc, kind, normalize_optional_string(map_get(record, :id, "id")))
    end)
  end

  defp navigation_projection({:ok, projection}, managed_repo_id, workspace_path, run_route, opts) do
    Map.put(
      projection,
      :items,
      attach_navigation(Map.get(projection, :items, []), managed_repo_id, workspace_path, run_route, opts)
    )
  end

  defp navigation_projection({:error, _reason, projection}, managed_repo_id, workspace_path, run_route, opts) do
    Map.put(
      projection,
      :items,
      attach_navigation(Map.get(projection, :items, []), managed_repo_id, workspace_path, run_route, opts)
    )
  end

  defp attach_navigation(items, managed_repo_id, workspace_path, run_route, opts) when is_list(items) do
    Enum.map(items, fn item ->
      resource_iri = Map.get(item, :memory_iri) || Map.get(item, :resource_iri)

      navigation =
        case resource_iri do
          resource_iri when is_binary(resource_iri) ->
            case ProductService.cross_links(managed_repo_id, workspace_path, resource_iri, opts) do
              {:ok, projection} ->
                patch_governed_navigation(projection.navigation, run_route)

              _other ->
                %{source_code: [], governed_records: [], related_memories: []}
            end

          _other ->
            %{source_code: [], governed_records: [], related_memories: []}
        end

      Map.put(item, :navigation, navigation)
    end)
  end

  defp patch_governed_navigation(navigation, run_route) when is_map(navigation) do
    governed_records =
      Enum.map(Map.get(navigation, :governed_records, []), fn link ->
        case {Map.get(link, :kind), Map.get(link, :route)} do
          {:evidence, nil} -> Map.put(link, :route, run_route <> "#run-detail-evidence-records")
          {:decision, nil} -> Map.put(link, :route, run_route <> "#run-detail-decisions")
          _other -> link
        end
      end)

    Map.put(navigation, :governed_records, governed_records)
  end

  defp history_summary(records, memories, provenance, kind) do
    Enum.map(records, fn record ->
      record_id = normalize_optional_string(map_get(record, :id, "id"))

      %{
        id: record_id,
        label: history_label(record, kind),
        memory_count: related_count(memories, kind, record_id),
        provenance_count: related_count(provenance, kind, record_id)
      }
    end)
  end

  defp related_count(items, kind, record_id) do
    Enum.count(items, fn item ->
      item
      |> Map.get(:navigation, %{})
      |> Map.get(:governed_records, [])
      |> Enum.any?(fn link ->
        Map.get(link, :kind) == kind and normalize_optional_string(Map.get(link, :id)) == record_id
      end)
    end)
  end

  defp history_label(record, :evidence) do
    normalize_optional_string(map_get(record, :key, "key")) || "Evidence"
  end

  defp history_label(record, :decision) do
    normalize_optional_string(map_get(record, :decision, "decision")) || "Decision"
  end

  defp queryable_graph?(graph) when is_map(graph) do
    Map.get(graph, :ready?, false) or (Map.get(graph, :stale?, false) and Map.get(graph, :queryable_when_stale?, false))
  end

  defp empty_lookup(kind, managed_repo_id, graph) do
    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: graph,
      feedback: ProductFeedback.for_graph(graph),
      items: [],
      result_group: %{
        helper: kind,
        count: 0,
        empty?: true,
        degraded?: Map.get(graph, :degraded?, false),
        stale?: Map.get(graph, :stale?, false)
      },
      error: nil
    }
  end

  defp unavailable_context(notice) do
    %{
      available?: false,
      managed_repo_id: nil,
      workspace_path: nil,
      graph: @default_graph,
      memories: empty_lookup(:memories, "unavailable", @default_graph),
      provenance: empty_lookup(:provenance, "unavailable", @default_graph),
      governed_history: %{evidence: [], decisions: []},
      notice: notice,
      notice_kind: :warning,
      recovery: ProductFeedback.recovery(@default_graph)
    }
  end

  defp governed_notice(%{graph: %{state: :ready}}), do: nil

  defp governed_notice(%{graph: graph, error: error}) do
    feedback = ProductFeedback.for_graph(graph, error)

    %{
      error_type: feedback.error_type,
      detail: feedback.detail,
      remediation: feedback.remediation
    }
  end

  defp governed_notice(_status), do: nil

  defp projection_for({:ok, projection}), do: projection
  defp projection_for({:error, _reason, projection}), do: projection

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
