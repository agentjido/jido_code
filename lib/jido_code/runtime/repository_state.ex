defmodule JidoCode.Runtime.RepositoryState do
  @moduledoc """
  State model for one repository runtime container.
  """

  @type managed_repo_id :: String.t()
  @type lifecycle :: :starting | :ready | :degraded | :stopping | :stopped
  @type work_item_id :: String.t()

  @type work_item_state :: %{
          work_item_id: work_item_id(),
          workspace_path: String.t() | nil,
          admitted_at: DateTime.t(),
          coding_pod: term(),
          context_management_pod: term(),
          lifecycle: :admitted | :running | :completed | :failed,
          diagnostics: [map()]
        }

  @type t :: %__MODULE__{
          managed_repo_id: managed_repo_id(),
          workspace_path: String.t() | nil,
          lifecycle: lifecycle(),
          active_pods: map(),
          active_work_items: %{optional(work_item_id()) => work_item_state()},
          capacity: map(),
          diagnostics: [map()],
          monitors: map(),
          started_at: DateTime.t(),
          last_activity_at: DateTime.t(),
          last_failure_at: DateTime.t() | nil
        }

  defstruct managed_repo_id: nil,
            workspace_path: nil,
            lifecycle: :starting,
            active_pods: %{},
            active_work_items: %{},
            capacity: %{max_active_work_items: :infinity},
            diagnostics: [],
            monitors: %{},
            started_at: nil,
            last_activity_at: nil,
            last_failure_at: nil

  @spec new(keyword()) :: t()
  def new(opts) when is_list(opts) do
    now = DateTime.utc_now()

    %__MODULE__{
      managed_repo_id: Keyword.fetch!(opts, :managed_repo_id),
      workspace_path: Keyword.get(opts, :workspace_path),
      lifecycle: :ready,
      capacity: normalize_capacity(Keyword.get(opts, :capacity, %{})),
      started_at: now,
      last_activity_at: now
    }
  end

  @spec status(t()) :: map()
  def status(%__MODULE__{} = state) do
    state
    |> Map.from_struct()
    |> Map.delete(:monitors)
  end

  @spec put_pod(t(), atom(), term(), module(), pid(), map()) :: t()
  def put_pod(%__MODULE__{} = state, kind, key, module, pid, attrs \\ %{})
      when is_atom(kind) and is_atom(module) and is_pid(pid) and is_map(attrs) do
    monitor_key = {:pod, kind, key}
    {monitors, registered_at} = monitor_pod(state, monitor_key, pid)
    existing_status = Map.get(state.active_pods, monitor_key)
    metadata = merged_metadata(existing_status, Map.get(attrs, :metadata, %{}))
    now = DateTime.utc_now()

    pod_status = %{
      pod_id: Map.fetch!(attrs, :pod_id),
      kind: kind,
      key: key,
      module: module,
      scope: Map.get(attrs, :scope, :repository),
      metadata: metadata,
      runtime_pid: pid,
      lifecycle: :running,
      nodes: %{},
      diagnostics: [],
      registered_at: registered_at,
      started_at: Map.get(existing_status || %{}, :started_at, now),
      last_activity_at: now
    }

    %{
      state
      | active_pods: Map.put(state.active_pods, monitor_key, pod_status),
        monitors: monitors,
        last_activity_at: now
    }
  end

  @spec delete_pod(t(), atom(), term()) :: t()
  def delete_pod(%__MODULE__{} = state, kind, key) when is_atom(kind) do
    monitor_key = {:pod, kind, key}

    case Map.pop(state.monitors, monitor_key) do
      {nil, monitors} ->
        %{state | active_pods: Map.delete(state.active_pods, monitor_key), monitors: monitors}

      {ref, monitors} ->
        Process.demonitor(ref, [:flush])
        %{state | active_pods: Map.delete(state.active_pods, monitor_key), monitors: monitors}
    end
  end

  @spec pod_status(t(), atom(), term()) :: map() | nil
  def pod_status(%__MODULE__{} = state, kind, key) do
    Map.get(state.active_pods, {:pod, kind, key})
  end

  @spec pod_status_by_id(t(), String.t()) :: map() | nil
  def pod_status_by_id(%__MODULE__{} = state, pod_id) when is_binary(pod_id) do
    state.active_pods
    |> Map.values()
    |> Enum.find(&(Map.get(&1, :pod_id) == pod_id))
  end

  @spec list_pods(t()) :: [map()]
  def list_pods(%__MODULE__{} = state) do
    state.active_pods
    |> Map.values()
    |> Enum.sort_by(& &1.pod_id)
  end

  @spec update_pod_metadata(t(), String.t(), map()) :: {:ok, map(), t()} | {:error, term()}
  def update_pod_metadata(%__MODULE__{} = state, pod_id, updates)
      when is_binary(pod_id) and is_map(updates) do
    case find_pod_key(state, pod_id) do
      nil ->
        {:error, :pod_not_found}

      monitor_key ->
        pod_status = Map.fetch!(state.active_pods, monitor_key)
        metadata = merged_metadata(pod_status, updates)
        next_pod_status = %{pod_status | metadata: metadata, last_activity_at: DateTime.utc_now()}
        next_state = %{state | active_pods: Map.put(state.active_pods, monitor_key, next_pod_status)}
        {:ok, next_pod_status, touch(next_state)}
    end
  end

  @spec ensure_workspace(t(), String.t() | nil) :: {:ok, t()} | {:error, term()}
  def ensure_workspace(%__MODULE__{workspace_path: nil} = state, workspace_path) do
    {:ok, %{state | workspace_path: workspace_path, last_activity_at: DateTime.utc_now()}}
  end

  def ensure_workspace(%__MODULE__{workspace_path: workspace_path} = state, workspace_path) do
    {:ok, %{state | last_activity_at: DateTime.utc_now()}}
  end

  def ensure_workspace(%__MODULE__{} = state, requested_workspace_path) do
    {:error,
     %{
       type: :workspace_mismatch,
       existing_workspace_path: state.workspace_path,
       requested_workspace_path: requested_workspace_path
     }}
  end

  @spec admit_work_item(t(), work_item_id(), map()) :: {:ok, t()} | {:error, term()}
  def admit_work_item(state, work_item_id, attrs \\ %{})

  def admit_work_item(%__MODULE__{} = state, work_item_id, attrs)
      when is_binary(work_item_id) and is_map(attrs) do
    if Map.has_key?(state.active_work_items, work_item_id) do
      {:ok, touch(state)}
    else
      case capacity_available?(state) do
        :ok ->
          {:ok, put_work_item(state, work_item_id, attrs)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def admit_work_item(_state, _work_item_id, _attrs), do: {:error, %{type: :invalid_work_item_id}}

  @spec complete_work_item(t(), work_item_id()) :: t()
  def complete_work_item(%__MODULE__{} = state, work_item_id) when is_binary(work_item_id) do
    %{
      state
      | active_work_items: Map.delete(state.active_work_items, work_item_id),
        last_activity_at: DateTime.utc_now()
    }
  end

  @spec put_work_item_pod(t(), work_item_id(), :coding_pod | :context_management_pod, term()) :: t()
  def put_work_item_pod(%__MODULE__{} = state, work_item_id, field, pod_key)
      when is_binary(work_item_id) and field in [:coding_pod, :context_management_pod] do
    case Map.fetch(state.active_work_items, work_item_id) do
      {:ok, work_item} ->
        work_item = Map.put(work_item, field, pod_key)
        %{state | active_work_items: Map.put(state.active_work_items, work_item_id, work_item)}

      :error ->
        state
    end
  end

  @spec clear_work_item_pod(t(), work_item_id(), :coding_pod | :context_management_pod) :: t()
  def clear_work_item_pod(%__MODULE__{} = state, work_item_id, field)
      when is_binary(work_item_id) and field in [:coding_pod, :context_management_pod] do
    case Map.fetch(state.active_work_items, work_item_id) do
      {:ok, work_item} ->
        work_item = Map.put(work_item, field, nil)
        %{state | active_work_items: Map.put(state.active_work_items, work_item_id, work_item)}

      :error ->
        state
    end
  end

  @spec record_diagnostic(t(), map()) :: t()
  def record_diagnostic(%__MODULE__{} = state, diagnostic) when is_map(diagnostic) do
    %{
      state
      | lifecycle: :degraded,
        diagnostics: [diagnostic | state.diagnostics],
        last_failure_at: Map.get(diagnostic, :observed_at) || DateTime.utc_now()
    }
  end

  @spec record_diagnostics(t(), [map()]) :: t()
  def record_diagnostics(%__MODULE__{} = state, diagnostics) when is_list(diagnostics) do
    Enum.reduce(diagnostics, state, &record_diagnostic(&2, &1))
  end

  @spec restore_snapshot(t(), map(), [map()], [map()]) :: {:ok, t()} | {:error, term()}
  def restore_snapshot(%__MODULE__{} = state, snapshot, restored_work_items, diagnostics)
      when is_map(snapshot) and is_list(restored_work_items) and is_list(diagnostics) do
    with :ok <- ensure_snapshot_repo(state, snapshot),
         {:ok, workspace_path} <- restore_workspace_path(state, snapshot) do
      now = DateTime.utc_now()

      next_state = %{
        state
        | workspace_path: workspace_path,
          capacity: normalize_capacity(Map.get(snapshot, :capacity, Map.get(snapshot, "capacity", state.capacity))),
          active_work_items: restore_work_items(restored_work_items),
          last_activity_at: now
      }

      {:ok, record_diagnostics(next_state, diagnostics)}
    end
  end

  @spec active_work_item_ids(t()) :: [work_item_id()]
  def active_work_item_ids(%__MODULE__{} = state) do
    state.active_work_items
    |> Map.keys()
    |> Enum.sort()
  end

  @spec mark_stopping(t()) :: t()
  def mark_stopping(%__MODULE__{} = state) do
    %{state | lifecycle: :stopping, last_activity_at: DateTime.utc_now()}
  end

  @spec mark_process_down(t(), reference(), pid(), term()) :: t()
  def mark_process_down(%__MODULE__{} = state, ref, pid, reason) do
    {monitor_key, monitors} = pop_monitor(state.monitors, ref)
    observed_at = DateTime.utc_now()

    diagnostic = %{
      type: :owned_process_down,
      monitor_key: monitor_key,
      pid: pid,
      reason: reason,
      observed_at: observed_at
    }

    %{
      state
      | monitors: monitors,
        lifecycle: :degraded,
        last_failure_at: observed_at,
        diagnostics: [diagnostic | state.diagnostics]
    }
  end

  defp put_work_item(state, work_item_id, attrs) do
    admitted_at = DateTime.utc_now()

    work_item = %{
      work_item_id: work_item_id,
      workspace_path: Map.get(attrs, :workspace_path) || Map.get(attrs, "workspace_path"),
      admitted_at: admitted_at,
      coding_pod: nil,
      context_management_pod: nil,
      lifecycle: :admitted,
      diagnostics: []
    }

    %{
      state
      | active_work_items: Map.put(state.active_work_items, work_item_id, work_item),
        last_activity_at: admitted_at
    }
  end

  defp ensure_snapshot_repo(%__MODULE__{managed_repo_id: managed_repo_id}, snapshot) do
    case Map.get(snapshot, :managed_repo_id, Map.get(snapshot, "managed_repo_id")) do
      ^managed_repo_id ->
        :ok

      other ->
        {:error, %{type: :runtime_snapshot_repo_mismatch, expected: managed_repo_id, actual: other}}
    end
  end

  defp restore_workspace_path(%__MODULE__{workspace_path: nil}, snapshot) do
    {:ok, Map.get(snapshot, :workspace_path, Map.get(snapshot, "workspace_path"))}
  end

  defp restore_workspace_path(%__MODULE__{workspace_path: workspace_path}, snapshot) do
    snapshot_workspace_path = Map.get(snapshot, :workspace_path, Map.get(snapshot, "workspace_path"))

    cond do
      is_nil(snapshot_workspace_path) ->
        {:ok, workspace_path}

      workspace_path == snapshot_workspace_path ->
        {:ok, workspace_path}

      true ->
        {:error,
         %{
           type: :workspace_mismatch,
           existing_workspace_path: workspace_path,
           requested_workspace_path: snapshot_workspace_path
         }}
    end
  end

  defp restore_work_items(work_items) do
    work_items
    |> Enum.map(&restore_work_item/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new()
  end

  defp restore_work_item(work_item) when is_map(work_item) do
    work_item_id = Map.get(work_item, :work_item_id, Map.get(work_item, "work_item_id"))

    if is_binary(work_item_id) do
      admitted_at =
        work_item
        |> Map.get(:admitted_at, Map.get(work_item, "admitted_at"))
        |> normalize_datetime(DateTime.utc_now())

      {work_item_id,
       %{
         work_item_id: work_item_id,
         workspace_path: Map.get(work_item, :workspace_path, Map.get(work_item, "workspace_path")),
         admitted_at: admitted_at,
         coding_pod: restore_key(Map.get(work_item, :coding_pod, Map.get(work_item, "coding_pod"))),
         context_management_pod:
           restore_key(Map.get(work_item, :context_management_pod, Map.get(work_item, "context_management_pod"))),
         lifecycle: :admitted,
         diagnostics: Map.get(work_item, :diagnostics, Map.get(work_item, "diagnostics", []))
       }}
    end
  end

  defp restore_work_item(_work_item), do: nil

  defp restore_key(nil), do: nil
  defp restore_key(value) when is_tuple(value), do: value

  defp restore_key(value) when is_list(value) do
    value
    |> Enum.map(&restore_key_part/1)
    |> List.to_tuple()
  end

  defp restore_key(value), do: value

  defp restore_key_part("repo"), do: :repo
  defp restore_key_part("source_code_graph"), do: :source_code_graph
  defp restore_key_part("memory_graph"), do: :memory_graph
  defp restore_key_part("coding"), do: :coding
  defp restore_key_part("context_management"), do: :context_management
  defp restore_key_part(value), do: value

  defp normalize_datetime(%DateTime{} = datetime, _default), do: datetime

  defp normalize_datetime(datetime, default) when is_binary(datetime) do
    case DateTime.from_iso8601(datetime) do
      {:ok, parsed, _offset} -> parsed
      {:error, _reason} -> default
    end
  end

  defp normalize_datetime(_datetime, default), do: default

  defp monitor_pod(%__MODULE__{} = state, monitor_key, pid) do
    existing_status = Map.get(state.active_pods, monitor_key)
    existing_ref = Map.get(state.monitors, monitor_key)

    if match?(%{runtime_pid: ^pid}, existing_status) and is_reference(existing_ref) do
      {state.monitors, Map.get(existing_status, :registered_at) || DateTime.utc_now()}
    else
      if is_reference(existing_ref), do: Process.demonitor(existing_ref, [:flush])
      {Map.put(state.monitors, monitor_key, Process.monitor(pid)), DateTime.utc_now()}
    end
  end

  defp find_pod_key(%__MODULE__{} = state, pod_id) do
    state.active_pods
    |> Enum.find_value(fn {monitor_key, pod_status} ->
      if Map.get(pod_status, :pod_id) == pod_id, do: monitor_key
    end)
  end

  defp merged_metadata(nil, incoming_metadata) when is_map(incoming_metadata), do: incoming_metadata

  defp merged_metadata(%{metadata: existing_metadata}, incoming_metadata)
       when is_map(existing_metadata) and is_map(incoming_metadata) do
    merged_metadata = Map.merge(existing_metadata, incoming_metadata)

    case {Map.get(existing_metadata, :latest_import_status), Map.get(incoming_metadata, :latest_import_status)} do
      {%{ready?: true} = existing_status, %{ready?: false}} ->
        Map.put(merged_metadata, :latest_import_status, existing_status)

      {%{ready?: true} = existing_status, nil} ->
        Map.put(merged_metadata, :latest_import_status, existing_status)

      _other ->
        merged_metadata
    end
  end

  defp capacity_available?(state) do
    case Map.get(state.capacity, :max_active_work_items, :infinity) do
      :infinity ->
        :ok

      limit when is_integer(limit) and map_size(state.active_work_items) < limit ->
        :ok

      limit when is_integer(limit) ->
        {:error,
         %{
           type: :capacity_exceeded,
           managed_repo_id: state.managed_repo_id,
           limit: limit,
           active_work_items: active_work_item_ids(state)
         }}
    end
  end

  defp normalize_capacity(capacity) when is_map(capacity) do
    limit = Map.get(capacity, :max_active_work_items, Map.get(capacity, "max_active_work_items", :infinity))
    %{max_active_work_items: normalize_limit(limit)}
  end

  defp normalize_capacity(_capacity), do: %{max_active_work_items: :infinity}

  defp normalize_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_limit(_limit), do: :infinity

  defp touch(state), do: %{state | last_activity_at: DateTime.utc_now()}

  defp pop_monitor(monitors, ref) do
    case Enum.find(monitors, fn {_key, monitor_ref} -> monitor_ref == ref end) do
      {key, _ref} -> {key, Map.delete(monitors, key)}
      nil -> {nil, monitors}
    end
  end
end
