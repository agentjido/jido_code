defmodule JidoCode.Workbench.ProjectMemoryInspection do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  @moduledoc """
  Product-owned memory inspection shaping for managed-repository operator surfaces.

  This boundary keeps LiveViews repo-first while hiding raw SPARQL and graph
  internals behind bounded memory and provenance projections.
  """

  alias JidoCode.MemoryGraph.{ProductFeedback, ProductService, SurfaceFeedback}
  alias JidoCode.Workbench.ProjectDetail

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

  @default_notice_kind :warning

  @type notice :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t() | nil
        }

  @type recovery :: %{
          action: atom(),
          available?: boolean(),
          label: String.t() | nil
        }

  @type inspection :: %{
          available?: boolean(),
          managed_repo_id: String.t() | nil,
          workspace_path: String.t() | nil,
          graph: map(),
          summary: map(),
          memories: map(),
          provenance: map(),
          notice: notice() | nil,
          notice_kind: atom(),
          recovery: recovery()
        }

  @spec load_repo_detail(map() | nil, keyword()) :: inspection()
  def load_repo_detail(project_like, opts \\ []) do
    case scope(project_like) do
      {:ok, managed_repo_id, workspace_path} ->
        status = projection_for(ProductService.status(managed_repo_id, workspace_path, opts))
        graph = Map.get(status, :graph, @default_graph)

        lookup_opts = Keyword.put_new(opts, :allow_stale?, true)

        {summary, memories, provenance} =
          if queryable_graph?(graph) do
            {
              projection_for(ProductService.summary(managed_repo_id, workspace_path, lookup_opts)),
              navigation_projection(
                ProductService.memories(managed_repo_id, workspace_path, Keyword.put_new(lookup_opts, :limit, 6)),
                managed_repo_id,
                workspace_path,
                lookup_opts
              ),
              navigation_projection(
                ProductService.provenance(managed_repo_id, workspace_path, Keyword.put_new(lookup_opts, :limit, 6)),
                managed_repo_id,
                workspace_path,
                lookup_opts
              )
            }
          else
            {
              empty_summary(managed_repo_id, graph),
              empty_lookup(:memories, managed_repo_id, graph),
              empty_lookup(:provenance, managed_repo_id, graph)
            }
          end

        %{
          available?: true,
          managed_repo_id: managed_repo_id,
          workspace_path: workspace_path,
          graph: graph,
          summary: summary,
          memories: memories,
          provenance: provenance,
          notice: memory_notice(status),
          notice_kind: ProductFeedback.notice_kind(graph),
          recovery: ProductFeedback.recovery(graph)
        }

      {:error, notice} ->
        unavailable_inspection(notice)
    end
  end

  @spec status_hint(map() | nil, keyword()) :: map() | nil
  def status_hint(project_like, opts \\ []) do
    case scope(project_like) do
      {:ok, managed_repo_id, workspace_path} ->
        status = projection_for(ProductService.status(managed_repo_id, workspace_path, opts))
        graph = Map.get(status, :graph, @default_graph)

        %{
          managed_repo_id: managed_repo_id,
          state: Map.get(graph, :state, :unavailable),
          label: ProductFeedback.state_label(graph),
          detail: hint_detail(status),
          remediation: hint_remediation(graph),
          recovery: ProductFeedback.recovery(graph)
        }

      {:error, _notice} ->
        nil
    end
  end

  @spec recover(map() | nil, keyword()) ::
          {:ok, %{inspection: inspection(), feedback: notice()}}
          | {:error, %{inspection: inspection(), feedback: notice()}}
  def recover(project_like, opts \\ []) do
    case scope(project_like) do
      {:ok, managed_repo_id, workspace_path} ->
        result = ProductService.recover(managed_repo_id, workspace_path, opts)
        inspection = load_repo_detail(project_like, opts)

        case result do
          {:ok, recovery_projection} ->
            {:ok,
             %{
               inspection: inspection,
               feedback: recovery_feedback(recovery_projection)
             }}

          {:error, reason, diagnostics} ->
            {:error,
             %{
               inspection: inspection,
               feedback: recovery_error_feedback(reason, diagnostics, inspection.graph)
             }}
        end

      {:error, notice} ->
        inspection = unavailable_inspection(notice)
        {:error, %{inspection: inspection, feedback: notice}}
    end
  end

  defp scope(project_like) when is_map(project_like) do
    managed_repo_id =
      project_like
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    workspace_path =
      project_like
      |> ProjectDetail.workspace_path()
      |> normalize_optional_string() ||
        project_like
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_optional_string()

    cond do
      is_nil(managed_repo_id) ->
        {:error,
         %{
           error_type: "memory_repo_scope_unavailable",
           detail: "Memory inspection needs a managed repository identifier.",
           remediation: "Reopen this repository from a managed-repo route and retry memory inspection."
         }}

      is_nil(workspace_path) ->
        {:error,
         %{
           error_type: "memory_workspace_binding_unavailable",
           detail:
             "Memory inspection needs the managed repository's repo-scoped local workspace binding before it can load memory graph state.",
           remediation:
             "Bind this repository to its own local workspace path and then retry memory inspection."
         }}

      true ->
        {:ok, managed_repo_id, workspace_path}
    end
  end

  defp scope(_project_like), do: {:error, unavailable_notice()}

  defp projection_for({:ok, projection}), do: projection
  defp projection_for({:error, _reason, projection}), do: projection

  defp navigation_projection({:ok, projection}, managed_repo_id, workspace_path, opts) do
    Map.put(
      projection,
      :items,
      attach_navigation(Map.get(projection, :items, []), managed_repo_id, workspace_path, opts)
    )
  end

  defp navigation_projection({:error, _reason, projection}, managed_repo_id, workspace_path, opts) do
    Map.put(
      projection,
      :items,
      attach_navigation(Map.get(projection, :items, []), managed_repo_id, workspace_path, opts)
    )
  end

  defp attach_navigation(items, managed_repo_id, workspace_path, opts) when is_list(items) do
    Enum.map(items, fn item ->
      resource_iri = Map.get(item, :memory_iri) || Map.get(item, :resource_iri)

      navigation =
        case resource_iri do
          resource_iri when is_binary(resource_iri) ->
            case ProductService.cross_links(managed_repo_id, workspace_path, resource_iri, opts) do
              {:ok, projection} -> projection.navigation
              _other -> %{source_code: [], governed_records: [], related_memories: []}
            end

          _other ->
            %{source_code: [], governed_records: [], related_memories: []}
        end

      Map.put(item, :navigation, navigation)
    end)
  end

  defp empty_summary(managed_repo_id, graph) do
    %{
      kind: :memory_graph_summary,
      managed_repo_id: managed_repo_id,
      graph: graph,
      feedback: ProductFeedback.for_graph(graph),
      groups: %{
        memories: %{status: :unavailable, count: 0, items: []},
        provenance: %{status: :unavailable, count: 0, items: []}
      },
      error: nil
    }
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

  defp queryable_graph?(graph) when is_map(graph) do
    Map.get(graph, :ready?, false) or (Map.get(graph, :stale?, false) and Map.get(graph, :queryable_when_stale?, false))
  end

  defp unavailable_inspection(notice) do
    %{
      available?: false,
      managed_repo_id: nil,
      workspace_path: nil,
      graph: @default_graph,
      summary: empty_summary("unavailable", @default_graph),
      memories: empty_lookup(:memories, "unavailable", @default_graph),
      provenance: empty_lookup(:provenance, "unavailable", @default_graph),
      notice: notice,
      notice_kind: @default_notice_kind,
      recovery: ProductFeedback.recovery(@default_graph)
    }
  end

  defp unavailable_notice do
    %{
      error_type: "memory_repo_scope_unavailable",
      detail: "Memory inspection is unavailable for this repository context.",
      remediation: "Open a managed repository route with a provisioned workspace and retry."
    }
  end

  defp memory_notice(%{graph: %{state: :ready}}), do: nil

  defp memory_notice(%{graph: graph, error: error}) do
    feedback = ProductFeedback.for_graph(graph, error)

    %{
      error_type: feedback.error_type,
      detail: feedback.detail,
      remediation: feedback.remediation
    }
  end

  defp memory_notice(_status), do: nil

  defp hint_detail(%{graph: graph, error: error}), do: ProductFeedback.for_graph(graph, error).detail
  defp hint_detail(_status), do: "Repository memory state is unavailable."

  defp hint_remediation(graph) do
    case ProductFeedback.recovery(graph) do
      %{available?: true, label: label} when is_binary(label) ->
        "Open repo detail to review governed memory context and #{String.downcase(label)}."

      _other ->
        ProductFeedback.for_graph(graph).remediation
    end
  end

  defp recovery_feedback(%{graph: graph}) do
    SurfaceFeedback.recovery_result(graph, surface_label: "this managed repository surface")
  end

  defp recovery_error_feedback(reason, diagnostics, graph) do
    SurfaceFeedback.recovery_error(
      reason,
      diagnostics,
      graph: graph,
      surface_label: "this managed repository surface"
    )
  end

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
