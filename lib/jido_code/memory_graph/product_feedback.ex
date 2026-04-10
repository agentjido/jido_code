defmodule JidoCode.MemoryGraph.ProductFeedback do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
  @moduledoc false

  @default_graph %{
    graph_name: "memory",
    ready?: false,
    stale?: false,
    degraded?: false,
    queryable_when_stale?: false,
    state: :unavailable,
    current_revision: nil,
    validated_revision: nil,
    latest_failure: nil,
    recovery_action: :none,
    cross_graph: %{consistency: %{state: :unknown, explainable?: true}}
  }

  @spec normalize_graph(map() | nil, atom() | nil) :: map()
  def normalize_graph(graph, reason \\ nil)

  def normalize_graph(nil, reason) do
    @default_graph
    |> Map.put(:stale?, reason == :memory_graph_stale)
    |> Map.put(:state, fallback_state(reason))
    |> Map.put(:recovery_action, fallback_recovery_action(reason))
  end

  def normalize_graph(graph, _reason) when is_map(graph) do
    latest_validation_status = Map.get(graph, :latest_validation_status, %{})
    latest_failure = normalize_failure(Map.get(graph, :latest_failure))
    stale? = Map.get(graph, :stale?, false)
    degraded? = Map.get(graph, :degraded?, false)

    %{
      graph_name: Map.get(graph, :graph_name, "memory"),
      ready?: Map.get(graph, :ready?, false),
      stale?: stale?,
      degraded?: degraded?,
      queryable_when_stale?: Map.get(graph, :queryable_when_stale?, false),
      state:
        Map.get(
          graph,
          :state,
          graph_state(
            Map.get(graph, :ready?, false),
            stale?,
            degraded?,
            latest_failure,
            Map.get(latest_validation_status, :state)
          )
        ),
      current_revision: Map.get(graph, :current_revision),
      validated_revision: Map.get(graph, :validated_revision),
      latest_failure: latest_failure,
      recovery_action:
        Map.get(
          graph,
          :recovery_action,
          graph_recovery_action(
            Map.get(graph, :ready?, false),
            stale?,
            latest_failure,
            Map.get(latest_validation_status, :state)
          )
        ),
      cross_graph: normalize_cross_graph(Map.get(graph, :cross_graph))
    }
  end

  @spec for_graph(map() | nil, map() | nil) :: map()
  def for_graph(graph, error \\ nil) do
    normalized_graph = normalize_graph(graph)

    %{
      state: normalized_graph.state,
      ready?: normalized_graph.ready?,
      stale?: normalized_graph.stale?,
      degraded?: normalized_graph.degraded?,
      label: state_label(normalized_graph),
      error_type: error_type(error, normalized_graph),
      detail: detail(normalized_graph, error),
      remediation: remediation(normalized_graph),
      recovery: recovery(normalized_graph),
      current_revision: normalized_graph.current_revision,
      validated_revision: normalized_graph.validated_revision,
      cross_graph: normalized_graph.cross_graph
    }
  end

  @spec fallback_graph(atom() | nil) :: map()
  def fallback_graph(reason), do: normalize_graph(nil, reason)

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
      %{state: :ready} -> "Memory graph ready"
      %{state: :not_ready} -> "Memory graph not ready"
      %{state: :invalidated} -> "Memory graph invalidated"
      %{state: :stale} -> "Memory graph stale"
      %{state: :degraded} -> "Memory graph degraded"
      %{state: :failed} -> "Memory graph failed"
      %{state: :disabled} -> "Memory graph disabled"
      _other -> "Memory graph unavailable"
    end
  end

  @spec recovery_label(atom()) :: String.t() | nil
  def recovery_label(:refresh), do: "Refresh memory graph"
  def recovery_label(:validate), do: "Validate memory graph"
  def recovery_label(:recover), do: "Recover memory graph"
  def recovery_label(:none), do: nil
  def recovery_label(_action), do: "Recover memory graph"

  defp detail(%{state: :ready, cross_graph: %{consistency: %{state: :aligned}}}, _error) do
    "Repository memory is ready for bounded recall and capture."
  end

  defp detail(%{state: :ready, cross_graph: %{consistency: %{state: :source_code_stale}}}, _error) do
    "Repository memory is ready, but linked source-code graph state is stale."
  end

  defp detail(%{state: :ready, cross_graph: %{consistency: %{state: :source_code_unavailable}}}, _error) do
    "Repository memory is ready, but linked source-code graph state is unavailable."
  end

  defp detail(%{state: :failed, latest_failure: %{message: message}}, _error) when is_binary(message),
    do: message

  defp detail(%{state: :disabled}, _error),
    do: "Repository memory graph capability is disabled for this repository."

  defp detail(%{state: :not_ready}, _error),
    do: "Repository memory graph data has not been prepared yet."

  defp detail(%{state: :invalidated}, _error),
    do: "Repository memory graph validation was explicitly invalidated and should be revalidated."

  defp detail(%{state: :stale}, _error),
    do: "Repository memory graph validation is stale for the requested revision."

  defp detail(%{state: :degraded}, _error),
    do: "Repository memory graph is operating in a bounded degraded mode."

  defp detail(%{state: :failed}, _error),
    do: "Repository memory graph recovery is required before normal use."

  defp detail(_graph, %{detail: detail}) when is_binary(detail), do: detail
  defp detail(_graph, %{reason: reason}) when is_binary(reason), do: reason
  defp detail(_graph, _error), do: "Repository memory state is unavailable."

  defp remediation(%{recovery_action: :none}), do: nil
  defp remediation(%{recovery_action: :refresh}), do: "Refresh repository memory graph state."
  defp remediation(%{recovery_action: :validate}), do: "Validate repository memory graph for the current revision."
  defp remediation(%{recovery_action: :recover}), do: "Recover repository memory graph state."
  defp remediation(_graph), do: nil

  defp error_type(%{type: type}, _graph) when is_atom(type), do: Atom.to_string(type)
  defp error_type(%{type: type}, _graph) when is_binary(type), do: type
  defp error_type(_error, %{state: :disabled}), do: "memory_graph_disabled"
  defp error_type(_error, %{state: :not_ready}), do: "memory_graph_not_ready"
  defp error_type(_error, %{state: :invalidated}), do: "memory_graph_invalidated"
  defp error_type(_error, %{state: :stale}), do: "memory_graph_stale"
  defp error_type(_error, %{state: :degraded}), do: "memory_graph_degraded"
  defp error_type(_error, %{state: :failed}), do: "memory_graph_failed"
  defp error_type(_error, _graph), do: "memory_graph_unavailable"

  defp fallback_state(:memory_graph_disabled), do: :disabled
  defp fallback_state(:memory_graph_stale), do: :stale
  defp fallback_state(:memory_graph_invalidated), do: :invalidated
  defp fallback_state(:memory_graph_not_ready), do: :not_ready
  defp fallback_state(_reason), do: :unavailable

  defp fallback_recovery_action(:memory_graph_disabled), do: :none
  defp fallback_recovery_action(:memory_graph_stale), do: :validate
  defp fallback_recovery_action(:memory_graph_invalidated), do: :validate
  defp fallback_recovery_action(:memory_graph_not_ready), do: :refresh
  defp fallback_recovery_action(_reason), do: :none

  defp graph_state(_ready?, _stale?, _degraded?, latest_failure, _validation_state)
       when not is_nil(latest_failure),
       do: :failed

  defp graph_state(_ready?, _stale?, _degraded?, _latest_failure, :invalidated), do: :invalidated
  defp graph_state(_ready?, _stale?, true, _latest_failure, _validation_state), do: :degraded
  defp graph_state(true, true, _degraded?, _latest_failure, _validation_state), do: :stale
  defp graph_state(true, false, false, _latest_failure, _validation_state), do: :ready
  defp graph_state(false, true, _degraded?, _latest_failure, _validation_state), do: :stale
  defp graph_state(false, false, false, _latest_failure, _validation_state), do: :not_ready

  defp graph_recovery_action(_ready?, _stale?, latest_failure, _validation_state)
       when not is_nil(latest_failure),
       do: :recover

  defp graph_recovery_action(_ready?, _stale?, _latest_failure, :invalidated), do: :validate
  defp graph_recovery_action(true, true, _latest_failure, _validation_state), do: :validate
  defp graph_recovery_action(false, _stale?, _latest_failure, _validation_state), do: :refresh
  defp graph_recovery_action(true, false, _latest_failure, _validation_state), do: :none

  defp normalize_cross_graph(nil), do: %{consistency: %{state: :unknown, explainable?: true}}

  defp normalize_cross_graph(cross_graph) when is_map(cross_graph) do
    %{
      source_code: Map.get(cross_graph, :source_code),
      workflow_provenance: Map.get(cross_graph, :workflow_provenance),
      consistency: Map.get(cross_graph, :consistency, %{state: :unknown, explainable?: true})
    }
  end

  defp normalize_failure(nil), do: nil

  defp normalize_failure(failure) when is_map(failure) do
    %{
      kind: Map.get(failure, :kind) || Map.get(failure, "kind"),
      operation: Map.get(failure, :operation) || Map.get(failure, "operation"),
      stage: Map.get(failure, :stage) || Map.get(failure, "stage"),
      message: Map.get(failure, :message) || Map.get(failure, "message")
    }
  end
end
