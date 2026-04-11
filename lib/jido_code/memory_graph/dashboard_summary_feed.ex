defmodule JidoCode.MemoryGraph.DashboardSummaryFeed do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_memory_summaries_remain_bounded_and_action_oriented
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  @moduledoc """
  Loads bounded repository memory summaries for dashboard visibility.

  Dashboard callers get action-oriented freshness and recovery signals without
  taking ownership of raw graph inspection or low-level query behavior.
  """

  alias JidoCode.MemoryGraph.ProductFeedback
  alias JidoCode.MemoryGraph.ProductService
  alias JidoCode.Workbench.Inventory

  @default_fetch_error_type "dashboard_memory_summary_feed_fetch_failed"

  @default_fetch_remediation """
  Retry dashboard memory refresh. If this persists, inspect repository memory recovery from the managed-repository route.
  """

  @type stale_warning :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type memory_summary :: %{
          id: String.t(),
          route_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          repo_label: String.t(),
          state: atom(),
          label: String.t(),
          detail: String.t(),
          remediation: String.t() | nil,
          memory_count: non_neg_integer(),
          provenance_count: non_neg_integer(),
          route: String.t() | nil,
          action_label: String.t() | nil,
          action_needed?: boolean(),
          recovery_available?: boolean(),
          latest_revision: String.t() | nil
        }

  @spec load() :: {:ok, [memory_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def load do
    loader =
      Application.get_env(:jido_code, :dashboard_memory_summary_loader, &__MODULE__.default_loader/0)

    if is_function(loader, 0) do
      safe_invoke_loader(loader)
    else
      {:error,
       stale_warning(
         "dashboard_memory_summary_loader_invalid",
         "Dashboard memory summary loader is invalid.",
         @default_fetch_remediation
       )}
    end
  end

  @doc false
  @spec default_loader() :: {:ok, [memory_summary()], stale_warning() | nil} | {:error, stale_warning()}
  def default_loader do
    case Inventory.load() do
      {:ok, rows, warning} ->
        {:ok, Enum.map(rows, &to_memory_summary/1), normalize_warning(warning)}

      {:error, warning} ->
        {:error,
         normalize_warning(warning) ||
           stale_warning(
             @default_fetch_error_type,
             "Dashboard memory summary data may be stale.",
             @default_fetch_remediation
           )}
    end
  end

  defp safe_invoke_loader(loader) do
    try do
      case loader.() do
        {:ok, summaries, warning} when is_list(summaries) ->
          {:ok, Enum.map(summaries, &normalize_summary/1), normalize_warning(warning)}

        {:error, warning} ->
          {:error,
           normalize_warning(warning) ||
             stale_warning(
               @default_fetch_error_type,
               "Dashboard memory summary data may be stale.",
               @default_fetch_remediation
             )}

        other ->
          {:error,
           stale_warning(
             @default_fetch_error_type,
             "Dashboard memory summary loader returned an invalid result (#{inspect(other)}).",
             @default_fetch_remediation
           )}
      end
    rescue
      exception ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard memory summary loader crashed (#{Exception.message(exception)}).",
           @default_fetch_remediation
         )}
    catch
      kind, reason ->
        {:error,
         stale_warning(
           @default_fetch_error_type,
           "Dashboard memory summary loader threw #{inspect({kind, reason})}.",
           @default_fetch_remediation
         )}
    end
  end

  defp to_memory_summary(row) do
    managed_repo_id =
      row
      |> map_get(:managed_repo_id, "managed_repo_id")
      |> normalize_optional_string()

    workspace_path =
      row
      |> map_get(:workspace_path, "workspace_path")
      |> normalize_optional_string()

    route_id =
      row
      |> map_get(:id, "id")
      |> normalize_optional_string()

    repo_label =
      row
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string() ||
        row
        |> map_get(:name, "name")
        |> normalize_optional_string() || "Unknown repository"

    hint =
      row
      |> map_get(:memory_graph_hint, "memory_graph_hint", %{})
      |> normalize_map()

    summary_projection = summary_projection(managed_repo_id, workspace_path)
    graph = graph_state(hint, summary_projection)
    groups = Map.get(summary_projection, :groups, %{})
    feedback = ProductFeedback.for_graph(graph)
    recovery = Map.get(hint, "recovery") || Map.get(hint, :recovery) || feedback.recovery || %{}

    state = normalize_state(Map.get(hint, "state") || Map.get(hint, :state) || Map.get(graph, :state))
    label = normalize_optional_string(Map.get(hint, "label") || Map.get(hint, :label)) || feedback.label

    detail =
      normalize_optional_string(Map.get(hint, "detail") || Map.get(hint, :detail)) || feedback.detail

    remediation =
      normalize_optional_string(Map.get(hint, "remediation") || Map.get(hint, :remediation)) || feedback.remediation

    memory_count =
      groups
      |> Map.get(:memories, %{})
      |> Map.get(:count, 0)
      |> normalize_count()

    provenance_count =
      groups
      |> Map.get(:provenance, %{})
      |> Map.get(:count, 0)
      |> normalize_count()

    route = route_id && "/repos/#{route_id}#project-detail-memory-inspection"
    recovery_available? = truthy?(Map.get(recovery, "available?") || Map.get(recovery, :available?))

    %{
      id: "dashboard-memory-summary-#{route_id || managed_repo_id || repo_label}",
      route_id: route_id,
      managed_repo_id: managed_repo_id,
      repo_label: repo_label,
      state: state,
      label: label || ProductFeedback.state_label(graph),
      detail: detail || "Repository memory state is unavailable.",
      remediation: remediation,
      memory_count: memory_count,
      provenance_count: provenance_count,
      route: route,
      action_label:
        action_label(
          normalize_optional_string(Map.get(recovery, "label") || Map.get(recovery, :label)),
          route
        ),
      action_needed?: action_needed?(state, recovery_available?, memory_count, provenance_count),
      recovery_available?: recovery_available?,
      latest_revision:
        normalize_optional_string(Map.get(graph, :validated_revision) || Map.get(graph, :current_revision))
    }
  end

  defp normalize_summary(summary) when is_map(summary) do
    state = normalize_state(map_get(summary, :state, "state"))
    route = normalize_optional_string(map_get(summary, :route, "route"))

    %{
      id:
        normalize_optional_string(map_get(summary, :id, "id")) ||
          "dashboard-memory-summary-#{normalize_optional_string(map_get(summary, :route_id, "route_id")) || System.unique_integer([:positive])}",
      route_id: normalize_optional_string(map_get(summary, :route_id, "route_id")),
      managed_repo_id: normalize_optional_string(map_get(summary, :managed_repo_id, "managed_repo_id")),
      repo_label: normalize_optional_string(map_get(summary, :repo_label, "repo_label")) || "Unknown repository",
      state: state,
      label: normalize_optional_string(map_get(summary, :label, "label")) || state_label(state),
      detail:
        normalize_optional_string(map_get(summary, :detail, "detail")) ||
          "Repository memory state is unavailable.",
      remediation: normalize_optional_string(map_get(summary, :remediation, "remediation")),
      memory_count: normalize_count(map_get(summary, :memory_count, "memory_count", 0)),
      provenance_count: normalize_count(map_get(summary, :provenance_count, "provenance_count", 0)),
      route: route,
      action_label:
        normalize_optional_string(map_get(summary, :action_label, "action_label")) || action_label(nil, route),
      action_needed?:
        truthy?(map_get(summary, :action_needed?, "action_needed?")) ||
          truthy?(map_get(summary, :action_needed, "action_needed")),
      recovery_available?:
        truthy?(map_get(summary, :recovery_available?, "recovery_available?")) ||
          truthy?(map_get(summary, :recovery_available, "recovery_available")),
      latest_revision: normalize_optional_string(map_get(summary, :latest_revision, "latest_revision"))
    }
  end

  defp normalize_summary(_summary) do
    %{
      id: "dashboard-memory-summary-unknown",
      route_id: nil,
      managed_repo_id: nil,
      repo_label: "Unknown repository",
      state: :unavailable,
      label: state_label(:unavailable),
      detail: "Repository memory state is unavailable.",
      remediation: nil,
      memory_count: 0,
      provenance_count: 0,
      route: nil,
      action_label: nil,
      action_needed?: false,
      recovery_available?: false,
      latest_revision: nil
    }
  end

  defp summary_projection(managed_repo_id, workspace_path)
       when is_binary(managed_repo_id) and is_binary(workspace_path) do
    case ProductService.summary(managed_repo_id, workspace_path, allow_stale?: true) do
      {:ok, projection} -> projection
      {:error, _reason, projection} -> projection
    end
  end

  defp summary_projection(_managed_repo_id, _workspace_path), do: %{}

  defp graph_state(hint, summary_projection) do
    projection_graph = Map.get(summary_projection, :graph, %{})

    %{
      state: normalize_state(Map.get(hint, "state") || Map.get(hint, :state) || Map.get(projection_graph, :state)),
      ready?: truthy?(Map.get(projection_graph, :ready?)),
      stale?: truthy?(Map.get(projection_graph, :stale?)),
      degraded?: truthy?(Map.get(projection_graph, :degraded?)),
      validated_revision: Map.get(projection_graph, :validated_revision),
      current_revision: Map.get(projection_graph, :current_revision),
      recovery_action: Map.get(projection_graph, :recovery_action),
      latest_failure: Map.get(projection_graph, :latest_failure),
      cross_graph: Map.get(projection_graph, :cross_graph)
    }
  end

  defp action_label(nil, route) when is_binary(route), do: "Open memory detail"
  defp action_label(label, _route) when is_binary(label), do: label
  defp action_label(_label, _route), do: nil

  defp action_needed?(state, recovery_available?, memory_count, provenance_count) do
    recovery_available? or state in [:not_ready, :stale, :invalidated, :degraded, :failed] or
      memory_count > 0 or provenance_count > 0
  end

  defp normalize_warning(nil), do: nil

  defp normalize_warning(warning) do
    stale_warning(
      map_get(warning, :error_type, "error_type", @default_fetch_error_type),
      map_get(warning, :detail, "detail", "Dashboard memory summary data may be stale."),
      map_get(warning, :remediation, "remediation", @default_fetch_remediation)
    )
  end

  defp stale_warning(error_type, detail, remediation) do
    %{
      error_type: error_type,
      detail: detail,
      remediation: remediation
    }
  end

  defp state_label(:ready), do: "Memory graph ready"
  defp state_label(:not_ready), do: "Memory graph not ready"
  defp state_label(:invalidated), do: "Memory graph invalidated"
  defp state_label(:stale), do: "Memory graph stale"
  defp state_label(:degraded), do: "Memory graph degraded"
  defp state_label(:failed), do: "Memory graph failed"
  defp state_label(:disabled), do: "Memory graph disabled"
  defp state_label(_state), do: "Memory graph unavailable"

  defp normalize_state(value) when value in [:ready, :not_ready, :invalidated, :stale, :degraded, :failed, :disabled],
    do: value

  defp normalize_state(value) when is_binary(value) do
    case String.trim(value) do
      "ready" -> :ready
      "not_ready" -> :not_ready
      "invalidated" -> :invalidated
      "stale" -> :stale
      "degraded" -> :degraded
      "failed" -> :failed
      "disabled" -> :disabled
      _other -> :unavailable
    end
  end

  defp normalize_state(_value), do: :unavailable

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

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(map) when is_map(map), do: map
  defp normalize_map(_map), do: %{}

  defp truthy?(value), do: value in [true, "true", 1, "1"]

  defp normalize_count(value) when is_integer(value) and value >= 0, do: value

  defp normalize_count(value) when is_binary(value) do
    case Integer.parse(value) do
      {count, ""} when count >= 0 -> count
      _other -> 0
    end
  end

  defp normalize_count(_value), do: 0
end
