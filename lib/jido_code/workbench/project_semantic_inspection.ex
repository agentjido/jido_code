defmodule JidoCode.Workbench.ProjectSemanticInspection do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  @moduledoc """
  Product-owned semantic inspection shaping for managed-repository operator surfaces.

  This boundary keeps LiveViews and widgets repo-first while hiding raw SPARQL,
  pod topology, and store internals behind bounded product projections.
  """

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.ProductService

  @default_graph %{
    graph_name: "source_code",
    ready?: false,
    stale?: false,
    degraded?: false,
    state: :unavailable,
    imported_revision: nil,
    current_revision: nil,
    latest_failure: nil,
    recovery_action: :none
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
          modules: map(),
          functions: map(),
          runtime_patterns: map(),
          impact: map(),
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

        {summary, modules, functions, runtime_patterns, impact} =
          if queryable_graph?(graph) do
            lookup_opts = Keyword.put_new(opts, :allow_stale?, true)

            {
              projection_for(ProductService.summary(managed_repo_id, workspace_path, lookup_opts)),
              projection_for(
                ProductService.modules(
                  managed_repo_id,
                  workspace_path,
                  Keyword.put_new(lookup_opts, :limit, 8)
                )
              ),
              projection_for(
                ProductService.functions(
                  managed_repo_id,
                  workspace_path,
                  Keyword.put_new(lookup_opts, :limit, 8)
                )
              ),
              projection_for(
                ProductService.runtime_patterns(
                  managed_repo_id,
                  workspace_path,
                  Keyword.put_new(lookup_opts, :limit, 6)
                )
              ),
              projection_for(
                ProductService.impact(
                  managed_repo_id,
                  workspace_path,
                  Keyword.put_new(lookup_opts, :limit, 6)
                )
              )
            }
          else
            {
              empty_summary(managed_repo_id, graph),
              empty_lookup(:modules, managed_repo_id, graph),
              empty_lookup(:functions, managed_repo_id, graph),
              empty_lookup(:runtime_patterns, managed_repo_id, graph),
              empty_lookup(:impact, managed_repo_id, graph)
            }
          end

        %{
          available?: true,
          managed_repo_id: managed_repo_id,
          workspace_path: workspace_path,
          graph: graph,
          summary: summary,
          modules: modules,
          functions: functions,
          runtime_patterns: runtime_patterns,
          impact: impact,
          notice: semantic_notice(status),
          notice_kind: semantic_notice_kind(graph),
          recovery: recovery(graph)
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
          label: graph_state_label(graph),
          detail: hint_detail(status),
          remediation: hint_remediation(graph),
          recovery: recovery(graph)
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
        result = AgentWorkspace.recover_source_code_graph(managed_repo_id, workspace_path, opts)
        inspection = load_repo_detail(project_like, opts)

        case result do
          {:ok, recovery_result} ->
            {:ok,
             %{
               inspection: inspection,
               feedback: recovery_feedback(recovery_result)
             }}

          {:error, reason, diagnostics} ->
            {:error,
             %{
               inspection: inspection,
               feedback: recovery_error_feedback(reason, diagnostics)
             }}

          {:error, reason} ->
            {:error,
             %{
               inspection: inspection,
               feedback: recovery_error_feedback(reason, %{})
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
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_optional_string() ||
        project_like
        |> map_get(:settings, "settings", %{})
        |> map_get(:workspace, "workspace", %{})
        |> map_get(:workspace_path, "workspace_path")
        |> normalize_optional_string()

    cond do
      is_nil(managed_repo_id) ->
        {:error,
         %{
           error_type: "semantic_repo_scope_unavailable",
           detail: "Semantic inspection needs a managed repository identifier.",
           remediation: "Reopen this repository from a managed-repo route and retry semantic inspection."
         }}

      is_nil(workspace_path) ->
        {:error,
         %{
           error_type: "semantic_workspace_unavailable",
           detail: "Semantic inspection needs a repository workspace path before it can load semantic graph state.",
           remediation: "Complete workspace import for this managed repository and then retry semantic inspection."
         }}

      true ->
        {:ok, managed_repo_id, workspace_path}
    end
  end

  defp scope(_project_like), do: {:error, unavailable_notice()}

  defp projection_for({:ok, projection}), do: projection
  defp projection_for({:error, _reason, projection}), do: projection

  defp empty_summary(managed_repo_id, graph) do
    %{
      kind: :semantic_summary,
      managed_repo_id: managed_repo_id,
      graph: graph,
      groups: %{
        modules: %{status: :unavailable, count: 0, items: []},
        runtime_patterns: %{status: :unavailable, count: 0, items: []}
      },
      error: nil
    }
  end

  defp empty_lookup(kind, managed_repo_id, graph) do
    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: graph,
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
    Map.get(graph, :ready?, false) or Map.get(graph, :stale?, false)
  end

  defp unavailable_inspection(notice) do
    %{
      available?: false,
      managed_repo_id: nil,
      workspace_path: nil,
      graph: @default_graph,
      summary: empty_summary("unavailable", @default_graph),
      modules: empty_lookup(:modules, "unavailable", @default_graph),
      functions: empty_lookup(:functions, "unavailable", @default_graph),
      runtime_patterns: empty_lookup(:runtime_patterns, "unavailable", @default_graph),
      impact: empty_lookup(:impact, "unavailable", @default_graph),
      notice: notice,
      notice_kind: @default_notice_kind,
      recovery: recovery(@default_graph)
    }
  end

  defp unavailable_notice do
    %{
      error_type: "semantic_repo_scope_unavailable",
      detail: "Semantic inspection is unavailable for this repository context.",
      remediation: "Open a managed repository route with a provisioned workspace and retry."
    }
  end

  defp semantic_notice(%{graph: %{state: :ready}}), do: nil

  defp semantic_notice(%{graph: graph, error: error}) do
    error_type =
      error_type(error) ||
        graph
        |> Map.get(:latest_failure)
        |> map_get(:kind, "kind")
        |> normalize_optional_string() ||
        graph_error_type(graph)

    %{
      error_type: error_type,
      detail: semantic_detail(graph, error),
      remediation: hint_remediation(graph)
    }
  end

  defp semantic_notice(_status), do: nil

  defp semantic_notice_kind(%{state: :failed}), do: :error
  defp semantic_notice_kind(_graph), do: @default_notice_kind

  defp hint_detail(%{graph: graph, error: error}), do: semantic_detail(graph, error)
  defp hint_detail(_status), do: "Semantic repository state is unavailable."

  defp semantic_detail(%{state: :stale}, %{detail: detail}) when is_binary(detail), do: detail

  defp semantic_detail(%{state: :failed, latest_failure: %{message: message}}, _error) when is_binary(message),
    do: message

  defp semantic_detail(%{state: :disabled}, _error),
    do: "Semantic source-code graph capability is disabled for this repository."

  defp semantic_detail(%{state: :not_ready}, _error), do: "Semantic source-code graph data has not been loaded yet."

  defp semantic_detail(%{state: :stale}, _error),
    do: "Semantic source-code graph data is stale and should be refreshed."

  defp semantic_detail(%{state: :degraded}, _error),
    do: "Semantic source-code graph data is available in degraded mode while the repository revision is stale."

  defp semantic_detail(%{state: :failed}, _error), do: "Semantic source-code graph refresh failed and needs recovery."

  defp semantic_detail(%{state: :unavailable}, _error),
    do: "Semantic inspection is unavailable for this managed repository."

  defp semantic_detail(_graph, %{detail: detail}) when is_binary(detail), do: detail
  defp semantic_detail(_graph, _error), do: "Semantic repository state is unavailable."

  defp hint_remediation(%{recovery_action: :none}), do: nil
  defp hint_remediation(%{recovery_action: :load}), do: "Open repo detail to load semantic graph data."
  defp hint_remediation(%{recovery_action: :refresh}), do: "Open repo detail to refresh semantic graph data."
  defp hint_remediation(%{recovery_action: :recover}), do: "Open repo detail to recover semantic graph state."
  defp hint_remediation(_graph), do: nil

  defp recovery(graph) do
    action = Map.get(graph, :recovery_action, :none)

    %{
      action: action,
      available?: action != :none,
      label: recovery_label(action)
    }
  end

  defp graph_state_label(%{state: :ready}), do: "Semantic graph ready"
  defp graph_state_label(%{state: :not_ready}), do: "Semantic graph not loaded"
  defp graph_state_label(%{state: :stale}), do: "Semantic graph stale"
  defp graph_state_label(%{state: :degraded}), do: "Semantic graph degraded"
  defp graph_state_label(%{state: :failed}), do: "Semantic graph failed"
  defp graph_state_label(%{state: :disabled}), do: "Semantic graph disabled"
  defp graph_state_label(_graph), do: "Semantic graph unavailable"

  defp recovery_label(:load), do: "Load semantic graph"
  defp recovery_label(:refresh), do: "Refresh semantic graph"
  defp recovery_label(:recover), do: "Recover semantic graph"
  defp recovery_label(:none), do: nil
  defp recovery_label(_action), do: "Recover semantic graph"

  defp graph_error_type(%{state: :disabled}), do: "source_code_graph_disabled"
  defp graph_error_type(%{state: :not_ready}), do: "source_code_graph_not_ready"
  defp graph_error_type(%{state: :stale}), do: "source_code_graph_stale"
  defp graph_error_type(%{state: :degraded}), do: "source_code_graph_degraded"
  defp graph_error_type(%{state: :failed}), do: "source_code_graph_failed"
  defp graph_error_type(_graph), do: "source_code_graph_unavailable"

  defp recovery_feedback(%{status: :source_code_graph_recovery_not_needed}) do
    %{
      error_type: "semantic_graph_up_to_date",
      detail: "Semantic source-code graph is already ready for inspection.",
      remediation: nil
    }
  end

  defp recovery_feedback(%{recovery_action: action}) do
    %{
      error_type: "semantic_graph_recovered",
      detail: "#{recovery_label(action)} completed successfully.",
      remediation: nil
    }
  end

  defp recovery_feedback(_result) do
    %{
      error_type: "semantic_graph_recovered",
      detail: "Semantic source-code graph recovery completed successfully.",
      remediation: nil
    }
  end

  defp recovery_error_feedback(reason, diagnostics) do
    %{
      error_type: normalize_optional_string(reason) || "semantic_graph_recovery_failed",
      detail: recovery_error_detail(reason, diagnostics),
      remediation: "Review repo detail semantic status and retry recovery when repository graph inputs are available."
    }
  end

  defp recovery_error_detail(_reason, diagnostics) when is_map(diagnostics) do
    map_get(diagnostics, :message, "message") ||
      map_get(diagnostics, :reason, "reason") ||
      inspect(diagnostics)
  end

  defp recovery_error_detail(reason, _diagnostics) do
    "Semantic source-code graph recovery failed (#{reason})."
  end

  defp error_type(%{type: type}), do: normalize_optional_string(type)
  defp error_type(%{"type" => type}), do: normalize_optional_string(type)
  defp error_type(_error), do: nil

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
