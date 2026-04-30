defmodule JidoCode.MemoryGraph.FollowUpSurface do
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections
  @moduledoc """
  Shapes bounded follow-up previews from product-owned memory projections.

  Product surfaces can stage governed follow-up from durable memory without
  reaching for raw graph responses or direct runtime contracts.
  """

  alias JidoCode.MemoryGraph.Finding

  @priority_order %{
    "KnownIssue" => 0,
    "AntiPattern" => 1,
    "OpenQuestion" => 2,
    "Decision" => 3,
    "Invariant" => 4,
    "Convention" => 5,
    "Pattern" => 6,
    "Fact" => 7,
    "LessonLearned" => 8
  }

  @spec preview(map() | nil, keyword()) :: map()
  def preview(projection, opts \\ [])

  def preview(%{kind: :memories} = projection, opts) do
    selected_items =
      projection
      |> Map.get(:items, [])
      |> prioritized_items(Keyword.get(opts, :item_limit, 2))

    if selected_items == [] do
      unavailable_preview()
    else
      case Finding.from_projection(
             projection,
             selected_items: selected_items,
             category: Keyword.get(opts, :category, "memory_graph_follow_up_preview"),
             recommended_action: "promote_memory_follow_up",
             summary: Keyword.get(opts, :summary)
           ) do
        {:ok, finding} ->
          route = normalize_optional_string(Keyword.get(opts, :route))

          %{
            available?: true,
            summary: Map.get(finding, :summary),
            recommended_action: Map.get(finding, :recommended_action),
            recommended_action_label: recommended_action_label(Map.get(finding, :recommended_action)),
            priority: Map.get(finding, :priority),
            urgency: Map.get(finding, :urgency),
            selected_count: length(selected_items),
            memory_kinds:
              selected_items
              |> Enum.map(&memory_kind/1)
              |> Enum.reject(&is_nil/1)
              |> Enum.uniq(),
            route: route,
            route_label: route_label(route),
            workflow_context: %{
              "category" => Keyword.get(opts, :category, "memory_graph_follow_up_preview"),
              "memory_resources" =>
                selected_items
                |> Enum.map(&memory_iri/1)
                |> Enum.reject(&is_nil/1),
              "memory_kinds" =>
                selected_items
                |> Enum.map(&memory_kind/1)
                |> Enum.reject(&is_nil/1)
                |> Enum.uniq()
            }
          }

        {:error, _reason} ->
          unavailable_preview()
      end
    end
  end

  def preview(%{kind: :conversation_recall} = projection, opts) do
    selected_items =
      projection
      |> Map.get(:items, [])
      |> Enum.take(Keyword.get(opts, :item_limit, 2))

    if selected_items == [] do
      unavailable_preview()
    else
      case Finding.from_projection(
             projection,
             selected_items: selected_items,
             category: Keyword.get(opts, :category, "conversation_recall_follow_up_preview"),
             recommended_action: "promote_conversation_follow_up",
             summary: Keyword.get(opts, :summary)
           ) do
        {:ok, finding} ->
          route = normalize_optional_string(Keyword.get(opts, :route))

          %{
            available?: true,
            summary: Map.get(finding, :summary),
            recommended_action: Map.get(finding, :recommended_action),
            recommended_action_label: recommended_action_label(Map.get(finding, :recommended_action)),
            priority: Map.get(finding, :priority),
            urgency: Map.get(finding, :urgency),
            selected_count: length(selected_items),
            memory_kinds: [],
            route: route,
            route_label: route_label(route),
            workflow_context: %{
              "category" => Keyword.get(opts, :category, "conversation_recall_follow_up_preview"),
              "conversation_resources" =>
                selected_items
                |> Enum.flat_map(&(Map.get(&1, :resource_iris, []) |> List.wrap()))
                |> Enum.reject(&is_nil/1)
                |> Enum.uniq(),
              "conversation_ids" =>
                selected_items
                |> Enum.map(&Map.get(&1, :conversation_id))
                |> Enum.reject(&is_nil/1)
                |> Enum.uniq()
            }
          }

        {:error, _reason} ->
          unavailable_preview()
      end
    end
  end

  def preview(_projection, _opts), do: unavailable_preview()

  defp unavailable_preview do
    %{
      available?: false,
      summary: nil,
      recommended_action: nil,
      recommended_action_label: nil,
      priority: nil,
      urgency: nil,
      selected_count: 0,
      memory_kinds: [],
      route: nil,
      route_label: nil,
      workflow_context: %{}
    }
  end

  defp prioritized_items(items, item_limit) when is_list(items) do
    items
    |> Enum.sort_by(fn item ->
      kind = memory_kind(item)
      Map.get(@priority_order, kind, 99)
    end)
    |> Enum.take(item_limit)
  end

  defp prioritized_items(_items, _item_limit), do: []

  defp memory_iri(item) when is_map(item) do
    normalized_string(Map.get(item, :memory_iri) || Map.get(item, "memory_iri"))
  end

  defp memory_iri(_item), do: nil

  defp memory_kind(item) when is_map(item) do
    normalized_string(Map.get(item, :memory_kind) || Map.get(item, "memory_kind")) ||
      kind_from_iri(memory_iri(item))
  end

  defp memory_kind(_item), do: nil

  defp kind_from_iri(nil), do: nil

  defp kind_from_iri(value) when is_binary(value) do
    value
    |> String.split("#")
    |> List.last()
    |> case do
      nil -> nil
      fragment -> fragment |> String.split("/") |> List.first()
    end
    |> normalized_string()
    |> case do
      nil -> nil
      segment -> segment |> String.replace("-", "_") |> Macro.camelize()
    end
  end

  defp route_label(nil), do: nil
  defp route_label(_route), do: "Review bounded follow-up context"

  defp recommended_action_label("promote_memory_follow_up"), do: "Promote governed follow-up"
  defp recommended_action_label("promote_conversation_follow_up"), do: "Promote conversation follow-up"

  defp recommended_action_label(action) when is_binary(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp recommended_action_label(_action), do: "Review bounded follow-up"

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp normalized_string(value) do
    case normalize_optional_string(value) do
      "nil" -> nil
      normalized -> normalized
    end
  end
end
