defmodule JidoCodeWeb.Areas do
  # covers: architecture.frontend_stack.root_area_shell_owns_navigation
  # covers: architecture.frontend_stack.greenfield_ui_reset_removes_legacy_surfaces
  @moduledoc """
  Target product-area contract for the UI reset shell.

  Phase 97 defines the shell target before the existing UI is replaced. The
  values here intentionally describe the destination area model rather than the
  current subject-tree implementation.
  """

  @areas [
    %{
      area: :dashboard,
      id: "dashboard",
      handoff_id: "dashboard",
      label: "Dashboard",
      path: "/dashboard",
      local_context_key: :dashboard_state,
      route_owner: :root_area,
      summary: "Operational home and next actions"
    },
    %{
      area: :repositories,
      id: "repositories",
      handoff_id: "repositories",
      label: "Repositories",
      path: "/repos",
      local_context_key: :repository_state,
      route_owner: :root_area,
      summary: "Managed repositories and detail context"
    },
    %{
      area: :workbench,
      id: "workbench",
      handoff_id: "workbench",
      label: "Workbench",
      path: "/workbench",
      local_context_key: :workbench_state,
      route_owner: :root_area,
      summary: "Dense specialist workspace"
    },
    %{
      area: :conversations,
      id: "conversations",
      handoff_id: "conversations",
      label: "Conversations",
      path: "/conversations",
      local_context_key: :conversation_state,
      route_owner: :root_area,
      summary: "Productive threads and runtime continuity"
    },
    %{
      area: :workflows,
      id: "workflows",
      handoff_id: "workflows",
      label: "Workflows",
      path: "/workflows",
      local_context_key: :workflow_state,
      route_owner: :root_area,
      summary: "Governed run launch and history"
    },
    %{
      area: :agents,
      id: "agents",
      handoff_id: "agents",
      label: "Agents",
      path: "/agents",
      local_context_key: :agent_state,
      route_owner: :root_area,
      summary: "Repo-scoped support automation"
    },
    %{
      area: :memory,
      id: "memory",
      handoff_id: "memory",
      label: "Memory",
      path: "/memory",
      local_context_key: :memory_state,
      route_owner: :root_area,
      summary: "Durable memory and provenance recall"
    },
    %{
      area: :semantic,
      id: "semantic",
      handoff_id: "semantic",
      label: "Semantic",
      path: "/semantic",
      local_context_key: :semantic_state,
      route_owner: :root_area,
      summary: "Source graph and semantic inspection"
    },
    %{
      area: :settings,
      id: "settings",
      handoff_id: "settings",
      label: "Settings",
      path: "/settings",
      local_context_key: :settings_state,
      route_owner: :root_area,
      summary: "Auth, integrations, and runtime defaults"
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
    %{id: :operator_navigation, module: JidoCodeWeb.OperatorNavigation, replacement: :area_menu},
    %{id: :operator_shell_components, module: JidoCodeWeb.OperatorShellComponents, replacement: :content},
    %{id: :subject_tree_shell, module: nil, replacement: :area_menu},
    %{id: :daisyui_theme, module: nil, replacement: :shadcn_tokens}
  ]

  def registered_areas, do: @areas

  def navigation_items do
    Enum.map(@areas, &Map.take(&1, [:area, :id, :label, :path, :summary]))
  end

  def area_metadata!(area) when is_atom(area) do
    Enum.find(@areas, &(&1.area == area)) ||
      raise ArgumentError, "unknown product area #{inspect(area)}"
  end

  def area_label(area), do: area_metadata!(area).label

  def area_path(area), do: area_metadata!(area).path

  def shell_regions, do: @shell_regions

  def legacy_replacement_targets, do: @legacy_replacement_targets

  def shell_state(active_area, attrs \\ []) when is_atom(active_area) do
    attrs = Map.new(attrs)
    area = area_metadata!(active_area)

    %{
      active_area: active_area,
      label: area.label,
      summary: area.summary,
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
