defmodule JidoCode.MemoryGraph.GovernedSurfaceContext do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  @moduledoc """
  Product-owned memory context shaping for governed product surfaces.

  Governed surfaces remain canonical product routes while this boundary loads
  bounded memory and workflow-provenance context for the records already in view.
  """

  alias JidoCode.MemoryGraph.ProductFeedback
  alias JidoCode.MemoryGraph.{GovernedReference, ProductService}
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
        work_item = Keyword.get(opts, :work_item)
        governed_references = run_governed_references(run, work_item, evidence_records, decisions)
        run_route = "/repos/#{managed_repo_id}/runs/#{run.run_id}"

        {memories, provenance} =
          if queryable_graph?(graph) and governed_references != [] do
            {
              navigation_projection(
                ProductService.memories_for_governed_references(
                  managed_repo_id,
                  workspace_path,
                  governed_references,
                  Keyword.put_new(lookup_opts, :limit, 8)
                ),
                managed_repo_id,
                workspace_path,
                run_route,
                lookup_opts
              ),
              navigation_projection(
                ProductService.provenance_for_governed_references(
                  managed_repo_id,
                  workspace_path,
                  governed_references,
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
            work_item: history_summary(work_item, memories.items, provenance.items, :work_item),
            evidence: history_summary(evidence_records, memories.items, provenance.items, :evidence),
            decisions: history_summary(decisions, memories.items, provenance.items, :decision)
          },
          governed_surfaces:
            governed_surfaces(
              managed_repo_id,
              workspace_path,
              graph,
              work_item,
              evidence_records,
              decisions,
              run_route,
              lookup_opts
            ),
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
        workspace_path_from_settings(map_get(scope, :workspace_settings, "workspace_settings")) ||
        workspace_path_from_settings(map_get(scope, :settings, "settings")) ||
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
    |> workspace_path_from_settings()
  end

  defp managed_workspace_path(_managed_repo), do: nil

  defp workspace_path_from_settings(settings) when is_map(settings) do
    normalize_optional_string(map_get(settings, :workspace_path, "workspace_path")) ||
      settings
      |> map_get(:workspace, "workspace", %{})
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_optional_string()
  end

  defp workspace_path_from_settings(_settings), do: nil

  defp run_governed_references(%Run{} = run, work_item, evidence_records, decisions) do
    []
    |> maybe_add_governed_reference(:run, normalize_optional_string(run.run_id))
    |> maybe_add_governed_reference(:work_item, record_id(work_item))
    |> add_governed_references(evidence_records, :evidence)
    |> add_governed_references(decisions, :decision)
    |> Enum.uniq_by(fn reference -> {reference.kind, reference.id} end)
  end

  defp maybe_add_governed_reference(references, _kind, nil), do: references

  defp maybe_add_governed_reference(references, kind, id) do
    references ++ [%{kind: kind, id: id}]
  end

  defp add_governed_references(references, records, kind) when is_list(records) do
    Enum.reduce(records, references, fn record, acc ->
      maybe_add_governed_reference(acc, kind, normalize_optional_string(map_get(record, :id, "id")))
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
                patch_governed_navigation(projection.navigation, managed_repo_id, run_route)

              _other ->
                %{source_code: [], governed_records: [], related_memories: []}
            end

          _other ->
            %{source_code: [], governed_records: [], related_memories: []}
        end

      Map.put(item, :navigation, navigation)
    end)
  end

  defp patch_governed_navigation(navigation, managed_repo_id, run_route)
       when is_map(navigation) and is_binary(managed_repo_id) do
    governed_records =
      Enum.map(Map.get(navigation, :governed_records, []), fn link ->
        case governed_route_from_reference(managed_repo_id, link, run_route) do
          route when is_binary(route) -> Map.put(link, :route, route)
          _other -> link
        end
      end)

    Map.put(navigation, :governed_records, governed_records)
  end

  defp history_summary(nil, _memories, _provenance, :work_item), do: nil

  defp history_summary(record, memories, provenance, :work_item) when is_map(record) do
    record_id = record_id(record)

    %{
      id: record_id,
      kind: :work_item,
      label: history_label(record, :work_item),
      memory_count: related_count(memories, :work_item, record_id),
      provenance_count: related_count(provenance, :work_item, record_id)
    }
  end

  defp history_summary(records, memories, provenance, kind) do
    Enum.map(records, fn record ->
      record_id = record_id(record)

      %{
        id: record_id,
        kind: kind,
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

  defp governed_surfaces(
         managed_repo_id,
         workspace_path,
         graph,
         work_item,
         evidence_records,
         decisions,
         run_route,
         opts
       ) do
    %{
      work_item: governed_surface(work_item, :work_item, managed_repo_id, workspace_path, graph, run_route, opts),
      evidence:
        Enum.map(
          evidence_records,
          &governed_surface(&1, :evidence, managed_repo_id, workspace_path, graph, run_route, opts)
        ),
      decisions:
        Enum.map(decisions, &governed_surface(&1, :decision, managed_repo_id, workspace_path, graph, run_route, opts))
    }
  end

  defp governed_surface(nil, _kind, _managed_repo_id, _workspace_path, _graph, _run_route, _opts), do: nil

  defp governed_surface(record, kind, managed_repo_id, workspace_path, graph, run_route, opts) when is_map(record) do
    record_id = record_id(record)
    governed_references = [%{kind: kind, id: record_id}]
    route = record_id && governed_route(kind, record_id, managed_repo_id, run_route)

    {memories, provenance} =
      if queryable_graph?(graph) and is_binary(record_id) do
        {
          navigation_projection(
            ProductService.memories_for_governed_references(
              managed_repo_id,
              workspace_path,
              governed_references,
              Keyword.put_new(opts, :limit, 4)
            ),
            managed_repo_id,
            workspace_path,
            run_route,
            opts
          ),
          navigation_projection(
            ProductService.provenance_for_governed_references(
              managed_repo_id,
              workspace_path,
              governed_references,
              Keyword.put_new(opts, :limit, 4)
            ),
            managed_repo_id,
            workspace_path,
            run_route,
            opts
          )
        }
      else
        {
          empty_lookup(:memories, managed_repo_id, graph),
          empty_lookup(:provenance, managed_repo_id, graph)
        }
      end

    %{
      kind: kind,
      id: record_id,
      label: history_label(record, kind),
      route: route,
      memories: memories,
      provenance: provenance,
      memory_count: get_in(memories, [:result_group, :count]) || 0,
      provenance_count: get_in(provenance, [:result_group, :count]) || 0
    }
  end

  defp history_label(record, :evidence) do
    normalize_optional_string(map_get(record, :key, "key")) || "Evidence"
  end

  defp history_label(record, :decision) do
    normalize_optional_string(map_get(record, :decision, "decision")) || "Decision"
  end

  defp history_label(record, :work_item) do
    normalize_optional_string(map_get(record, :summary, "summary")) ||
      normalize_optional_string(map_get(record, :recommended_action, "recommended_action")) || "Work item"
  end

  defp governed_route(kind, record_id, managed_repo_id, run_route)
       when is_atom(kind) and is_binary(record_id) and is_binary(managed_repo_id) do
    GovernedReference.route(managed_repo_id, kind, record_id) ||
      governed_anchor_route(kind, record_id, run_route)
  end

  defp governed_route(kind, record_id, _managed_repo_id, run_route)
       when is_atom(kind) and is_binary(record_id),
       do: governed_anchor_route(kind, record_id, run_route)

  defp governed_route(_kind, _record_id, _managed_repo_id, run_route), do: run_route

  defp governed_anchor_route(:work_item, _record_id, run_route), do: run_route <> "#run-detail-work-item"

  defp governed_anchor_route(:evidence, record_id, run_route),
    do: run_route <> "#run-detail-evidence-entry-#{dom_token(record_id)}"

  defp governed_anchor_route(:decision, record_id, run_route),
    do: run_route <> "#run-detail-decision-entry-#{dom_token(record_id)}"

  defp governed_anchor_route(_kind, _record_id, run_route), do: run_route

  defp governed_route_from_reference(managed_repo_id, %{kind: kind, id: id}, run_route)
       when is_binary(managed_repo_id) and is_atom(kind) and is_binary(id),
       do:
         case GovernedReference.route(managed_repo_id, kind, id) do
           route when is_binary(route) -> route
           _other -> governed_anchor_route(kind, id, run_route)
         end

  defp governed_route_from_reference(managed_repo_id, %{kind: :work_item}, run_route)
       when is_binary(managed_repo_id),
       do: run_route <> "#run-detail-work-item"

  defp governed_route_from_reference(_managed_repo_id, _reference, _run_route), do: nil

  defp record_id(record) when is_map(record), do: normalize_optional_string(map_get(record, :id, "id"))
  defp record_id(_record), do: nil

  defp dom_token(value) do
    value
    |> normalize_optional_string()
    |> case do
      nil -> "unknown"
      normalized -> normalized
    end
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
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
      governed_history: %{work_item: nil, evidence: [], decisions: []},
      governed_surfaces: %{work_item: nil, evidence: [], decisions: []},
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
