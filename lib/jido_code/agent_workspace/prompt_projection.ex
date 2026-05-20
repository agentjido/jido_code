defmodule JidoCode.AgentWorkspace.PromptProjection do
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_context
  @moduledoc """
  Compact prompt-facing projections for AgentWorkspace graph context.

  Structured semantic and memory contexts remain available through
  `tool_context`; this module only shapes bounded text for LLM instructions.
  """

  @default_max_items 6
  @default_max_item_bytes 600

  @type projection :: %{
          lines: [String.t()],
          diagnostics: map(),
          state: :empty | :projected | :trimmed
        }

  @spec semantic(map() | nil, keyword() | map()) :: projection()
  def semantic(context, opts \\ [])

  def semantic(nil, _opts), do: empty_projection(:semantic_context)
  def semantic(%{} = context, _opts) when map_size(context) == 0, do: empty_projection(:semantic_context)

  def semantic(%{} = context, opts) do
    opts = normalize_opts(opts)
    max_items = positive_integer(Map.get(opts, :max_items), @default_max_items)
    max_item_bytes = positive_integer(Map.get(opts, :max_item_bytes), @default_max_item_bytes)

    graph_status = normalize_map(Map.get(context, :graph_status, Map.get(context, "graph_status", %{})))
    results = normalize_map(Map.get(context, :results, Map.get(context, "results", %{})))

    base_lines =
      []
      |> maybe_add_line("workflow", string_value(Map.get(context, :workflow, Map.get(context, "workflow"))))
      |> maybe_add_line("graph_ready?", string_value(Map.get(graph_status, "ready?")))
      |> maybe_add_line("graph_stale?", string_value(Map.get(graph_status, "stale?")))
      |> maybe_add_line("graph_revision", string_value(Map.get(graph_status, "current_revision")))
      |> maybe_add_line("graph_failure", graph_failure(graph_status, max_item_bytes))

    result_lines =
      results
      |> Enum.sort_by(fn {kind, _value} -> kind end)
      |> Enum.map(fn {kind, value} ->
        "#{kind}: #{bounded_text(summarize_value(value), max_item_bytes)}"
      end)
      |> Enum.take(max_items)

    original_count = map_size(results)
    dropped = max(original_count - length(result_lines), 0)
    lines = base_lines ++ result_lines

    projection(:semantic_context, lines, original_count, length(result_lines), dropped)
  end

  def semantic(_context, _opts), do: empty_projection(:semantic_context)

  @spec memory(map() | nil, keyword() | map()) :: projection()
  def memory(context, opts \\ [])

  def memory(nil, _opts), do: empty_projection(:memory_context)
  def memory(%{} = context, _opts) when map_size(context) == 0, do: empty_projection(:memory_context)

  def memory(%{} = context, opts) do
    opts = normalize_opts(opts)
    max_items = positive_integer(Map.get(opts, :max_items), @default_max_items)
    max_item_bytes = positive_integer(Map.get(opts, :max_item_bytes), @default_max_item_bytes)

    graph = normalize_map(Map.get(context, :graph, Map.get(context, "graph", %{})))
    freshness = normalize_map(Map.get(context, :freshness, Map.get(context, "freshness", %{})))
    policy = normalize_map(Map.get(context, :policy, Map.get(context, "policy", %{})))
    selection = normalize_map(Map.get(context, :selection, Map.get(context, "selection", %{})))

    base_lines =
      []
      |> maybe_add_line("workflow", string_value(Map.get(context, :workflow, Map.get(context, "workflow"))))
      |> maybe_add_line("graph_ready?", string_value(Map.get(graph, "ready?")))
      |> maybe_add_line("graph_stale?", string_value(Map.get(graph, "stale?")))
      |> maybe_add_line("graph_revision", string_value(Map.get(graph, "current_revision")))
      |> maybe_add_line("freshness", string_value(Map.get(freshness, "label", Map.get(freshness, "state"))))
      |> maybe_add_line("policy_intent", string_value(Map.get(policy, "intent")))
      |> maybe_add_line("follow_up_intent", string_value(Map.get(policy, "follow_up_intent")))

    selected_lines = selected_memory_lines(selection, max_items, max_item_bytes)
    lines = base_lines ++ selected_lines.lines

    projection(
      :memory_context,
      lines,
      selected_lines.original_count,
      selected_lines.packed_count,
      selected_lines.dropped_count
    )
  end

  def memory(_context, _opts), do: empty_projection(:memory_context)

  defp selected_memory_lines(selection, max_items, max_item_bytes) do
    selected_items = normalize_map(Map.get(selection, "selected_items", %{}))
    memories = normalize_list(Map.get(selected_items, "memories"))
    provenance = normalize_list(Map.get(selected_items, "provenance"))
    governed_references = normalize_list(Map.get(selection, "governed_references"))

    entries =
      []
      |> Kernel.++(Enum.map(memories, &selected_item_line("memory", &1, max_item_bytes)))
      |> Kernel.++(Enum.map(provenance, &selected_item_line("provenance", &1, max_item_bytes)))
      |> Kernel.++(Enum.map(governed_references, &selected_item_line("governed_reference", &1, max_item_bytes)))

    lines = Enum.take(entries, max_items)

    %{
      lines: lines,
      original_count: length(entries),
      packed_count: length(lines),
      dropped_count: max(length(entries) - length(lines), 0)
    }
  end

  defp selected_item_line(prefix, %{} = item, max_item_bytes) do
    kind =
      item
      |> Map.get("memory_kind", Map.get(item, "provenance_kind", Map.get(item, "kind")))
      |> string_value()

    content =
      item
      |> Map.get("content", Map.get(item, "label", Map.get(item, "id", summarize_value(item))))
      |> summarize_value()
      |> bounded_text(max_item_bytes)

    [prefix, kind, content]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(": ")
  end

  defp selected_item_line(prefix, item, max_item_bytes) do
    "#{prefix}: #{bounded_text(summarize_value(item), max_item_bytes)}"
  end

  defp projection(kind, lines, original_count, packed_count, dropped_count) do
    state =
      cond do
        lines == [] -> :empty
        dropped_count > 0 -> :trimmed
        true -> :projected
      end

    %{
      state: state,
      lines: lines,
      diagnostics: %{
        kind: kind,
        state: state,
        original_items: original_count,
        packed_items: packed_count,
        dropped_items: dropped_count
      }
    }
  end

  defp empty_projection(kind) do
    %{
      state: :empty,
      lines: [],
      diagnostics: %{kind: kind, state: :empty, original_items: 0, packed_items: 0, dropped_items: 0}
    }
  end

  defp graph_failure(graph_status, max_item_bytes) do
    case Map.get(graph_status, "latest_failure") do
      nil -> nil
      failure -> bounded_text(summarize_value(failure), max_item_bytes)
    end
  end

  defp summarize_value(value) when is_binary(value), do: value
  defp summarize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp summarize_value(value) when is_integer(value) or is_float(value) or is_boolean(value), do: to_string(value)
  defp summarize_value(nil), do: nil
  defp summarize_value(value), do: inspect(value, pretty: true, limit: 10)

  defp bounded_text(nil, _max_bytes), do: nil

  defp bounded_text(text, max_bytes) when is_binary(text) and byte_size(text) > max_bytes do
    text
    |> String.slice(0, max_bytes)
    |> Kernel.<>("\n... (projection item truncated)")
  end

  defp bounded_text(text, _max_bytes), do: text

  defp maybe_add_line(lines, _label, nil), do: lines
  defp maybe_add_line(lines, label, value), do: lines ++ ["#{label}: #{value}"]

  defp string_value(nil), do: nil
  defp string_value(value) when is_binary(value), do: value
  defp string_value(value) when is_atom(value), do: Atom.to_string(value)
  defp string_value(value), do: to_string(value)

  defp normalize_list(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_list(_value), do: []

  defp normalize_map(%{} = map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_key(key), normalize_value(value))
    end)
  end

  defp normalize_map(_map), do: %{}

  defp normalize_value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp normalize_value(%{} = value), do: normalize_map(value)
  defp normalize_value(value) when is_list(value), do: Enum.map(value, &normalize_value/1)
  defp normalize_value(nil), do: nil
  defp normalize_value(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_value(value), do: value

  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: to_string(key)

  defp normalize_opts(nil), do: %{}
  defp normalize_opts(opts) when is_list(opts), do: Enum.into(opts, %{})
  defp normalize_opts(%{} = opts), do: opts
  defp normalize_opts(_opts), do: %{}

  defp positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_integer(_value, default), do: default
end
