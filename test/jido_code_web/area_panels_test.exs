defmodule JidoCodeWeb.AreaPanelsTest do
  use ExUnit.Case, async: true

  alias JidoCodeWeb.{AreaPanels, Areas}

  test "each registered area has a server-authored overview panel" do
    for area <- Areas.registered_areas() do
      panel = AreaPanels.panel_for(area.area)

      assert panel.id == area.id
      assert panel.area == area.area
      assert panel.title == area.label
      assert panel.summary == area.summary
      assert is_binary(panel.posture)
      assert %{id: _, label: _, path: _} = panel.primary_action
      assert length(panel.metrics) == 3
      assert length(panel.sections) == 2
      assert length(panel.handoffs) == 4
      refute Enum.any?(panel.handoffs, &(&1.target_area == area.area))
    end
  end
end
