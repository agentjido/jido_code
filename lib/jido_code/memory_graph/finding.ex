defmodule JidoCode.MemoryGraph.Finding do
  # covers: architecture.memory_graph_product_adoption.memory_findings_rejoin_governed_product_records
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  @moduledoc """
  Builds bounded product findings from memory and workflow-provenance projections.
  """

  @supported_projection_kinds [:memories, :provenance, :conversation_recall]

  @spec from_projection(map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def from_projection(projection, opts \\ [])

  def from_projection(%{managed_repo_id: managed_repo_id, kind: kind} = projection, opts)
      when is_binary(managed_repo_id) and kind in @supported_projection_kinds do
    selected_items =
      opts
      |> Keyword.get(:selected_items, Map.get(projection, :items, []))
      |> List.wrap()
      |> Enum.take(Keyword.get(opts, :item_limit, 10))

    graph = normalize_graph(Map.get(projection, :graph, %{}))
    provenance = provenance(projection, opts, selected_items)
    summary = finding_summary(projection, selected_items, opts)

    finding =
      %{
        kind: :memory_finding,
        finding_type: Keyword.get(opts, :finding_type, kind),
        managed_repo_id: managed_repo_id,
        summary: summary,
        category: Keyword.get(opts, :category, default_category(kind)),
        priority: Keyword.get(opts, :priority, default_priority(kind, graph, selected_items)),
        urgency: Keyword.get(opts, :urgency, default_urgency(kind, graph, selected_items)),
        recommended_action:
          Keyword.get(opts, :recommended_action, default_recommended_action(kind)),
        graph: graph,
        provenance: provenance,
        payload: %{
          items: selected_items,
          result_group: normalize_map(Map.get(projection, :result_group, %{})),
          error: normalize_map(Map.get(projection, :error, %{}))
        }
      }
      |> Map.put(
        :digest,
        digest(%{
          managed_repo_id: managed_repo_id,
          finding_type: kind,
          summary: summary,
          graph: graph,
          provenance: provenance,
          payload: selected_items
        })
      )

    {:ok, finding}
  end

  def from_projection(_projection, _opts), do: {:error, :invalid_memory_projection}

  defp finding_summary(projection, selected_items, opts) do
    case normalize_optional_string(Keyword.get(opts, :summary)) do
      nil -> default_summary(projection, selected_items)
      summary -> summary
    end
  end

  defp default_summary(%{kind: :memories}, [%{memory_kind: memory_kind, module_name: module_name} | _rest])
       when is_binary(memory_kind) and is_binary(module_name) do
    "Review durable #{memory_kind} memory for #{module_name}."
  end

  defp default_summary(%{kind: :memories}, [%{memory_kind: memory_kind, content: content} | _rest])
       when is_binary(memory_kind) and is_binary(content) do
    "Review durable #{memory_kind} memory: #{content}"
  end

  defp default_summary(%{kind: :provenance}, [%{provenance_kind: provenance_kind, label: label} | _rest])
       when is_binary(provenance_kind) and is_binary(label) do
    "Review workflow provenance #{provenance_kind} for #{label}."
  end

  defp default_summary(%{kind: :provenance}, [%{provenance_kind: provenance_kind} | _rest])
       when is_binary(provenance_kind) do
    "Review workflow provenance #{provenance_kind} for the managed repository."
  end

  defp default_summary(%{kind: :conversation_recall}, [%{origin_summary: origin_summary} | _rest])
       when is_binary(origin_summary) do
    origin_summary
  end

  defp default_summary(%{kind: :conversation_recall}, [%{latest_event: latest_event} | _rest])
       when is_binary(latest_event) do
    "Review conversation-derived origin context for #{String.replace(latest_event, "_", " ")}."
  end

  defp default_summary(%{kind: kind}, selected_items) do
    "Review #{length(selected_items)} #{kind} findings for the managed repository."
  end

  defp default_category(:memories), do: "memory_graph_memory_finding"
  defp default_category(:provenance), do: "memory_graph_provenance_finding"
  defp default_category(:conversation_recall), do: "memory_graph_conversation_recall_finding"

  defp default_priority(_kind, %{state: state}, _items) when state in [:failed, :invalidated], do: :high
  defp default_priority(_kind, %{state: :stale}, _items), do: :medium

  defp default_priority(:memories, _graph, items) do
    if Enum.any?(items, &high_priority_memory?/1), do: :high, else: :medium
  end

  defp default_priority(:provenance, _graph, _items), do: :medium

  defp default_priority(:conversation_recall, _graph, items) do
    if Enum.any?(items, &high_priority_conversation_recall?/1), do: :high, else: :medium
  end

  defp default_urgency(_kind, %{state: state}, _items) when state in [:failed, :invalidated], do: :high
  defp default_urgency(_kind, %{state: :stale}, _items), do: :medium

  defp default_urgency(:memories, _graph, items) do
    if Enum.any?(items, &high_priority_memory?/1), do: :high, else: :medium
  end

  defp default_urgency(:provenance, _graph, _items), do: :medium

  defp default_urgency(:conversation_recall, _graph, items) do
    if Enum.any?(items, &high_priority_conversation_recall?/1), do: :high, else: :medium
  end

  defp default_recommended_action(:memories), do: "review_memory_finding"
  defp default_recommended_action(:provenance), do: "review_provenance_finding"
  defp default_recommended_action(:conversation_recall), do: "review_conversation_follow_up"

  defp high_priority_memory?(%{memory_kind: memory_kind}) when is_binary(memory_kind) do
    memory_kind in ["KnownIssue", "AntiPattern", "OpenQuestion"]
  end

  defp high_priority_memory?(_item), do: false

  defp high_priority_conversation_recall?(%{latest_event: latest_event}) when is_binary(latest_event) do
    latest_event in ["turn_failed", "clarification_requested"]
  end

  defp high_priority_conversation_recall?(_item), do: false

  defp provenance(projection, opts, selected_items) do
    %{
      projection_kind: Map.get(projection, :kind),
      result_count: get_in(projection, [:result_group, :count]) || length(Map.get(projection, :items, [])),
      selected_count: length(selected_items),
      governed_references: selected_governed_references(selected_items),
      conversation_origin: selected_conversation_origin(selected_items),
      query: normalize_map(Keyword.get(opts, :query, %{})),
      requested_by: normalize_map(Keyword.get(opts, :requested_by, %{})),
      feedback: normalize_map(Map.get(projection, :feedback, %{}))
    }
  end

  defp selected_governed_references(selected_items) when is_list(selected_items) do
    selected_items
    |> Enum.flat_map(fn item ->
      item
      |> Map.get(:governed_context, [])
      |> List.wrap()
      |> Enum.map(&normalize_map/1)
    end)
    |> Enum.uniq_by(fn reference ->
      {Map.get(reference, "kind"), Map.get(reference, "id")}
    end)
  end

  defp selected_conversation_origin(selected_items) when is_list(selected_items) do
    selected_items
    |> Enum.flat_map(fn item ->
      case normalize_map(Map.get(item, :conversation_context, %{})) do
        %{} = context when map_size(context) > 0 ->
          [
            %{
              "conversation_id" => context["conversation_id"],
              "turn_id" => context["turn_id"],
              "command_id" => context["command_id"],
              "conversation_event" => context["conversation_event"],
              "scope" => context["scope"],
              "attachment_mode" => context["attachment_mode"],
              "status" => context["status"],
              "source" => context["source"],
              "resource_iris" => normalize_list(Map.get(item, :resource_iris, []))
            }
          ]

        _other ->
          []
      end
    end)
    |> Enum.uniq_by(fn origin ->
      {origin["conversation_id"], origin["turn_id"], origin["command_id"]}
    end)
  end

  defp normalize_list(values) when is_list(values), do: Enum.map(values, &normalize_nested_value/1)
  defp normalize_list(_values), do: []

  defp normalize_graph(graph) when is_map(graph) do
    %{
      graph_name: Map.get(graph, :graph_name, "memory"),
      state: Map.get(graph, :state),
      ready?: Map.get(graph, :ready?, false),
      stale?: Map.get(graph, :stale?, false),
      degraded?: Map.get(graph, :degraded?, false),
      current_revision: Map.get(graph, :current_revision),
      validated_revision: Map.get(graph, :validated_revision),
      latest_failure: normalize_map(Map.get(graph, :latest_failure, %{})),
      recovery_action: Map.get(graph, :recovery_action),
      cross_graph: normalize_map(Map.get(graph, :cross_graph, %{}))
    }
  end

  defp normalize_graph(_graph) do
    %{
      graph_name: "memory",
      state: :not_ready,
      ready?: false,
      stale?: false,
      degraded?: false,
      current_revision: nil,
      validated_revision: nil,
      latest_failure: %{},
      recovery_action: :refresh,
      cross_graph: %{}
    }
  end

  defp digest(payload) do
    payload
    |> Jason.encode!()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      normalized_value =
        cond do
          is_boolean(nested_value) or is_nil(nested_value) -> nested_value
          is_map(nested_value) -> normalize_map(nested_value)
          is_list(nested_value) -> Enum.map(nested_value, &normalize_nested_value/1)
          is_atom(nested_value) -> Atom.to_string(nested_value)
          true -> nested_value
        end

      Map.put(acc, normalized_key, normalized_value)
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_boolean(value) or is_nil(value), do: value
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_nested_value(value), do: value

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
