defmodule JidoCode.ControlPlane.StoreServer do
  use GenServer

  alias JidoCode.ControlPlane.{GraphTopology, StoreConfig}
  alias JidoCode.MemoryGraph

  @type health :: %{
          ready?: boolean(),
          path: String.t(),
          schema: :quad,
          reset_policy: atom(),
          ontology_bootstrap: map(),
          graph_counts: map()
        }

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    id = Keyword.get(opts, :id, __MODULE__)

    %{
      id: id,
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5_000,
      type: :worker
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec health(GenServer.server()) :: health()
  def health(server \\ __MODULE__), do: GenServer.call(server, :health)

  @spec reset(GenServer.server()) :: {:ok, health()} | {:error, term()}
  def reset(server \\ __MODULE__), do: GenServer.call(server, :reset, :infinity)

  @spec with_store(GenServer.server(), (map() -> term())) :: {:ok, term()} | {:error, term()}
  def with_store(server \\ __MODULE__, fun) when is_function(fun, 1) do
    GenServer.call(server, {:with_store, fun}, :infinity)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    path = StoreConfig.store_path(opts)
    reset_policy = StoreConfig.reset_policy(opts)
    open_timeout_ms = StoreConfig.open_timeout_ms(opts)

    case open_bootstrapped_store(path, reset_policy, open_timeout_ms) do
      {:ok, store, bootstrap} ->
        {:ok,
         %{
           store: store,
           path: path,
           reset_policy: reset_policy,
           open_timeout_ms: open_timeout_ms,
           ontology_bootstrap: bootstrap
         }}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:health, _from, state) do
    {:reply, health_from_state(state), state}
  end

  def handle_call(:reset, _from, state) do
    close_store(state.store)
    File.rm_rf(state.path)

    case open_bootstrapped_store(state.path, :reset_on_start, state.open_timeout_ms) do
      {:ok, store, bootstrap} ->
        next_state = %{state | store: store, ontology_bootstrap: bootstrap}
        {:reply, {:ok, health_from_state(next_state)}, next_state}

      {:error, reason} ->
        {:reply, {:error, reason},
         %{state | store: nil, ontology_bootstrap: %{state: :failed, reason: inspect(reason)}}}
    end
  end

  def handle_call({:with_store, _fun}, _from, %{store: nil} = state) do
    {:reply, {:error, :store_unavailable}, state}
  end

  def handle_call({:with_store, fun}, _from, state) do
    result =
      try do
        {:ok, fun.(state.store)}
      rescue
        exception -> {:error, {exception.__struct__, Exception.message(exception)}}
      catch
        kind, reason -> {:error, {kind, reason}}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_info({:EXIT, _pid, :normal}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, :shutdown}, state), do: {:noreply, state}
  def handle_info({:EXIT, _pid, {:shutdown, _reason}}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{store: store}) do
    close_store(store)
  end

  defp open_bootstrapped_store(path, reset_policy, open_timeout_ms) do
    with :ok <- prepare_path(path, reset_policy),
         {:ok, store} <- open_store(path, open_timeout_ms) do
      case bootstrap_ontologies(store) do
        {:ok, bootstrap} ->
          {:ok, store, bootstrap}

        {:error, reason} ->
          close_store(store)
          {:error, reason}
      end
    end
  end

  defp prepare_path(path, :reset_on_start) do
    File.rm_rf(path)
    ensure_parent(path)
  end

  defp prepare_path(path, _reset_policy), do: ensure_parent(path)

  defp ensure_parent(path) do
    path
    |> Path.dirname()
    |> File.mkdir_p()
  end

  defp open_store(path, open_timeout_ms) do
    task =
      Task.async(fn ->
        TripleStore.open(path, create_if_missing: true, schema: :quad)
      end)

    case Task.yield(task, open_timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, {:open_timeout, open_timeout_ms}}
    end
  end

  defp bootstrap_ontologies(store) do
    with {:ok, control_plane_graph} <- GraphTopology.graph_resource(:control_plane),
         {:ok, loaded_count} <- load_ontology_artifacts(store, control_plane_graph) do
      {:ok,
       %{
         state: :ready,
         named_graph_iri: to_string(control_plane_graph),
         loaded_triple_count: loaded_count,
         loaded_at: DateTime.utc_now()
       }}
    end
  end

  defp load_ontology_artifacts(store, named_graph) do
    MemoryGraph.ontology_artifacts()
    |> Enum.reduce_while({:ok, 0}, fn artifact, {:ok, total_count} ->
      with {:ok, graph} <- RDF.Turtle.read_file(artifact.path),
           {:ok, count} <- TripleStore.load_graph(store, graph, graph: named_graph) do
        {:cont, {:ok, total_count + count}}
      else
        {:error, reason} -> {:halt, {:error, {artifact.filename, reason}}}
      end
    end)
  end

  defp health_from_state(%{store: nil} = state) do
    %{
      ready?: false,
      path: state.path,
      schema: :quad,
      reset_policy: state.reset_policy,
      ontology_bootstrap: state.ontology_bootstrap,
      graph_counts: %{}
    }
  end

  defp health_from_state(state) do
    %{
      ready?: true,
      path: state.path,
      schema: state.store.schema,
      reset_policy: state.reset_policy,
      ontology_bootstrap: state.ontology_bootstrap,
      graph_counts: graph_counts(state.store)
    }
  end

  defp graph_counts(store) do
    case TripleStore.QuadOperations.graphs_summary(store.db, include_default: false) do
      {:ok, summary} ->
        Map.new(summary, fn {graph, count} -> {to_string(graph), count} end)

      {:error, _reason} ->
        %{}
    end
  end

  defp close_store(nil), do: :ok

  defp close_store(store) do
    case TripleStore.close(store) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end
end
