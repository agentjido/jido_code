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
  attr :recover_event, :any, default: nil
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
          class="ui-button ui-button-sm ui-button-outline"
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
  attr :conversation_label, :string, default: "Canonical conversation"
  attr :governed_label, :string, default: "Governed context"
  attr :source_label, :string, default: "Source code"
  attr :related_label, :string, default: "Related memory"

  def memory_link_groups(assigns) do
    ~H"""
    <div class="space-y-1">
      <.memory_link_group
        :if={conversation_links(@item) != []}
        dom_prefix={"#{@dom_prefix}-conversation"}
        label={@conversation_label}
        links={conversation_links(@item)}
      />
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
  attr :item, :map, required: true

  def conversation_origin_card(assigns) do
    ~H"""
    <div class="space-y-2">
      <div class="space-y-1">
        <p id={"#{@dom_prefix}-summary"} class="font-medium">
          {conversation_origin_summary(@item)}
        </p>
        <p
          :if={conversation_origin_preview(@item)}
          id={"#{@dom_prefix}-preview"}
          class="text-sm text-foreground"
        >
          {conversation_origin_preview(@item)}
        </p>
        <p
          :if={conversation_origin_metadata(@item) != []}
          id={"#{@dom_prefix}-metadata"}
          class="text-xs text-muted-foreground"
        >
          {Enum.join(conversation_origin_metadata(@item), " | ")}
        </p>
        <p
          :if={conversation_anchor(@item)}
          id={"#{@dom_prefix}-anchor"}
          class="text-xs text-muted-foreground"
        >
          Code anchor: {conversation_anchor(@item)}
        </p>
      </div>

      <.memory_link_groups dom_prefix={@dom_prefix} item={@item} />
    </div>
    """
  end

  attr :dom_prefix, :string, required: true
  attr :label, :string, required: true
  attr :links, :list, required: true

  def memory_link_group(assigns) do
    ~H"""
    <div class="space-y-1">
      <p id={"#{@dom_prefix}-label"} class="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">
        {@label}
      </p>
      <div id={"#{@dom_prefix}-links"} class="flex flex-wrap gap-2">
        <%= for {link, index} <- Enum.with_index(@links, 1) do %>
          <%= if is_binary(link.route) do %>
            <.link
              id={"#{@dom_prefix}-link-#{index}"}
              href={link.route}
              class="text-primary underline-offset-4 hover:underline text-xs"
            >
              {link.label}
            </.link>
          <% else %>
            <span
              id={"#{@dom_prefix}-label-only-#{index}"}
              class="ui-badge ui-badge-sm ui-badge-outline text-xs font-normal"
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

  defp conversation_links(item) when is_map(item) do
    route =
      item
      |> map_get(:conversation_route, "conversation_route")
      |> normalize_optional_string()

    label =
      item
      |> map_get(:conversation_route_label, "conversation_route_label")
      |> normalize_optional_string()

    if is_binary(route) do
      [
        %{
          kind: :conversation,
          id: nil,
          label: label || "Open canonical conversation",
          route: route
        }
      ]
    else
      []
    end
  end

  defp conversation_links(_item), do: []

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

  defp conversation_origin_summary(item) when is_map(item) do
    item
    |> map_get(:origin_summary, "origin_summary")
    |> normalize_optional_string() ||
      item
      |> map_get(:label, "label")
      |> normalize_optional_string() ||
      "Conversation origin remains available as bounded recall."
  end

  defp conversation_origin_summary(_item), do: "Conversation origin remains available as bounded recall."

  defp conversation_origin_preview(item) when is_map(item) do
    item
    |> map_get(:content_preview, "content_preview")
    |> normalize_optional_string() ||
      item
      |> map_get(:content, "content")
      |> normalize_optional_string()
  end

  defp conversation_origin_preview(_item), do: nil

  defp conversation_origin_metadata(item) when is_map(item) do
    []
    |> maybe_append_segment(latest_event_segment(item))
    |> maybe_append_segment(conversation_id_segment(item))
    |> maybe_append_segment(scope_segment(item))
    |> maybe_append_segment(status_segment(item))
  end

  defp conversation_origin_metadata(_item), do: []

  defp latest_event_segment(item) do
    item
    |> map_get(:latest_event, "latest_event")
    |> humanize_segment("Latest event")
  end

  defp conversation_id_segment(item) do
    item
    |> conversation_context_value(:conversation_id, "conversation_id")
    |> then(fn
      nil -> nil
      conversation_id -> "Conversation: #{conversation_id}"
    end)
  end

  defp scope_segment(item) do
    item
    |> conversation_context_value(:scope, "scope")
    |> humanize_segment("Scope")
  end

  defp status_segment(item) do
    item
    |> conversation_context_value(:status, "status")
    |> humanize_segment("Status")
  end

  defp conversation_anchor(item) when is_map(item) do
    item
    |> map_get(:module_name, "module_name")
    |> normalize_optional_string() ||
      item
      |> map_get(:function_name, "function_name")
      |> normalize_optional_string()
  end

  defp conversation_anchor(_item), do: nil

  defp conversation_context_value(item, atom_key, string_key) when is_map(item) do
    item
    |> map_get(:conversation_context, "conversation_context", %{})
    |> map_get(atom_key, string_key)
    |> normalize_optional_string()
  end

  defp maybe_append_segment(segments, nil), do: segments
  defp maybe_append_segment(segments, segment), do: segments ++ [segment]

  defp humanize_segment(value, label) when is_binary(label) do
    case normalize_optional_string(value) do
      nil ->
        nil

      normalized ->
        humanized =
          normalized
          |> String.replace("_", " ")
          |> String.replace("-", " ")
          |> String.capitalize()

        "#{label}: #{humanized}"
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
