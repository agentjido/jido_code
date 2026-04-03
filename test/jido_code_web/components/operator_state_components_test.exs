defmodule JidoCodeWeb.OperatorStateComponentsTest do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest

  defmodule Harness do
    use Phoenix.Component

    import JidoCodeWeb.OperatorStateComponents

    def warning(assigns) do
      ~H"""
      <.operator_state_notice
        id="operator-state"
        title="Shared operator state"
        state={@state}
        kind={:warning}
        compact={true}
      >
        <p id="operator-state-extra">Extra context</p>
        <:actions>
          <button id="operator-state-action" type="button">Retry</button>
        </:actions>
      </.operator_state_notice>
      """
    end

    def notice(assigns) do
      ~H"""
      <.operator_state_notice
        id="operator-state"
        title="Shared operator notice"
        state={@state}
        kind={:notice}
        dom_prefix="custom-operator-state"
      />
      """
    end
  end

  test "operator_state_notice renders typed state detail, remediation, and actions" do
    html =
      render_component(&Harness.warning/1, %{
        state: %{
          error_type: "stale_feed",
          detail: "The summarized data is behind the current control-plane state.",
          remediation: "Retry the affected refresh path after reviewing persistence health."
        }
      })

    assert html =~ ~s(id="operator-state-label")
    assert html =~ "Shared operator state"
    assert html =~ ~s(id="operator-state-type")
    assert html =~ "Typed warning: stale_feed"
    assert html =~ ~s(id="operator-state-detail")
    assert html =~ "The summarized data is behind the current control-plane state."
    assert html =~ ~s(id="operator-state-remediation")
    assert html =~ "Retry the affected refresh path after reviewing persistence health."
    assert html =~ ~s(id="operator-state-extra")
    assert html =~ ~s(id="operator-state-action")
  end

  test "operator_state_notice can change the DOM prefix without changing the section id" do
    html =
      render_component(&Harness.notice/1, %{
        state: %{
          error_type: "filter_reset_notice",
          detail: "Invalid values were replaced with product defaults."
        }
      })

    assert html =~ ~s(id="operator-state")
    assert html =~ ~s(id="custom-operator-state-label")
    assert html =~ ~s(id="custom-operator-state-type")
    assert html =~ ~s(id="custom-operator-state-detail")
    assert html =~ "Typed notice: filter_reset_notice"
    refute html =~ "custom-operator-state-remediation"
  end
end
