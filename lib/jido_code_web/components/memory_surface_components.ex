defmodule JidoCodeWeb.MemorySurfaceComponents do
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  @moduledoc false

  use Phoenix.Component

  import JidoCodeWeb.OperatorStateComponents

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :state, :map, required: true
  attr :kind, :atom, default: :warning
  attr :recovery, :map, default: nil
  attr :recover_event, :string, default: nil
  attr :recover_id, :string, default: nil

  def memory_status_notice(assigns) do
    assigns =
      assign_new(assigns, :recover_id, fn ->
        "#{assigns.id}-recover"
      end)

    ~H"""
    <.operator_state_notice id={@id} title={@title} state={@state} kind={@kind}>
      <:actions>
        <button
          :if={recovery_available?(@recovery) and is_binary(@recover_event)}
          id={@recover_id}
          type="button"
          class="btn btn-sm btn-outline"
          phx-click={@recover_event}
        >
          {recovery_label(@recovery)}
        </button>
      </:actions>
    </.operator_state_notice>
    """
  end

  attr :dom_prefix, :string, required: true
  attr :item, :map, required: true
  attr :include_governed, :boolean, default: true
  attr :governed_label, :string, default: "Governed context"
  attr :source_label, :string, default: "Source code"
  attr :related_label, :string, default: "Related memory"

  def memory_link_groups(assigns) do
    ~H"""
    <div class="space-y-1">
      <.memory_link_group
        :if={@include_governed and navigation_links(@item, :governed_records) != []}
        dom_prefix={"#{@dom_prefix}-governed"}
        label={@governed_label}
        links={navigation_links(@item, :governed_records)}
      />
      <.memory_link_group
        :if={navigation_links(@item, :source_code) != []}
        dom_prefix={"#{@dom_prefix}-source"}
        label={@source_label}
        links={navigation_links(@item, :source_code)}
      />
      <.memory_link_group
        :if={navigation_links(@item, :related_memories) != []}
        dom_prefix={"#{@dom_prefix}-related"}
        label={@related_label}
        links={navigation_links(@item, :related_memories)}
      />
    </div>
    """
  end

  attr :dom_prefix, :string, required: true
  attr :label, :string, required: true
  attr :links, :list, required: true

  def memory_link_group(assigns) do
    ~H"""
    <div class="space-y-1">
      <p id={"#{@dom_prefix}-label"} class="text-[11px] font-medium uppercase tracking-wide text-base-content/60">
        {@label}
      </p>
      <div id={"#{@dom_prefix}-links"} class="flex flex-wrap gap-2">
        <%= for {link, index} <- Enum.with_index(@links, 1) do %>
          <%= if is_binary(link.route) do %>
            <.link
              id={"#{@dom_prefix}-link-#{index}"}
              href={link.route}
              class="link link-primary text-xs"
            >
              {link.label}
            </.link>
          <% else %>
            <span
              id={"#{@dom_prefix}-label-only-#{index}"}
              class="badge badge-outline badge-sm text-xs font-normal"
            >
              {link.label}
            </span>
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  defp navigation_links(item, key) when is_map(item) do
    item
    |> map_get(:navigation, "navigation", %{})
    |> map_get(key, Atom.to_string(key), [])
    |> Enum.map(&normalize_link/1)
    |> Enum.filter(&(is_binary(Map.get(&1, :label)) and String.trim(Map.get(&1, :label)) != ""))
  end

  defp navigation_links(_item, _key), do: []

  defp normalize_link(link) when is_map(link) do
    %{
      kind: map_get(link, :kind, "kind"),
      id: map_get(link, :id, "id"),
      label: map_get(link, :label, "label") || fallback_label(link),
      route: map_get(link, :route, "route")
    }
  end

  defp normalize_link(_link), do: %{kind: nil, id: nil, label: nil, route: nil}

  defp fallback_label(link) do
    kind =
      link
      |> map_get(:kind, "kind")
      |> normalize_optional_string()

    id =
      link
      |> map_get(:id, "id")
      |> normalize_optional_string()

    case {kind, id} do
      {nil, nil} -> nil
      {kind, nil} -> kind
      {nil, id} -> id
      {kind, id} -> "#{kind} #{id}"
    end
  end

  defp recovery_available?(%{available?: true}), do: true
  defp recovery_available?(_recovery), do: false

  defp recovery_label(%{label: label}) when is_binary(label), do: label
  defp recovery_label(_recovery), do: "Recover memory graph"

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
