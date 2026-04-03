defmodule JidoCodeWeb.LiveVueCase do
  @moduledoc false

  import ExUnit.Assertions

  alias Phoenix.LiveView.JS

  def vue(view_or_html, opts \\ []) do
    LiveVue.Test.get_vue(view_or_html, opts)
  end

  def assert_vue_component(view_or_html, component, opts \\ []) do
    vue = vue(view_or_html, opts)
    assert vue.component == component
    vue
  end

  def assert_vue_prop(view_or_html, key, expected, opts \\ []) do
    vue = vue(view_or_html, opts)
    assert Map.fetch!(vue.props, to_string(key)) == expected
    vue
  end

  def assert_vue_handler(view_or_html, emit, expected, opts \\ []) do
    vue = vue(view_or_html, opts)

    expected =
      case expected do
        %JS{} = js -> js
        event_name when is_binary(event_name) -> JS.push(event_name)
      end

    assert Map.fetch!(vue.handlers, to_string(emit)) == expected
    vue
  end
end
