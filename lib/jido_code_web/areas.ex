defmodule JidoCodeWeb.Areas do
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  # covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  @moduledoc """
  Target product-area contract for the UI reset shell.

  The values here describe the destination area model and the route ownership
  boundary that lets existing product LiveViews become area-owned surfaces while
  the reset shell replaces legacy navigation and old route-local chrome.
  """

  @areas [
    %{
      area: :dashboard,
      id: "dashboard",
      handoff_id: "dashboard",
      label: "Dashboard",
      path: "/dashboard",
      local_context_key: :dashboard_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.DashboardLive,
      route_action: :index,
      summary: "Operational home and next actions"
    },
    %{
      area: :repositories,
      id: "repositories",
      handoff_id: "repositories",
      label: "Repositories",
      path: "/repos",
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.ProjectInventoryLive,
      route_action: :index,
      summary: "Managed repositories and detail context"
    },
    %{
      area: :workbench,
      id: "workbench",
      handoff_id: "workbench",
      label: "Workbench",
      path: "/workbench",
      local_context_key: :workbench_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.WorkbenchLive,
      route_action: :index,
      summary: "Dense specialist workspace"
    },
    %{
      area: :conversations,
      id: "conversations",
      handoff_id: "conversations",
      label: "Conversations",
      path: "/conversations",
      local_context_key: :conversation_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.OperatorRootLive,
      route_action: :conversations,
      summary: "Productive threads and runtime continuity"
    },
    %{
      area: :workflows,
      id: "workflows",
      handoff_id: "workflows",
      label: "Workflows",
      path: "/workflows",
      local_context_key: :workflow_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.WorkflowsLive,
      route_action: :index,
      summary: "Governed run launch and history"
    },
    %{
      area: :agents,
      id: "agents",
      handoff_id: "agents",
      label: "Agents",
      path: "/agents",
      local_context_key: :agent_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.AgentsLive,
      route_action: :index,
      summary: "Repo-scoped support automation"
    },
    %{
      area: :memory,
      id: "memory",
      handoff_id: "memory",
      label: "Memory",
      path: "/memory",
      local_context_key: :memory_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.OperatorRootLive,
      route_action: :memory,
      summary: "Durable memory and provenance recall"
    },
    %{
      area: :semantic,
      id: "semantic",
      handoff_id: "semantic",
      label: "Semantic",
      path: "/semantic",
      local_context_key: :semantic_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.OperatorRootLive,
      route_action: :semantic,
      summary: "Source graph and semantic inspection"
    },
    %{
      area: :settings,
      id: "settings",
      handoff_id: "settings",
      label: "Settings",
      path: "/settings",
      local_context_key: :settings_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.SettingsLive,
      route_action: :index,
      summary: "Auth, integrations, and runtime defaults"
    }
  ]

  @root_handoff_route %{
    id: :root,
    path: "/",
    active_area: :dashboard,
    handoff_path: "/dashboard",
    required_auth: :public_bootstrap_gate,
    route_owner: JidoCodeWeb.PageController,
    route_action: :home,
    summary: "Public root gate that hands ready authenticated operators to the dashboard shell"
  }

  @detail_routes [
    %{
      id: :repository_detail,
      path: "/repos/:id",
      active_area: :repositories,
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.ProjectDetailLive,
      route_action: :show,
      summary: "Repository detail shell surface"
    },
    %{
      id: :run_detail,
      path: "/repos/:id/runs/:run_id",
      active_area: :repositories,
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.RunDetailLive,
      route_action: :show,
      summary: "Governed run detail shell surface"
    },
    %{
      id: :work_item_detail,
      path: "/repos/:id/work-items/:work_item_id",
      active_area: :repositories,
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.WorkItemDetailLive,
      route_action: :show,
      summary: "Governed work item detail shell surface"
    },
    %{
      id: :evidence_detail,
      path: "/repos/:id/evidence/:evidence_id",
      active_area: :repositories,
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.EvidenceDetailLive,
      route_action: :show,
      summary: "Governed evidence detail shell surface"
    },
    %{
      id: :decision_detail,
      path: "/repos/:id/decisions/:decision_id",
      active_area: :repositories,
      local_context_key: :repository_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.DecisionDetailLive,
      route_action: :show,
      summary: "Governed decision detail shell surface"
    },
    %{
      id: :settings_tab,
      path: "/settings/:tab",
      active_area: :settings,
      local_context_key: :settings_state,
      required_auth: :live_user_required,
      route_owner: JidoCodeWeb.SettingsLive,
      route_action: :index,
      summary: "Settings tab detail shell surface"
    }
  ]

  @shell_regions [
    %{id: :brand, label: "Brand block", owner: :layout, purpose: "Product identity and home link"},
    %{id: :subtitle, label: "Route subtitle", owner: :layout, purpose: "Current area framing"},
    %{id: :actions, label: "Action slot", owner: :route, purpose: "Area-local primary actions"},
    %{id: :theme_toggle, label: "Theme toggle", owner: :layout, purpose: "System, light, and dark mode"},
    %{id: :area_menu, label: "Area button menu", owner: :layout, purpose: "Major product area navigation"},
    %{id: :status_strip, label: "Status strip", owner: :layout, purpose: "Scope, runtime, warnings, and degradation"},
    %{id: :content, label: "Content body", owner: :route, purpose: "Area-local product surface"}
  ]

  @legacy_replacement_targets [
    %{id: :operator_navigation, module: nil, replacement: :area_menu},
    %{id: :route_local_chrome, module: nil, replacement: :route_shell_components},
    %{id: :legacy_section_shell, module: nil, replacement: :route_section_shell},
    %{id: :legacy_theme, module: nil, replacement: :shadcn_tokens}
  ]

  def registered_areas, do: @areas

  def navigation_items do
    Enum.map(@areas, &Map.take(&1, [:area, :id, :handoff_id, :label, :path, :summary, :required_auth]))
  end

  def root_handoff_route, do: @root_handoff_route

  def authenticated_area_routes do
    Enum.map(@areas, fn area ->
      Map.take(area, [
        :area,
        :id,
        :path,
        :local_context_key,
        :required_auth,
        :route_owner,
        :route_action,
        :summary
      ])
    end)
  end

  def detail_routes, do: @detail_routes

  def route_map do
    [@root_handoff_route | authenticated_area_routes() ++ @detail_routes]
  end

  def area_metadata!(area) when is_atom(area) do
    Enum.find(@areas, &(&1.area == area)) ||
      raise ArgumentError, "unknown product area #{inspect(area)}"
  end

  def area_label(area), do: area_metadata!(area).label

  def area_path(area), do: area_metadata!(area).path

  def area_for_live_action!(live_action) when is_atom(live_action) do
    Enum.find(@areas, &(&1.route_action == live_action)) ||
      raise ArgumentError, "unknown product area live action #{inspect(live_action)}"
  end

  def shell_regions, do: @shell_regions

  def legacy_replacement_targets, do: @legacy_replacement_targets

  def shell_state(active_area, attrs \\ []) when is_atom(active_area) do
    attrs = Map.new(attrs)
    area = area_metadata!(active_area)

    %{
      active_area: active_area,
      label: area.label,
      summary: area.summary,
      path: area.path,
      id: area.id,
      handoff_id: area.handoff_id,
      required_auth: area.required_auth,
      route_owner: area.route_owner,
      route_action: area.route_action,
      current_scope: Map.get(attrs, :current_scope),
      connection_status: Map.get(attrs, :connection_status, :session_required),
      runtime_status: Map.get(attrs, :runtime_status, :unknown),
      warnings: attrs |> Map.get(:warnings, []) |> List.wrap(),
      local_context_key: area.local_context_key,
      handoffs: handoff_targets(active_area)
    }
  end

  def handoff_targets(active_area) when is_atom(active_area) do
    source = area_metadata!(active_area)

    @areas
    |> Enum.reject(&(&1.area == active_area))
    |> Enum.map(fn target ->
      %{
        id: "#{source.handoff_id}-to-#{target.handoff_id}",
        target_area: target.area,
        label: "Open #{target.label}",
        path: target.path
      }
    end)
  end
end
