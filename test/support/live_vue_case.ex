defmodule JidoCodeWeb.LiveVueCase do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
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

    expected = normalize_js(expected)

    assert normalize_js(Map.fetch!(vue.handlers, to_string(emit))) == expected
    vue
  end

  defp normalize_js(%JS{ops: ops} = js) do
    %{js | ops: normalize_term(ops)}
  end

  defp normalize_term(term) when is_list(term), do: Enum.map(term, &normalize_term/1)

  defp normalize_term(term) when is_map(term) do
    Map.new(term, fn {key, value} -> {normalize_key(key), normalize_term(value)} end)
  end

  defp normalize_term(term), do: term

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key), do: key
end
