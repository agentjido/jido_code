defmodule JidoCodeWeb.Components.UI do
  # covers: architecture.frontend_stack.salad_ui_liveview_and_shadcn_vue_islands
  # covers: architecture.frontend_stack.product_owned_mounting_boundary

  @moduledoc """
  Application-owned boundary for HEEx components backed by SaladUI.

  LiveViews should import primitives through this module instead of depending on
  `SaladUI.*` modules directly. When a primitive needs product-specific
  customization, move the custom component under `JidoCodeWeb.Components` and
  keep this namespace as the public import boundary.
  """

  use Phoenix.Component

  defdelegate button(assigns), to: SaladUI.Button

  defdelegate dialog(assigns), to: SaladUI.Dialog
  defdelegate dialog_trigger(assigns), to: SaladUI.Dialog
  defdelegate dialog_content(assigns), to: SaladUI.Dialog
  defdelegate dialog_header(assigns), to: SaladUI.Dialog
  defdelegate dialog_title(assigns), to: SaladUI.Dialog
  defdelegate dialog_description(assigns), to: SaladUI.Dialog
  defdelegate dialog_footer(assigns), to: SaladUI.Dialog

  defdelegate table(assigns), to: SaladUI.Table
  defdelegate table_header(assigns), to: SaladUI.Table
  defdelegate table_body(assigns), to: SaladUI.Table
  defdelegate table_row(assigns), to: SaladUI.Table
  defdelegate table_head(assigns), to: SaladUI.Table
  defdelegate table_cell(assigns), to: SaladUI.Table
  defdelegate table_caption(assigns), to: SaladUI.Table

  defdelegate badge(assigns), to: SaladUI.Badge

  defdelegate alert(assigns), to: SaladUI.Alert
  defdelegate alert_title(assigns), to: SaladUI.Alert
  defdelegate alert_description(assigns), to: SaladUI.Alert

  defdelegate separator(assigns), to: SaladUI.Separator
  defdelegate scroll_area(assigns), to: SaladUI.ScrollArea
  defdelegate skeleton(assigns), to: SaladUI.Skeleton

  defdelegate tooltip(assigns), to: SaladUI.Tooltip
  defdelegate tooltip_trigger(assigns), to: SaladUI.Tooltip
  defdelegate tooltip_content(assigns), to: SaladUI.Tooltip

  defdelegate popover(assigns), to: SaladUI.Popover
  defdelegate popover_trigger(assigns), to: SaladUI.Popover
  defdelegate popover_content(assigns), to: SaladUI.Popover

  defdelegate command(assigns), to: SaladUI.Command
  defdelegate command_input(assigns), to: SaladUI.Command
  defdelegate command_empty(assigns), to: SaladUI.Command
  defdelegate command_list(assigns), to: SaladUI.Command
  defdelegate command_group(assigns), to: SaladUI.Command
  defdelegate command_item(assigns), to: SaladUI.Command
  defdelegate command_shortcut(assigns), to: SaladUI.Command

  defdelegate collapsible(assigns), to: SaladUI.Collapsible
  defdelegate collapsible_trigger(assigns), to: SaladUI.Collapsible
  defdelegate collapsible_content(assigns), to: SaladUI.Collapsible

  defdelegate tabs(assigns), to: SaladUI.Tabs
  defdelegate tabs_list(assigns), to: SaladUI.Tabs
  defdelegate tabs_trigger(assigns), to: SaladUI.Tabs
  defdelegate tabs_content(assigns), to: SaladUI.Tabs
end
