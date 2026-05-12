defmodule JidoCode.Agents.RepoMonitor.SourceWatcher do
  # covers: architecture.agent_os_integration.repo_pod_singleton_per_kernel
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  @moduledoc false

  use GenServer

  require Logger

  alias JidoCode.Agents.RepoMonitor
  alias JidoCode.AgentOS.Manager
  alias JidoCode.SourceCodeGraph
  alias JidoCode.SourceCodeGraph.RefreshScheduler

  @registry JidoCode.RepoMonitor.SourceWatcherRegistry
  @supervisor JidoCode.RepoMonitor.SourceWatcherSupervisor
  @repo_pod_id "repo-pod"

  @type source_change_event :: %{
          kind: :workspace_source_changed,
          managed_repo_id: String.t(),
          workspace_path: String.t(),
          changed_paths: [String.t()],
          changed_path: String.t(),
          file_events: [atom() | String.t()],
          event_source: atom(),
          event_sources: [atom()],
          current_revision: String.t() | nil,
          source_commit: String.t() | nil,
          workspace_snapshot_identity: String.t() | nil,
          observed_at: DateTime.t()
        }

  @spec ensure_started(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_started(managed_repo_id, workspace_path, opts \\ [])
      when is_binary(managed_repo_id) and is_binary(workspace_path) and is_list(opts) do
    child_opts =
      opts
      |> Keyword.put(:managed_repo_id, managed_repo_id)
      |> Keyword.put(:workspace_path, workspace_path)

    case DynamicSupervisor.start_child(@supervisor, {__MODULE__, child_opts}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        GenServer.call(pid, {:configure, workspace_path, opts})

      {:error, {:shutdown, reason}} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
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

  @spec notify_change(String.t(), String.t(), [atom() | String.t()], atom()) :: :ok | {:error, term()}
  def notify_change(managed_repo_id, changed_path, file_events, event_source)
      when is_binary(managed_repo_id) and is_binary(changed_path) and is_list(file_events) and
             is_atom(event_source) do
    case Registry.lookup(@registry, managed_repo_id) do
      [{pid, _value}] ->
        GenServer.cast(pid, {:notify_change, changed_path, file_events, event_source})

      [] ->
        {:error, :source_watcher_not_started}
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
    Process.flag(:trap_exit, true)

    with {:ok, state} <- build_state(opts),
         {:ok, state} <- maybe_start_file_watcher(state, opts) do
      {:ok, persist_watcher_state(state)}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call({:configure, workspace_path, opts}, _from, state) do
    with {:ok, normalized_workspace_path} <- normalize_workspace_path(workspace_path) do
      if normalized_workspace_path == state.workspace_path do
        {:reply, {:ok, self()}, state}
      else
        next_state =
          state
          |> stop_file_watcher()
          |> Map.put(:workspace_path, normalized_workspace_path)
          |> Map.put(:debounce_ms, debounce_ms(opts))
          |> Map.put(:max_pending_paths, max_pending_paths(opts))
          |> Map.put(:pending_change, nil)

        case maybe_start_file_watcher(next_state, opts) do
          {:ok, configured_state} ->
            {:reply, {:ok, self()}, persist_watcher_state(configured_state)}

          {:error, reason} ->
            {:reply, {:error, reason}, persist_watcher_state(%{next_state | watcher_status: :failed})}
        end
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_cast({:notify_change, path, events, event_source}, state) do
    {:noreply, queue_source_change(state, path, List.wrap(events), event_source)}
  end

  @impl true
  def handle_info({:file_event, watcher_pid, {path, events}}, %{file_watcher_pid: watcher_pid} = state) do
    {:noreply, queue_source_change(state, path, List.wrap(events), :human_watcher)}
  end

  def handle_info({:file_event, watcher_pid, :stop}, %{file_watcher_pid: watcher_pid} = state) do
    {:noreply, persist_watcher_state(%{state | file_watcher_pid: nil, watcher_status: :stopped})}
  end

  def handle_info({:file_event, _watcher_pid, _event}, state), do: {:noreply, state}

  def handle_info(:flush_source_changes, state) do
    case source_change_event(state) do
      {:ok, event} ->
        publish_source_change(event)
        {:noreply, persist_source_change(%{state | debounce_timer: nil, pending_change: nil}, event)}

      :ignore ->
        {:noreply, %{state | debounce_timer: nil, pending_change: nil}}
    end
  end

  def handle_info({:EXIT, pid, reason}, %{file_watcher_pid: pid} = state) do
    Logger.warning(
      "source_file_watcher_exited managed_repo_id=#{inspect(state.managed_repo_id)} reason=#{inspect(reason)}"
    )

    {:noreply, persist_watcher_state(%{state | file_watcher_pid: nil, file_watcher_ref: nil, watcher_status: :stopped})}
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, %{file_watcher_ref: ref, file_watcher_pid: pid} = state) do
    Logger.warning(
      "source_file_watcher_stopped managed_repo_id=#{inspect(state.managed_repo_id)} reason=#{inspect(reason)}"
    )

    {:noreply, persist_watcher_state(%{state | file_watcher_pid: nil, file_watcher_ref: nil, watcher_status: :stopped})}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp build_state(opts) do
    managed_repo_id = Keyword.fetch!(opts, :managed_repo_id)

    with {:ok, workspace_path} <- normalize_workspace_path(Keyword.get(opts, :workspace_path)) do
      {:ok,
       %{
         managed_repo_id: managed_repo_id,
         workspace_path: workspace_path,
         file_watcher_pid: nil,
         file_watcher_ref: nil,
         watcher_status: :starting,
         debounce_ms: debounce_ms(opts),
         max_pending_paths: max_pending_paths(opts),
         debounce_timer: nil,
         pending_change: nil,
         latest_source_change: nil
       }}
    end
  end

  defp normalize_workspace_path(path) when is_binary(path) do
    case SourceCodeGraph.normalize_workspace_path(path) do
      {:ok, workspace_path} ->
        if File.dir?(workspace_path) do
          {:ok, workspace_path}
        else
          {:error, :missing_workspace_path}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp normalize_workspace_path(_path), do: {:error, :missing_workspace_path}

  defp maybe_start_file_watcher(state, opts) do
    start_file_system? =
      Keyword.get(
        opts,
        :start_file_system?,
        Application.get_env(:jido_code, :source_code_graph_file_watcher_enabled, false)
      )

    if start_file_system? do
      start_file_watcher(state)
    else
      {:ok, %{state | watcher_status: :disabled}}
    end
  end

  defp debounce_ms(opts) do
    Keyword.get(opts, :debounce_ms, Application.get_env(:jido_code, :source_code_graph_file_watcher_debounce_ms, 500))
  end

  defp max_pending_paths(opts) do
    Keyword.get(
      opts,
      :max_pending_paths,
      Application.get_env(:jido_code, :source_code_graph_file_watcher_max_pending_paths, 500)
    )
  end

  defp start_file_watcher(state) do
    with {:module, FileSystem} <- Code.ensure_loaded(FileSystem),
         {:ok, watcher_pid} <- FileSystem.start_link(dirs: [state.workspace_path]),
         :ok <- FileSystem.subscribe(watcher_pid) do
      {:ok,
       %{
         state
         | file_watcher_pid: watcher_pid,
           file_watcher_ref: Process.monitor(watcher_pid),
           watcher_status: :watching
       }}
    else
      {:error, reason} ->
        {:error, {:file_watcher_start_failed, reason}}

      other ->
        {:error, {:file_watcher_unavailable, other}}
    end
  end

  defp stop_file_watcher(%{file_watcher_pid: nil} = state), do: state

  defp stop_file_watcher(%{file_watcher_pid: pid, file_watcher_ref: ref} = state) do
    if is_reference(ref), do: Process.demonitor(ref, [:flush])
    if Process.alive?(pid), do: GenServer.stop(pid)

    %{state | file_watcher_pid: nil, file_watcher_ref: nil, watcher_status: :stopped}
  end

  defp queue_source_change(state, path, file_events, event_source) do
    if SourceCodeGraph.source_file?(state.workspace_path, path) do
      changed_path = Path.relative_to(Path.expand(path), state.workspace_path)

      pending_change =
        merge_pending_change(state.pending_change, changed_path, file_events, event_source, state.max_pending_paths)

      state
      |> Map.put(:pending_change, pending_change)
      |> schedule_debounce()
    else
      state
    end
  end

  defp merge_pending_change(nil, changed_path, file_events, event_source, _max_pending_paths) do
    %{
      changed_paths: MapSet.new([changed_path]),
      file_events: MapSet.new(normalize_file_events(file_events)),
      event_sources: MapSet.new([event_source]),
      first_observed_at: DateTime.utc_now()
    }
  end

  defp merge_pending_change(pending_change, changed_path, file_events, event_source, max_pending_paths) do
    pending_change
    |> update_in([:changed_paths], &bounded_path_put(&1, changed_path, max_pending_paths))
    |> update_in([:file_events], fn existing ->
      Enum.reduce(normalize_file_events(file_events), existing, fn event, acc -> MapSet.put(acc, event) end)
    end)
    |> update_in([:event_sources], &MapSet.put(&1, event_source))
  end

  defp bounded_path_put(paths, changed_path, max_pending_paths) do
    cond do
      MapSet.member?(paths, changed_path) -> paths
      MapSet.size(paths) < max_pending_paths -> MapSet.put(paths, changed_path)
      true -> paths
    end
  end

  defp schedule_debounce(%{debounce_timer: timer} = state) when is_reference(timer) do
    Process.cancel_timer(timer)
    schedule_debounce(%{state | debounce_timer: nil})
  end

  defp schedule_debounce(state) do
    %{state | debounce_timer: Process.send_after(self(), :flush_source_changes, state.debounce_ms)}
  end

  defp source_change_event(%{pending_change: nil}), do: :ignore

  defp source_change_event(state) do
    revision_metadata =
      case SourceCodeGraph.current_revision_metadata(state.workspace_path) do
        {:ok, metadata} -> metadata
        {:error, _reason} -> %{}
      end

    changed_paths = state.pending_change.changed_paths |> MapSet.to_list() |> Enum.sort()
    event_sources = state.pending_change.event_sources |> MapSet.to_list() |> Enum.sort()

    {:ok,
     %{
       kind: :workspace_source_changed,
       managed_repo_id: state.managed_repo_id,
       workspace_path: state.workspace_path,
       changed_paths: changed_paths,
       changed_path: List.first(changed_paths),
       file_events: state.pending_change.file_events |> MapSet.to_list() |> Enum.sort(),
       event_source: event_source(event_sources),
       event_sources: event_sources,
       current_revision: Map.get(revision_metadata, :current_revision),
       source_commit: Map.get(revision_metadata, :source_commit),
       workspace_snapshot_identity: Map.get(revision_metadata, :workspace_snapshot_identity),
       observed_at: DateTime.utc_now()
     }}
  end

  defp event_source([event_source]), do: event_source
  defp event_source(_event_sources), do: :mixed

  defp normalize_file_events(events) do
    events
    |> Enum.map(fn
      event when is_atom(event) -> event
      event when is_binary(event) -> event
      event -> event
    end)
  end

  defp publish_source_change(event) do
    Phoenix.PubSub.broadcast(
      JidoCode.PubSub,
      RepoMonitor.source_change_topic(event.managed_repo_id),
      {:workspace_source_changed, event}
    )

    RefreshScheduler.enqueue(event)
  end

  defp persist_source_change(state, event) do
    next_state = %{state | latest_source_change: event}

    persist_watcher_state(next_state, %{
      latest_source_change: Map.drop(event, [:kind]),
      latest_source_change_at: event.observed_at
    })
  end

  defp persist_watcher_state(state, extra_updates \\ %{}) do
    updates =
      Map.merge(
        %{
          source_watcher: %{
            workspace_path: state.workspace_path,
            status: state.watcher_status,
            latest_source_change_at: state.latest_source_change && state.latest_source_change.observed_at
          }
        },
        extra_updates
      )

    safe_update_pod_metadata(state.managed_repo_id, updates)

    state
  end

  defp safe_update_pod_metadata(managed_repo_id, updates) do
    case Manager.update_pod_metadata(managed_repo_id, @repo_pod_id, updates) do
      {:ok, _pod_entry} -> :ok
      {:error, _reason} -> :ok
    end
  rescue
    _error -> :ok
  catch
    :exit, _reason -> :ok
  end
end
