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
    refute Enum.any?(state.handoffs, &(&1.target_area == :repositories))
    assert Enum.any?(state.handoffs, &(&1.id == "repositories-to-workbench"))
  end

  test "area helpers expose metadata and fail closed for unknown areas" do
    assert Areas.area_label(:semantic) == "Semantic"
    assert Areas.area_path(:semantic) == "/semantic"

    assert_raise ArgumentError, ~r/unknown product area :unknown/, fn ->
      Areas.area_metadata!(:unknown)
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

    assert %{id: :operator_navigation, module: JidoCodeWeb.OperatorNavigation, replacement: :area_menu} in replacements

    assert %{id: :daisyui_theme, module: nil, replacement: :shadcn_tokens} in replacements
  end
end
