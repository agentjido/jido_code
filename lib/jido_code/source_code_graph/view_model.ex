defmodule JidoCode.SourceCodeGraph.ViewModel do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  @moduledoc false

  @type graph_state :: map()
  @type projection :: map()

  @spec status(String.t(), map()) :: projection()
  def status(managed_repo_id, status_result) when is_binary(managed_repo_id) and is_map(status_result) do
    %{
      kind: :graph_status,
      managed_repo_id: managed_repo_id,
      graph: graph_state(status_result),
      error: nil
    }
  end

  @spec health(String.t(), map()) :: projection()
  def health(managed_repo_id, health_status) when is_binary(managed_repo_id) and is_map(health_status) do
    %{
      kind: :graph_health,
      managed_repo_id: managed_repo_id,
      health: %{
        summary: health_summary(health_status),
        ready?: Map.get(health_status, :ready?, false),
        stale?: Map.get(health_status, :stale?, true),
        corrupted?: Map.get(health_status, :corrupted?, false),
        last_analysis_at: Map.get(health_status, :last_analysis_at),
        last_analysis_duration_ms: Map.get(health_status, :last_analysis_duration_ms),
        graph_size_bytes: Map.get(health_status, :graph_size_bytes),
        graph_size_mb: size_in_mb(Map.get(health_status, :graph_size_bytes)),
        triple_count: Map.get(health_status, :triple_count),
        file_count: Map.get(health_status, :file_count),
        error_count: Map.get(health_status, :error_count, 0),
        imported_revision: Map.get(health_status, :imported_revision),
        source_commit: Map.get(health_status, :source_commit)
      },
      error: nil
    }
  end

  defp health_summary(health_status) do
    cond do
      Map.get(health_status, :corrupted?, false) -> "corrupted"
      not Map.get(health_status, :ready?, false) -> "not_ready"
      Map.get(health_status, :stale?, true) -> "stale"
      true -> "healthy"
    end
  end

  defp size_in_mb(nil), do: nil
  defp size_in_mb(bytes) when is_integer(bytes), do: div(bytes, 1024 * 1024)

  @spec summary(String.t(), map(), map()) :: projection()
  def summary(managed_repo_id, status_result, groups)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(groups) do
    %{
      kind: :semantic_summary,
      managed_repo_id: managed_repo_id,
      graph: graph_state(status_result),
      groups: groups,
      error: nil
    }
  end

  @spec modules(String.t(), map(), map()) :: projection()
  def modules(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :modules,
      managed_repo_id,
      status_result,
      raw_result,
      Enum.map(Map.get(raw_result, :bindings, []), &module_item/1)
    )
  end

  @spec functions(String.t(), map(), map()) :: projection()
  def functions(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :functions,
      managed_repo_id,
      status_result,
      raw_result,
      Enum.map(Map.get(raw_result, :bindings, []), &function_item/1)
    )
  end

  @spec runtime_patterns(String.t(), map(), map()) :: projection()
  def runtime_patterns(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :runtime_patterns,
      managed_repo_id,
      status_result,
      raw_result,
      Enum.map(Map.get(raw_result, :bindings, []), &runtime_pattern_item/1)
    )
  end

  @spec impact(String.t(), map(), map()) :: projection()
  def impact(managed_repo_id, status_result, raw_result)
      when is_binary(managed_repo_id) and is_map(status_result) and is_map(raw_result) do
    helper_projection(
      :impact,
      managed_repo_id,
      status_result,
      raw_result,
      Enum.map(Map.get(raw_result, :bindings, []), &impact_item/1)
    )
  end

  @spec error(atom(), String.t(), atom(), String.t(), map() | nil) :: projection()
  def error(kind, managed_repo_id, reason, detail, status_result \\ nil)
      when is_atom(kind) and is_binary(managed_repo_id) and is_atom(reason) and is_binary(detail) do
    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: graph_state(status_result, reason),
      error: %{
        type: reason,
        detail: detail,
        recovery_action: graph_recovery_action(status_result, reason)
      }
    }
  end

  @spec summary_group(map() | nil, (map() -> projection())) :: map()
  def summary_group(nil, _builder), do: %{status: :unavailable, count: 0, items: []}

  def summary_group(raw_result, builder) when is_map(raw_result) and is_function(builder, 1) do
    projection = builder.(raw_result)

    %{
      status: :ok,
      count: projection.result_group.count,
      items: projection.items,
      degraded?: projection.result_group.degraded?,
      stale?: projection.result_group.stale?
    }
  end

  defp helper_projection(kind, managed_repo_id, status_result, raw_result, items) do
    graph = graph_state(status_result, raw_result)

    %{
      kind: kind,
      managed_repo_id: managed_repo_id,
      graph: graph,
      items: items,
      result_group: %{
        helper: kind,
        count: Map.get(raw_result, :row_count, length(items)),
        empty?: Map.get(raw_result, :empty?, items == []),
        degraded?: Map.get(raw_result, :degraded?, false),
        stale?: Map.get(raw_result, :stale_graph?, false)
      },
      error: nil
    }
  end

  defp graph_state(status_result, raw_result_or_reason \\ nil)

  defp graph_state(nil, reason) when is_atom(reason) do
    %{
      graph_name: "source_code",
      ready?: false,
      stale?: reason == :source_code_graph_stale,
      degraded?: false,
      state: graph_state_name(false, reason == :source_code_graph_stale, false, reason),
      imported_revision: nil,
      current_revision: nil,
      latest_failure: nil,
      refresh: refresh_state(nil),
      recovery_action: graph_recovery_action(nil, reason)
    }
  end

  defp graph_state(%{} = status_result, raw_result_or_reason) do
    degraded? =
      case raw_result_or_reason do
        raw when is_map(raw) -> Map.get(raw, :degraded?, false)
        _ -> false
      end

    stale? =
      case raw_result_or_reason do
        raw when is_map(raw) -> Map.get(raw, :stale_graph?, Map.get(status_result, :stale?, false))
        :source_code_graph_stale -> true
        _ -> Map.get(status_result, :stale?, false)
      end

    ready? = Map.get(status_result, :ready?, false)
    latest_failure = Map.get(status_result, :latest_failure)
    reason = if latest_failure, do: Map.get(latest_failure, :kind), else: nil

    %{
      graph_name: Map.get(status_result, :graph_name, "source_code"),
      ready?: ready?,
      stale?: stale?,
      degraded?: degraded?,
      state: graph_state_name(ready?, stale?, degraded?, reason),
      imported_revision: Map.get(status_result, :imported_revision),
      current_revision: Map.get(status_result, :current_revision),
      latest_failure: normalize_failure(latest_failure),
      refresh: refresh_state(Map.get(status_result, :source_graph_refresh)),
      recovery_action: graph_recovery_action(status_result, reason)
    }
  end

  defp graph_state_name(_ready?, _stale?, _degraded?, :source_code_graph_disabled), do: :disabled
  defp graph_state_name(_ready?, _stale?, _degraded?, reason) when not is_nil(reason), do: :failed
  defp graph_state_name(_ready?, _stale?, true, _reason), do: :degraded
  defp graph_state_name(true, true, _degraded?, _reason), do: :stale
  defp graph_state_name(true, false, false, _reason), do: :ready
  defp graph_state_name(false, true, _degraded?, _reason), do: :stale
  defp graph_state_name(false, false, false, _reason), do: :not_ready

  defp graph_recovery_action(nil, :source_code_graph_disabled), do: :none
  defp graph_recovery_action(nil, :source_code_graph_stale), do: :refresh
  defp graph_recovery_action(nil, _reason), do: :load

  defp graph_recovery_action(status_result, _reason) do
    cond do
      latest_failure = Map.get(status_result, :latest_failure) ->
        failure_kind = Map.get(latest_failure, :kind)

        if failure_kind in [nil, ""] do
          :recover
        else
          :recover
        end

      Map.get(status_result, :stale?, false) ->
        :refresh

      Map.get(status_result, :ready?, false) ->
        :none

      true ->
        :load
    end
  end

  defp module_item(binding) do
    %{
      module_iri: value(binding, "module"),
      module_name: value(binding, "module_name") || compact_name(value(binding, "module"))
    }
  end

  defp function_item(binding) do
    %{
      function_iri: value(binding, "function"),
      module_iri: value(binding, "module"),
      module_name: value(binding, "module_name") || compact_name(value(binding, "module")),
      function_name: value(binding, "function_name") || compact_name(value(binding, "function")),
      arity: numeric_value(binding, "arity")
    }
  end

  defp runtime_pattern_item(binding) do
    pattern_iri = value(binding, "pattern")

    %{
      subject_iri: value(binding, "subject"),
      pattern_iri: pattern_iri,
      pattern_name: compact_name(pattern_iri)
    }
  end

  defp impact_item(binding) do
    %{
      source_iri: value(binding, "source"),
      predicate_iri: value(binding, "predicate"),
      predicate_name: compact_name(value(binding, "predicate")),
      target_iri: value(binding, "target")
    }
  end

  defp value(binding, key) when is_map(binding) do
    binding
    |> Map.get(key, %{})
    |> case do
      %{value: value} -> value
      %{"value" => value} -> value
      _ -> nil
    end
  end

  defp numeric_value(binding, key) do
    case value(binding, key) do
      value when is_integer(value) ->
        value

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} -> int
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp compact_name(nil), do: nil

  defp compact_name(value) when is_binary(value) do
    value
    |> String.split(["#", "/"])
    |> List.last()
    |> case do
      "" -> value
      compact -> compact
    end
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

  defp refresh_state(nil) do
    refresh_state(%{})
  end

  defp refresh_state(refresh) when is_map(refresh) do
    %{
      state: map_get(refresh, :state, "state", :idle),
      auto_refresh_enabled?: map_get(refresh, :auto_refresh_enabled?, "auto_refresh_enabled?", false),
      file_watcher_enabled?: map_get(refresh, :file_watcher_enabled?, "file_watcher_enabled?", false),
      file_watcher_debounce_ms: map_get(refresh, :file_watcher_debounce_ms, "file_watcher_debounce_ms"),
      file_watcher_max_pending_paths:
        map_get(refresh, :file_watcher_max_pending_paths, "file_watcher_max_pending_paths"),
      refresh_debounce_ms: map_get(refresh, :refresh_debounce_ms, "refresh_debounce_ms"),
      refresh_max_coalesce_ms: map_get(refresh, :refresh_max_coalesce_ms, "refresh_max_coalesce_ms"),
      refresh_max_pending_paths: map_get(refresh, :refresh_max_pending_paths, "refresh_max_pending_paths"),
      missing_graph_policy: map_get(refresh, :missing_graph_policy, "missing_graph_policy", :skip),
      max_refresh_attempts: map_get(refresh, :max_refresh_attempts, "max_refresh_attempts"),
      refresh_queued?: map_get(refresh, :refresh_queued?, "refresh_queued?", false),
      refresh_in_flight?: map_get(refresh, :refresh_in_flight?, "refresh_in_flight?", false),
      pending_changed_paths: map_get(refresh, :pending_changed_paths, "pending_changed_paths", []),
      last_source_change_at: map_get(refresh, :last_source_change_at, "last_source_change_at"),
      last_refresh_started_at: map_get(refresh, :last_refresh_started_at, "last_refresh_started_at"),
      last_refresh_completed_at: map_get(refresh, :last_refresh_completed_at, "last_refresh_completed_at"),
      last_result: map_get(refresh, :last_result, "last_result"),
      last_failure: map_get(refresh, :last_failure, "last_failure")
    }
  end

  defp map_get(map, atom_key, string_key, default \\ nil) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end
end
