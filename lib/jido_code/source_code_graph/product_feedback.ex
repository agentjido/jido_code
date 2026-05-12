defmodule JidoCode.SourceCodeGraph.ProductFeedback do
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  @moduledoc false

  @default_graph %{
    graph_name: "source_code",
    ready?: false,
    stale?: false,
    degraded?: false,
    state: :unavailable,
    imported_revision: nil,
    current_revision: nil,
    latest_failure: nil,
    refresh: %{},
    recovery_action: :none
  }

  @spec normalize_graph(map() | nil, atom() | nil) :: map()
  def normalize_graph(graph, reason \\ nil)

  def normalize_graph(nil, reason) do
    @default_graph
    |> Map.put(:stale?, reason == :source_code_graph_stale)
    |> Map.put(:state, fallback_state(reason))
    |> Map.put(:recovery_action, fallback_recovery_action(reason))
  end

  def normalize_graph(graph, _reason) when is_map(graph) do
    %{
      graph_name: Map.get(graph, :graph_name, "source_code"),
      ready?: Map.get(graph, :ready?, false),
      stale?: Map.get(graph, :stale?, false),
      degraded?: Map.get(graph, :degraded?, false),
      state: Map.get(graph, :state, :unavailable),
      imported_revision: Map.get(graph, :imported_revision),
      current_revision: Map.get(graph, :current_revision),
      latest_failure: normalize_failure(Map.get(graph, :latest_failure)),
      refresh: Map.get(graph, :refresh, %{}),
      recovery_action: Map.get(graph, :recovery_action, :none)
    }
  end

  @spec for_graph(map() | nil, map() | nil) :: map()
  def for_graph(graph, error \\ nil) do
    normalized_graph = normalize_graph(graph)

    %{
      state: Map.get(normalized_graph, :state, :unavailable),
      ready?: Map.get(normalized_graph, :ready?, false),
      stale?: Map.get(normalized_graph, :stale?, false),
      degraded?: Map.get(normalized_graph, :degraded?, false),
      label: state_label(normalized_graph),
      error_type: error_type(error, normalized_graph),
      detail: detail(normalized_graph, error),
      remediation: remediation(normalized_graph),
      recovery: recovery(normalized_graph),
      imported_revision: Map.get(normalized_graph, :imported_revision),
      current_revision: Map.get(normalized_graph, :current_revision)
    }
  end

  @spec fallback_graph(atom() | nil) :: map()
  def fallback_graph(reason), do: normalize_graph(nil, reason)

  @spec notice_kind(map() | nil) :: atom()
  def notice_kind(graph) do
    case normalize_graph(graph) do
      %{state: :failed} -> :error
      _other -> :warning
    end
  end

  @spec recovery(map() | nil) :: map()
  def recovery(graph) do
    normalized_graph = normalize_graph(graph)
    action = Map.get(normalized_graph, :recovery_action, :none)

    %{
      action: action,
      available?: action != :none,
      label: recovery_label(action)
    }
  end

  @spec state_label(map() | nil) :: String.t()
  def state_label(graph) do
    case normalize_graph(graph) do
      %{state: :ready} -> "Semantic graph ready"
      %{state: :not_ready} -> "Semantic graph not loaded"
      %{state: :stale} -> "Semantic graph stale"
      %{state: :degraded} -> "Semantic graph degraded"
      %{state: :failed} -> "Semantic graph failed"
      %{state: :disabled} -> "Semantic graph disabled"
      _other -> "Semantic graph unavailable"
    end
  end

  @spec recovery_label(atom()) :: String.t() | nil
  def recovery_label(:load), do: "Load semantic graph"
  def recovery_label(:refresh), do: "Refresh semantic graph"
  def recovery_label(:recover), do: "Recover semantic graph"
  def recovery_label(:none), do: nil
  def recovery_label(_action), do: "Recover semantic graph"

  defp detail(%{state: :stale}, %{detail: detail}) when is_binary(detail), do: detail
  defp detail(_graph, %{detail: detail}) when is_binary(detail), do: detail
  defp detail(%{state: :ready}, _error), do: "Semantic source-code graph is ready for inspection."

  defp detail(%{state: :failed, latest_failure: %{message: message}}, _error) when is_binary(message),
    do: message

  defp detail(%{state: :disabled}, _error),
    do: "Semantic source-code graph capability is disabled for this repository."

  defp detail(%{state: :not_ready}, _error), do: "Semantic source-code graph data has not been loaded yet."
  defp detail(%{state: :stale}, _error), do: "Semantic source-code graph data is stale and should be refreshed."

  defp detail(%{state: :degraded}, _error),
    do: "Semantic source-code graph data is available in degraded mode while the repository revision is stale."

  defp detail(%{state: :failed}, _error), do: "Semantic source-code graph refresh failed and needs recovery."
  defp detail(%{state: :unavailable}, _error), do: "Semantic repository state is unavailable."
  defp detail(_graph, _error), do: "Semantic repository state is unavailable."

  defp remediation(%{recovery_action: :none}), do: nil
  defp remediation(%{recovery_action: :load}), do: "Open repo detail to load semantic graph data."
  defp remediation(%{recovery_action: :refresh}), do: "Open repo detail to refresh semantic graph data."
  defp remediation(%{recovery_action: :recover}), do: "Open repo detail to recover semantic graph state."
  defp remediation(_graph), do: nil

  defp error_type(error, graph) do
    case normalize_optional_string(map_get(error, :type, "type")) do
      nil -> graph_error_type(graph)
      type -> type
    end
  end

  defp graph_error_type(%{state: :disabled}), do: "source_code_graph_disabled"
  defp graph_error_type(%{state: :not_ready}), do: "source_code_graph_not_ready"
  defp graph_error_type(%{state: :stale}), do: "source_code_graph_stale"
  defp graph_error_type(%{state: :degraded}), do: "source_code_graph_degraded"
  defp graph_error_type(%{state: :failed}), do: "source_code_graph_failed"
  defp graph_error_type(_graph), do: "source_code_graph_unavailable"

  defp fallback_state(:source_code_graph_disabled), do: :disabled
  defp fallback_state(:source_code_graph_not_ready), do: :not_ready
  defp fallback_state(:source_code_graph_stale), do: :stale
  defp fallback_state(_reason), do: :unavailable

  defp fallback_recovery_action(:source_code_graph_disabled), do: :none
  defp fallback_recovery_action(:source_code_graph_stale), do: :refresh
  defp fallback_recovery_action(:source_code_graph_not_ready), do: :load
  defp fallback_recovery_action(_reason), do: :none

  defp normalize_failure(nil), do: nil

  defp normalize_failure(failure) when is_map(failure) do
    %{
      kind: map_get(failure, :kind, "kind"),
      operation: map_get(failure, :operation, "operation"),
      stage: map_get(failure, :stage, "stage"),
      message: map_get(failure, :message, "message")
    }
  end

  defp map_get(map, atom_key, string_key) when is_map(map) do
    Map.get(map, atom_key) || Map.get(map, string_key)
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

  defp normalize_optional_string(nil), do: nil

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
