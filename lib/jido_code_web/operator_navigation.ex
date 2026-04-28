defmodule JidoCodeWeb.OperatorNavigation do
  @moduledoc false

  alias JidoCode.ManagedRepoRoutes

  @repositories_path "/repos"
  @workflows_path "/workflows"
  @agents_path "/agents"
  @settings_path "/settings"

  @spec from_socket(map() | nil) :: map() | nil
  def from_socket(%{view: view, assigns: assigns}) when is_map(assigns), do: from_view(view, assigns)
  def from_socket(_socket), do: nil

  @spec from_view(module(), map()) :: map() | nil
  def from_view(view, assigns \\ %{})

  def from_view(view, assigns) when is_atom(view) and is_map(assigns) do
    if signed_in?(assigns) do
      case route_context(view, assigns) do
        nil ->
          nil

        context ->
          %{
            id: "operator-global-nav",
            label: "Signed-in product navigation",
            route_badge: context.route_badge,
            route_label: context.route_label,
            major_destinations: major_destinations(context.major_destination),
            context_links: context.context_links
          }
      end
    end
  end

  def from_view(_view, _assigns), do: nil

  defp signed_in?(assigns), do: is_map(Map.get(assigns, :current_user))

  defp major_destinations(selected_id) do
    [
      major_destination(
        :dashboard,
        "Dashboard",
        "Signed-in home",
        ManagedRepoRoutes.dashboard_work_overview_path(),
        selected_id
      ),
      major_destination(
        :workbench,
        "Workbench",
        "Dense specialist inventory",
        ManagedRepoRoutes.workbench_path(),
        selected_id
      ),
      major_destination(:repositories, "Repositories", "Managed repo inventory", @repositories_path, selected_id),
      major_destination(:workflows, "Workflows", "Manual governed run kickoff", @workflows_path, selected_id),
      major_destination(:agents, "Agents", "Repo-scoped support automation", @agents_path, selected_id),
      major_destination(:settings, "Settings", "Auth, integrations, and security", @settings_path, selected_id)
    ]
  end

  defp major_destination(id, label, summary, navigate, selected_id) do
    %{
      id: id,
      dom_id: "operator-global-nav-#{id}",
      label: label,
      summary: summary,
      navigate: navigate,
      selected?: id == selected_id
    }
  end

  defp route_context(JidoCodeWeb.DashboardLive, _assigns) do
    %{
      major_destination: :dashboard,
      route_badge: "Authenticated home",
      route_label: "Dashboard",
      context_links: []
    }
  end

  defp route_context(JidoCodeWeb.WorkbenchLive, _assigns) do
    %{
      major_destination: :workbench,
      route_badge: "Specialist inventory",
      route_label: "Workbench",
      context_links: []
    }
  end

  defp route_context(JidoCodeWeb.ProjectInventoryLive, _assigns) do
    %{
      major_destination: :repositories,
      route_badge: "Managed repo inventory",
      route_label: "Repositories",
      context_links: []
    }
  end

  defp route_context(JidoCodeWeb.WorkflowsLive, _assigns) do
    %{
      major_destination: :workflows,
      route_badge: "Governed launch",
      route_label: "Workflows",
      context_links: []
    }
  end

  defp route_context(JidoCodeWeb.AgentsLive, _assigns) do
    %{
      major_destination: :agents,
      route_badge: "Support automation",
      route_label: "Agents",
      context_links: []
    }
  end

  defp route_context(JidoCodeWeb.SettingsLive, assigns) do
    active_tab = Map.get(assigns, :active_tab) || "github"

    %{
      major_destination: :settings,
      route_badge: "Operator configuration",
      route_label: "Settings",
      context_links: [
        %{
          id: "operator-context-settings-tab",
          label: settings_tab_label(active_tab),
          current?: true
        }
      ]
    }
  end

  defp route_context(JidoCodeWeb.ProjectDetailLive, assigns) do
    return_to_path = Map.get(assigns, :return_to_path) || @repositories_path
    repo_label = repo_label(assigns)

    %{
      major_destination: major_destination_for_path(return_to_path, :repositories),
      route_badge: "Managed repo",
      route_label: repo_label,
      context_links: [
        %{
          id: "operator-context-repo",
          label: repo_label,
          current?: true
        }
      ]
    }
  end

  defp route_context(JidoCodeWeb.RunDetailLive, assigns) do
    project_id = Map.get(assigns, :project_id)
    return_to_path = Map.get(assigns, :return_to_path)
    broad_parent_path = ManagedRepoRoutes.repo_detail_parent_return_to(return_to_path, @repositories_path)

    repo_link =
      case normalize_string(project_id) do
        nil ->
          nil

        normalized_project_id ->
          %{
            id: "operator-context-repo",
            label: "Repo #{normalized_project_id}",
            navigate:
              ManagedRepoRoutes.project_detail_path(
                normalized_project_id,
                return_to: broad_parent_path
              )
          }
      end

    %{
      major_destination: major_destination_for_path(broad_parent_path, :repositories),
      route_badge: "Governed run",
      route_label: run_label(assigns),
      context_links:
        Enum.reject(
          [
            repo_link,
            %{
              id: "operator-context-run",
              label: run_label(assigns),
              current?: true
            }
          ],
          &is_nil/1
        )
    }
  end

  defp route_context(JidoCodeWeb.WorkItemDetailLive, assigns) do
    repo_link = governed_repo_link(assigns)

    %{
      major_destination: :repositories,
      route_badge: "Governed work item",
      route_label: "Work item detail",
      context_links:
        Enum.reject(
          [
            repo_link,
            %{id: "operator-context-work-item", label: "Work item detail", current?: true}
          ],
          &is_nil/1
        )
    }
  end

  defp route_context(JidoCodeWeb.EvidenceDetailLive, assigns) do
    repo_link = governed_repo_link(assigns)

    %{
      major_destination: :repositories,
      route_badge: "Governed evidence",
      route_label: "Evidence detail",
      context_links:
        Enum.reject(
          [
            repo_link,
            %{id: "operator-context-evidence", label: "Evidence detail", current?: true}
          ],
          &is_nil/1
        )
    }
  end

  defp route_context(JidoCodeWeb.DecisionDetailLive, assigns) do
    repo_link = governed_repo_link(assigns)

    %{
      major_destination: :repositories,
      route_badge: "Governed decision",
      route_label: "Decision detail",
      context_links:
        Enum.reject(
          [
            repo_link,
            %{id: "operator-context-decision", label: "Decision detail", current?: true}
          ],
          &is_nil/1
        )
    }
  end

  defp route_context(_view, _assigns), do: nil

  defp governed_repo_link(assigns) do
    case normalize_string(Map.get(assigns, :project_id)) do
      nil ->
        nil

      project_id ->
        %{
          id: "operator-context-repo",
          label: "Repo #{project_id}",
          navigate: ManagedRepoRoutes.project_detail_path(project_id, return_to: @repositories_path)
        }
    end
  end

  defp repo_label(assigns) do
    assigns
    |> Map.get(:project_detail)
    |> case do
      %{} = project_detail ->
        normalize_string(Map.get(project_detail, :github_full_name) || Map.get(project_detail, "github_full_name")) ||
          normalize_string(Map.get(project_detail, :id) || Map.get(project_detail, "id"))

      _other ->
        nil
    end || "Managed repo detail"
  end

  defp run_label(assigns) do
    assigns
    |> Map.get(:run_id)
    |> normalize_string()
    |> case do
      nil -> "Run detail"
      run_id -> "Run #{run_id}"
    end
  end

  defp settings_tab_label("github"), do: "GitHub settings"
  defp settings_tab_label("agents"), do: "Agent settings"
  defp settings_tab_label("account"), do: "Account settings"
  defp settings_tab_label("auth"), do: "Auth & Integrations"
  defp settings_tab_label("security"), do: "Security settings"
  defp settings_tab_label(_tab), do: "Settings"

  defp major_destination_for_path(path, fallback) do
    case normalize_string(path) do
      nil -> fallback
      normalized_path -> match_destination_from_path(normalized_path) || fallback
    end
  end

  defp match_destination_from_path("/dashboard" <> _suffix), do: :dashboard
  defp match_destination_from_path("/workbench" <> _suffix), do: :workbench
  defp match_destination_from_path("/workflows" <> _suffix), do: :workflows
  defp match_destination_from_path("/agents" <> _suffix), do: :agents
  defp match_destination_from_path("/settings" <> _suffix), do: :settings
  defp match_destination_from_path("/repos" <> _suffix), do: :repositories
  defp match_destination_from_path(_path), do: nil

  defp normalize_string(nil), do: nil

  defp normalize_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_string()
  defp normalize_string(_value), do: nil
end
