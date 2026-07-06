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

  @spec put_pod(t(), atom(), term(), module(), pid()) :: t()
  def put_pod(%__MODULE__{} = state, kind, key, module, pid) when is_atom(kind) and is_atom(module) and is_pid(pid) do
    monitor_key = {:pod, kind, key}
    ref = Process.monitor(pid)

    pod_status = %{
      kind: kind,
      key: key,
      module: module,
      runtime_pid: pid,
      lifecycle: :running,
      nodes: %{},
      diagnostics: [],
      started_at: DateTime.utc_now()
    }

    %{
      state
      | active_pods: Map.put(state.active_pods, monitor_key, pod_status),
        monitors: Map.put(state.monitors, monitor_key, ref),
        last_activity_at: pod_status.started_at
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

  @spec record_diagnostic(t(), map()) :: t()
  def record_diagnostic(%__MODULE__{} = state, diagnostic) when is_map(diagnostic) do
    %{
      state
      | lifecycle: :degraded,
        diagnostics: [diagnostic | state.diagnostics],
        last_failure_at: Map.get(diagnostic, :observed_at) || DateTime.utc_now()
    }
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
