defmodule JidoCode.SourceCodeGraph.RefreshScheduler do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  @moduledoc false

  use GenServer

  alias JidoCode.AgentWorkspace
  alias JidoCode.Runtime
  alias JidoCode.SourceCodeGraph

  @registry JidoCode.SourceCodeGraph.RefreshSchedulerRegistry
  @supervisor JidoCode.SourceCodeGraph.RefreshSchedulerSupervisor
  @task_supervisor JidoCode.SourceCodeGraph.RefreshTaskSupervisor

  @type source_change_event :: map()

  @spec enqueue(source_change_event()) :: :ok | {:error, term()}
  def enqueue(%{managed_repo_id: managed_repo_id} = event) when is_binary(managed_repo_id) do
    if Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled, false) do
      with {:ok, _pid} <- ensure_started(managed_repo_id) do
        GenServer.cast(via(managed_repo_id), {:enqueue, event})
      end
    else
      :ok
    end
  end

  @spec ensure_started(String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(managed_repo_id, opts \\ []) when is_binary(managed_repo_id) and is_list(opts) do
    child_opts = Keyword.put(opts, :managed_repo_id, managed_repo_id)

    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, child_opts}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec status(String.t()) :: {:ok, map()} | {:error, :not_started}
  def status(managed_repo_id) when is_binary(managed_repo_id) do
    case Registry.lookup(@registry, managed_repo_id) do
      [{pid, _value}] -> GenServer.call(pid, :status)
      [] -> {:error, :not_started}
    end
  end

  @spec stop(String.t()) :: :ok
  def stop(managed_repo_id) when is_binary(managed_repo_id) do
    case Registry.lookup(@registry, managed_repo_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(@supervisor, pid)
        :ok

      [] ->
        :ok
    end
  end

  @spec via(String.t()) :: {:via, Registry, {module(), String.t()}}
  def via(managed_repo_id) when is_binary(managed_repo_id) do
    {:via, Registry, {@registry, managed_repo_id}}
  end

  def child_spec(opts) do
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)

    %{
      id: {__MODULE__, managed_repo_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) when is_list(opts) do
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)
    GenServer.start_link(__MODULE__, opts, name: via(managed_repo_id))
  end

  @impl true
  def init(opts) do
    {:ok,
     %{
       managed_repo_id: Keyword.fetch!(opts, :managed_repo_id),
       pending_event: nil,
       refresh_timer: nil,
       refresh_task: nil,
       refresh_debounce_ms: Keyword.get(opts, :refresh_debounce_ms, default_refresh_debounce_ms()),
       refresh_max_coalesce_ms: Keyword.get(opts, :refresh_max_coalesce_ms, default_refresh_max_coalesce_ms()),
       max_pending_paths: Keyword.get(opts, :max_pending_paths, default_max_pending_paths()),
       missing_graph_policy: Keyword.get(opts, :missing_graph_policy, default_missing_graph_policy()),
       refresh_fun: Keyword.get(opts, :refresh_fun, &run_agent_workspace_refresh/4),
       max_refresh_attempts: Keyword.get(opts, :max_refresh_attempts, default_max_refresh_attempts()),
       state: :idle,
       first_queued_at: nil,
       last_source_change_at: nil,
       last_refresh_started_at: nil,
       last_refresh_completed_at: nil,
       last_result: nil,
       last_failure: nil,
       pending_after_refresh?: false
     }}
  end

  @impl true
  def handle_call(:status, _from, state), do: {:reply, {:ok, status_projection(state)}, state}

  @impl true
  def handle_cast({:enqueue, event}, state) do
    next_state =
      state
      |> Map.put(:last_source_change_at, Map.get(event, :observed_at) || DateTime.utc_now())
      |> enqueue_event(event)

    {:noreply, persist_scheduler_state(next_state)}
  end

  @impl true
  def handle_info(:run_refresh, state) do
    state = %{state | refresh_timer: nil}

    if state.refresh_task do
      {:noreply, persist_scheduler_state(%{state | pending_after_refresh?: true, state: :queued})}
    else
      {:noreply, start_refresh_task(state)}
    end
  end

  def handle_info({ref, result}, %{refresh_task: %{ref: ref}} = state) do
    Process.demonitor(ref, [:flush])

    next_state =
      state
      |> Map.put(:refresh_task, nil)
      |> Map.put(:last_refresh_completed_at, DateTime.utc_now())
      |> apply_refresh_result(result)

    if next_state.pending_after_refresh? do
      rescheduled =
        next_state
        |> Map.put(:pending_after_refresh?, false)
        |> schedule_refresh()

      {:noreply, persist_scheduler_state(rescheduled)}
    else
      {:noreply, persist_scheduler_state(%{next_state | pending_event: nil, first_queued_at: nil})}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, %{refresh_task: %{ref: ref}} = state) do
    next_state =
      state
      |> Map.put(:refresh_task, nil)
      |> Map.put(:last_refresh_completed_at, DateTime.utc_now())
      |> Map.put(:last_failure, %{reason: inspect(reason), recorded_at: DateTime.utc_now()})
      |> Map.put(:state, :failed)

    {:noreply, persist_scheduler_state(next_state)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp enqueue_event(%{refresh_task: task} = state, event) when not is_nil(task) do
    %{
      state
      | pending_event: merge_events(state.pending_event, event, state.max_pending_paths),
        first_queued_at: state.first_queued_at || DateTime.utc_now(),
        pending_after_refresh?: true,
        state: :queued
    }
  end

  defp enqueue_event(state, event) do
    state
    |> Map.put(:pending_event, merge_events(state.pending_event, event, state.max_pending_paths))
    |> Map.put(:first_queued_at, state.first_queued_at || DateTime.utc_now())
    |> schedule_refresh()
  end

  defp schedule_refresh(%{refresh_timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    schedule_refresh(%{state | refresh_timer: nil})
  end

  defp schedule_refresh(state) do
    %{state | refresh_timer: Process.send_after(self(), :run_refresh, refresh_delay_ms(state)), state: :queued}
  end

  defp start_refresh_task(%{pending_event: nil} = state), do: %{state | state: :idle}

  defp start_refresh_task(state) do
    event = state.pending_event
    refresh_fun = state.refresh_fun

    task =
      Task.Supervisor.async_nolink(@task_supervisor, fn ->
        run_refresh_with_retry(
          refresh_fun,
          state.managed_repo_id,
          event.workspace_path,
          event,
          [missing_graph_policy: state.missing_graph_policy],
          state.max_refresh_attempts
        )
      end)

    %{
      state
      | refresh_task: task,
        pending_event: nil,
        first_queued_at: nil,
        state: :running,
        last_refresh_started_at: DateTime.utc_now(),
        last_failure: nil
    }
    |> persist_scheduler_state()
  end

  defp apply_refresh_result(state, {:ok, result}) do
    state
    |> Map.put(:last_result, result)
    |> Map.put(:last_failure, nil)
    |> Map.put(:state, refresh_result_state(result))
  end

  defp apply_refresh_result(state, {:error, reason, detail}) do
    state
    |> Map.put(:last_failure, %{reason: reason, detail: detail, recorded_at: DateTime.utc_now()})
    |> Map.put(:state, :failed)
  end

  defp apply_refresh_result(state, {:error, reason}) do
    state
    |> Map.put(:last_failure, %{reason: reason, recorded_at: DateTime.utc_now()})
    |> Map.put(:state, :failed)
  end

  defp apply_refresh_result(state, other) do
    state
    |> Map.put(:last_failure, %{reason: {:unexpected_result, other}, recorded_at: DateTime.utc_now()})
    |> Map.put(:state, :failed)
  end

  defp refresh_result_state(%{status: status}) when status in [:refresh_skipped_current, :refresh_skipped_not_ready],
    do: :skipped

  defp refresh_result_state(%{status: :refresh_skipped_disabled}), do: :skipped
  defp refresh_result_state(_result), do: :succeeded

  defp merge_events(nil, event, max_pending_paths), do: normalize_event(event, max_pending_paths)

  defp merge_events(existing, event, max_pending_paths) do
    event = normalize_event(event, max_pending_paths)

    existing
    |> Map.put(:observed_at, event.observed_at)
    |> Map.put(:changed_paths, merge_lists(existing.changed_paths, event.changed_paths, max_pending_paths))
    |> Map.put(:file_events, merge_lists(existing.file_events, event.file_events))
    |> Map.put(:event_sources, merge_lists(existing.event_sources, event.event_sources))
    |> then(fn merged -> Map.put(merged, :event_source, event_source(merged.event_sources)) end)
  end

  defp normalize_event(event, max_pending_paths) do
    changed_paths = Map.get(event, :changed_paths) || List.wrap(Map.get(event, :changed_path))
    event_sources = Map.get(event, :event_sources) || [Map.get(event, :event_source, :unknown)]

    %{
      kind: :workspace_source_changed,
      managed_repo_id: event.managed_repo_id,
      workspace_path: event.workspace_path,
      changed_paths:
        changed_paths |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort() |> Enum.take(max_pending_paths),
      file_events: (Map.get(event, :file_events) || []) |> Enum.uniq() |> Enum.sort(),
      event_source: event_source(event_sources),
      event_sources: event_sources |> Enum.reject(&is_nil/1) |> Enum.uniq() |> Enum.sort(),
      observed_at: Map.get(event, :observed_at) || DateTime.utc_now()
    }
  end

  defp merge_lists(left, right), do: (left ++ right) |> Enum.uniq() |> Enum.sort()
  defp merge_lists(left, right, max), do: left |> merge_lists(right) |> Enum.take(max)

  defp refresh_delay_ms(%{first_queued_at: nil} = state), do: state.refresh_debounce_ms

  defp refresh_delay_ms(state) do
    elapsed_ms = DateTime.diff(DateTime.utc_now(), state.first_queued_at, :millisecond)
    remaining_ms = max(state.refresh_max_coalesce_ms - elapsed_ms, 0)

    min(state.refresh_debounce_ms, remaining_ms)
  end

  defp event_source([event_source]), do: event_source
  defp event_source(_event_sources), do: :mixed

  defp run_agent_workspace_refresh(managed_repo_id, workspace_path, _event, opts) do
    case AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path) do
      {:ok, %{ready?: true, stale?: true}} ->
        AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path)

      {:ok, %{ready?: true, stale?: false} = status} ->
        {:ok, %{status: :refresh_skipped_current, graph_status: status}}

      {:ok, %{ready?: false} = status} ->
        case Keyword.get(opts, :missing_graph_policy, :skip) do
          :load -> AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)
          _skip -> {:ok, %{status: :refresh_skipped_not_ready, graph_status: status}}
        end

      {:error, :source_code_graph_disabled} ->
        {:ok, %{status: :refresh_skipped_disabled}}

      {:error, reason} ->
        {:error, reason}

      {:error, reason, detail} ->
        {:error, reason, detail}
    end
  end

  defp run_refresh_with_retry(refresh_fun, managed_repo_id, workspace_path, event, opts, attempts_left)
       when attempts_left <= 1 do
    refresh_fun.(managed_repo_id, workspace_path, event, opts)
  end

  defp run_refresh_with_retry(refresh_fun, managed_repo_id, workspace_path, event, opts, attempts_left) do
    case refresh_fun.(managed_repo_id, workspace_path, event, opts) do
      {:error, _reason} ->
        run_refresh_with_retry(refresh_fun, managed_repo_id, workspace_path, event, opts, attempts_left - 1)

      {:error, _reason, _detail} ->
        run_refresh_with_retry(refresh_fun, managed_repo_id, workspace_path, event, opts, attempts_left - 1)

      result ->
        result
    end
  end

  defp status_projection(state) do
    %{
      managed_repo_id: state.managed_repo_id,
      state: state.state,
      auto_refresh_enabled?: Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled, false),
      file_watcher_enabled?: Application.get_env(:jido_code, :source_code_graph_file_watcher_enabled, false),
      file_watcher_debounce_ms: Application.get_env(:jido_code, :source_code_graph_file_watcher_debounce_ms, 500),
      file_watcher_max_pending_paths:
        Application.get_env(:jido_code, :source_code_graph_file_watcher_max_pending_paths, 500),
      refresh_debounce_ms: state.refresh_debounce_ms,
      refresh_max_coalesce_ms: state.refresh_max_coalesce_ms,
      refresh_max_pending_paths: state.max_pending_paths,
      missing_graph_policy: state.missing_graph_policy,
      max_refresh_attempts: state.max_refresh_attempts,
      refresh_queued?: not is_nil(state.refresh_timer) or state.pending_after_refresh?,
      refresh_in_flight?: not is_nil(state.refresh_task),
      pending_changed_paths: pending_changed_paths(state.pending_event),
      last_source_change_at: state.last_source_change_at,
      last_refresh_started_at: state.last_refresh_started_at,
      last_refresh_completed_at: state.last_refresh_completed_at,
      last_result: state.last_result,
      last_failure: state.last_failure
    }
  end

  defp pending_changed_paths(nil), do: []
  defp pending_changed_paths(event), do: Map.get(event, :changed_paths, [])

  defp persist_scheduler_state(state) do
    updates = %{source_graph_refresh: status_projection(state)}

    case Runtime.update_pod_metadata(state.managed_repo_id, SourceCodeGraph.pod_id(), updates) do
      {:ok, _pod_entry} -> :ok
      {:error, _reason} -> :ok
    end

    state
  rescue
    _error -> state
  catch
    :exit, _reason -> state
  end

  defp default_refresh_debounce_ms do
    Application.get_env(:jido_code, :source_code_graph_refresh_debounce_ms, 250)
  end

  defp default_refresh_max_coalesce_ms do
    Application.get_env(:jido_code, :source_code_graph_refresh_max_coalesce_ms, 2_500)
  end

  defp default_max_pending_paths do
    Application.get_env(:jido_code, :source_code_graph_refresh_max_pending_paths, 500)
  end

  defp default_missing_graph_policy do
    Application.get_env(:jido_code, :source_code_graph_auto_refresh_missing_graph_policy, :skip)
  end

  defp default_max_refresh_attempts do
    Application.get_env(:jido_code, :source_code_graph_auto_refresh_max_attempts, 1)
  end
end
