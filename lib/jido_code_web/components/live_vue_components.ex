defmodule JidoCodeWeb.LiveVueComponents do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.live_vue_is_canonical_rich_component_bridge
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  @moduledoc """
  Product-owned helpers for mounting Vue-backed islands inside the LiveView shell.

  The goal is to keep `live_vue` usage consistent across the product:

  - LiveView owns routes, auth, sessions, and server-authored state
  - Vue receives bounded props and optional top-level streams
  - Vue emits map back into LiveView events through explicit bindings
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS
  alias Phoenix.LiveView.LiveStream
  alias JidoCodeWeb.FrontendAssets

  @component_name_pattern ~r/^[A-Z][A-Za-z0-9]*(?:\/[A-Z][A-Za-z0-9]*)*$/
  @reserved_prop_keys ~w(
    __changed__
    __given__
    class
    component
    diff
    events
    id
    inner_block
    props
    socket
    ssr
    streams
    v-component
    v-diff
    v-on
    v-socket
    v-ssr
  )

  attr :component, :string, required: true
  attr :socket, :any, required: true
  attr :props, :map, default: %{}
  attr :streams, :map, default: %{}
  attr :events, :map, default: %{}
  attr :id, :string, default: nil
  attr :class, :any, default: nil
  attr :ssr, :boolean, default: nil
  attr :diff, :boolean, default: nil
  attr :fallback_title, :string, default: nil
  attr :fallback_detail, :string, default: nil
  slot :inner_block

  def vue_surface(assigns) do
    component = validate_component_name!(assigns.component)
    props = validate_props!(assigns.props)
    streams = validate_streams!(assigns.streams)
    events = normalize_events!(assigns.events)
    delivery = FrontendAssets.vue_surface_delivery(component)

    if delivery.mode == :fallback do
      assigns =
        assigns
        |> assign(:delivery, delivery)
        |> assign(:fallback_title, assigns.fallback_title || delivery.title)
        |> assign(:fallback_detail, assigns.fallback_detail || delivery.detail)
        |> assign(:fallback_id, fallback_id(assigns.id, component))

      ~H"""
      <section
        id={@fallback_id}
        class={[
          "rounded-lg border border-warning/50 bg-warning/10 p-4 space-y-2",
          @class
        ]}
      >
        <p class="font-semibold">{@fallback_title}</p>
        <p class="text-sm text-base-content/80">{@fallback_detail}</p>
        <p :if={@delivery.reason} class="text-xs text-base-content/70">
          Fallback mode reason: {humanize_reason(@delivery.reason)}
        </p>
        {render_slot(@inner_block)}
      </section>
      """
    else
      vue_assigns =
        assigns
        |> Map.take([:__changed__, :inner_block])
        |> Map.put(:"v-component", component)
        |> Map.put(:"v-socket", assigns.socket)
        |> maybe_put(:id, assigns.id)
        |> maybe_put(:class, assigns.class)
        |> maybe_put(:"v-ssr", coalesce_ssr(assigns.ssr, delivery.ssr))
        |> maybe_put(:"v-diff", assigns.diff)
        |> Map.merge(props)
        |> Map.merge(streams)

      vue_assigns =
        Enum.reduce(events, vue_assigns, fn {emit, handler}, acc ->
          Map.put(acc, "v-on:#{emit}", handler)
        end)

      LiveVue.vue(vue_assigns)
    end
  end

  defp maybe_put(assigns, _key, nil), do: assigns
  defp maybe_put(assigns, key, value), do: Map.put(assigns, key, value)

  defp validate_component_name!(component) when is_binary(component) do
    if Regex.match?(@component_name_pattern, component) do
      component
    else
      raise ArgumentError,
            "expected a PascalCase LiveVue component name or path, got: #{inspect(component)}"
    end
  end

  defp validate_component_name!(component) do
    raise ArgumentError,
          "expected a LiveVue component name as a string, got: #{inspect(component)}"
  end

  defp validate_props!(props) when is_map(props) do
    Enum.each(props, fn {key, _value} ->
      normalized = normalize_key!(key, :props)

      cond do
        normalized in @reserved_prop_keys ->
          raise ArgumentError, "reserved prop key #{inspect(key)} cannot be passed through vue_surface/1"

        String.starts_with?(normalized, "v-on:") ->
          raise ArgumentError, "event bindings belong in :events, not :props (got #{inspect(key)})"

        String.starts_with?(normalized, "v-") ->
          raise ArgumentError, "reserved LiveVue key #{inspect(key)} cannot be passed through :props"

        true ->
          :ok
      end
    end)

    props
  end

  defp validate_props!(props) do
    raise ArgumentError, "expected :props to be a map, got: #{inspect(props)}"
  end

  defp validate_streams!(streams) when is_map(streams) do
    Enum.each(streams, fn {key, value} ->
      normalized = normalize_key!(key, :streams)

      if normalized in @reserved_prop_keys do
        raise ArgumentError, "reserved stream key #{inspect(key)} cannot be passed through vue_surface/1"
      end

      unless match?(%LiveStream{}, value) do
        raise ArgumentError,
              "expected stream #{inspect(key)} to be a Phoenix.LiveView.LiveStream, got: #{inspect(value)}"
      end
    end)

    streams
  end

  defp validate_streams!(streams) do
    raise ArgumentError, "expected :streams to be a map, got: #{inspect(streams)}"
  end

  defp normalize_events!(events) when is_map(events) do
    Map.new(events, fn {emit, handler} ->
      emit = normalize_emit_name!(emit)

      normalized_handler =
        case handler do
          %JS{} = js ->
            js

          event_name when is_binary(event_name) ->
            JS.push(event_name)

          other ->
            raise ArgumentError,
                  "expected event handler for #{inspect(emit)} to be a string or JS, got: #{inspect(other)}"
        end

      {emit, normalized_handler}
    end)
  end

  defp normalize_events!(events) do
    raise ArgumentError, "expected :events to be a map, got: #{inspect(events)}"
  end

  defp normalize_key!(key, _context) when is_atom(key), do: Atom.to_string(key)

  defp normalize_key!(key, _context) when is_binary(key), do: key

  defp normalize_key!(key, context) do
    raise ArgumentError, "expected #{context} keys to be atoms or strings, got: #{inspect(key)}"
  end

  defp normalize_emit_name!(emit) do
    emit = normalize_key!(emit, :events)

    if emit == "" or String.starts_with?(emit, "v-on:") do
      raise ArgumentError, "expected a Vue emit name without the v-on: prefix, got: #{inspect(emit)}"
    else
      emit
    end
  end

  defp coalesce_ssr(explicit_ssr, nil), do: explicit_ssr
  defp coalesce_ssr(_explicit_ssr, fallback_ssr), do: fallback_ssr

  defp fallback_id(nil, component), do: "vue-surface-fallback-#{String.replace(component, "/", "-")}"
  defp fallback_id(id, _component), do: "#{id}-fallback"

  defp humanize_reason(reason) when is_atom(reason) do
    reason
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp humanize_reason(reason), do: to_string(reason)
end
