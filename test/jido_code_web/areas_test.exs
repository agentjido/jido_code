defmodule JidoCodeWeb.AreasTest do
  use ExUnit.Case, async: true

  alias JidoCodeWeb.Areas

  test "registered areas define the target root button menu" do
    items = Areas.navigation_items()

    assert Enum.map(items, & &1.area) == [
             :dashboard,
             :repositories,
             :workbench,
             :conversations,
             :workflows,
             :agents,
             :memory,
             :semantic,
             :settings
           ]

    assert Enum.map(items, & &1.id) == Enum.uniq(Enum.map(items, & &1.id))
    assert Enum.map(items, & &1.path) == Enum.uniq(Enum.map(items, & &1.path))
    assert Enum.all?(items, &String.starts_with?(&1.path, "/"))
    assert Enum.all?(items, &(&1.required_auth == :live_user_required))
    assert Enum.all?(items, &is_binary(&1.handoff_id))
  end

  test "shell state keeps route-owned active area context and handoffs" do
    state =
      Areas.shell_state(:repositories,
        current_scope: %{user_id: "owner-1"},
        connection_status: :connected,
        runtime_status: :ready,
        warnings: ["workspace missing"]
      )

    assert state.active_area == :repositories
    assert state.label == "Repositories"
    assert state.current_scope == %{user_id: "owner-1"}
    assert state.connection_status == :connected
    assert state.runtime_status == :ready
    assert state.warnings == ["workspace missing"]
    assert state.local_context_key == :repository_state
    assert state.path == "/repos"
    assert state.required_auth == :live_user_required
    assert state.route_owner == JidoCodeWeb.ProjectInventoryLive
    refute Enum.any?(state.handoffs, &(&1.target_area == :repositories))
    assert Enum.any?(state.handoffs, &(&1.id == "repositories-to-workbench"))
  end

  test "area helpers expose metadata and fail closed for unknown areas" do
    assert Areas.area_label(:semantic) == "Semantic"
    assert Areas.area_path(:semantic) == "/semantic"
    assert Areas.area_for_live_action!(:memory).area == :memory

    assert_raise ArgumentError, ~r/unknown product area :unknown/, fn ->
      Areas.area_metadata!(:unknown)
    end

    assert_raise ArgumentError, ~r/unknown product area live action :unknown/, fn ->
      Areas.area_for_live_action!(:unknown)
    end
  end

  test "route map records root handoff, root areas, and detail route ownership" do
    assert Areas.root_handoff_route() == %{
             id: :root,
             path: "/",
             active_area: :dashboard,
             handoff_path: "/dashboard",
             required_auth: :public_bootstrap_gate,
             route_owner: JidoCodeWeb.PageController,
             route_action: :home,
             summary: "Public root gate that hands ready authenticated operators to the dashboard shell"
           }

    assert Enum.any?(Areas.authenticated_area_routes(), fn route ->
             route.path == "/semantic" and
               route.area == :semantic and
               route.route_owner == JidoCodeWeb.OperatorRootLive and
               route.route_action == :semantic
           end)

    assert Enum.any?(Areas.detail_routes(), fn route ->
             route.path == "/repos/:id/runs/:run_id" and
               route.active_area == :repositories and
               route.route_owner == JidoCodeWeb.RunDetailLive
           end)

    route_paths = Areas.route_map() |> Enum.map(& &1.path)

    for path <- ["/", "/dashboard", "/repos", "/workbench", "/workflows", "/agents", "/settings"] do
      assert path in route_paths
    end
  end

  test "shell contract documents layout regions and legacy replacement targets" do
    assert Enum.map(Areas.shell_regions(), & &1.id) == [
             :brand,
             :subtitle,
             :actions,
             :theme_toggle,
             :area_menu,
             :status_strip,
             :content
           ]

    replacements = Areas.legacy_replacement_targets()

    assert %{id: :operator_navigation, module: nil, replacement: :area_menu} in replacements

    assert %{id: :legacy_theme, module: nil, replacement: :shadcn_tokens} in replacements
  end
end
