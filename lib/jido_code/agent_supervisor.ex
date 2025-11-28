defmodule JidoCode.AgentSupervisor do
  @moduledoc """
  DynamicSupervisor for managing LLM agent processes.

  This supervisor manages the lifecycle of agent processes, allowing them to be
  started and stopped dynamically at runtime. Agents are registered in
  `JidoCode.AgentRegistry` for lookup by name.

  ## Restart Strategy

  Uses `:transient` restart strategy - agents are only restarted if they
  terminate abnormally. Normal exits (e.g., user-initiated stop) do not
  trigger a restart.

  ## Usage

      # Start an agent
      {:ok, pid} = JidoCode.AgentSupervisor.start_agent(%{
        name: :my_agent,
        module: JidoCode.TestAgent,
        args: []
      })

      # Lookup an agent by name
      {:ok, pid} = JidoCode.AgentSupervisor.lookup_agent(:my_agent)

      # Stop an agent by pid or name
      :ok = JidoCode.AgentSupervisor.stop_agent(pid)
      :ok = JidoCode.AgentSupervisor.stop_agent(:my_agent)

      # List running agents
      agents = JidoCode.AgentSupervisor.which_children()
  """

  use DynamicSupervisor

  @registry JidoCode.AgentRegistry

  @doc """
  Starts the AgentSupervisor.
  """
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a supervised agent process.

  ## Options

  - `:name` - (required) Unique name for the agent, used for Registry lookup
  - `:module` - (required) The GenServer module to start
  - `:args` - (optional) Arguments to pass to the module's start_link/1

  ## Returns

  - `{:ok, pid}` - Agent started successfully
  - `{:error, {:already_started, pid}}` - Agent with this name already exists
  - `{:error, String.t()}` - Invalid agent spec (descriptive message)

  ## Examples

      iex> JidoCode.AgentSupervisor.start_agent(%{
      ...>   name: :my_agent,
      ...>   module: JidoCode.TestAgent,
      ...>   args: []
      ...> })
      {:ok, #PID<0.123.0>}
  """
  @spec start_agent(map()) :: {:ok, pid()} | {:error, term()}
  def start_agent(%{name: name, module: module} = spec) do
    args = Map.get(spec, :args, [])

    # Build the via tuple for Registry registration
    via_name = {:via, Registry, {@registry, name}}

    # Build child spec with transient restart
    child_spec = %{
      id: name,
      start: {module, :start_link, [Keyword.put(args, :name, via_name)]},
      restart: :transient
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def start_agent(invalid_spec) do
    {:error, "invalid agent spec: must be a map with :name and :module keys, got: #{inspect(invalid_spec)}"}
  end

  @doc """
  Stops a supervised agent process.

  Accepts either a pid or an agent name. The agent is terminated gracefully
  using `DynamicSupervisor.terminate_child/2`.

  ## Returns

  - `:ok` - Agent stopped successfully
  - `{:error, :not_found}` - No agent with this name/pid exists

  ## Examples

      iex> JidoCode.AgentSupervisor.stop_agent(:my_agent)
      :ok

      iex> JidoCode.AgentSupervisor.stop_agent(pid)
      :ok
  """
  @spec stop_agent(pid() | atom()) :: :ok | {:error, :not_found}
  def stop_agent(pid) when is_pid(pid) do
    case DynamicSupervisor.terminate_child(__MODULE__, pid) do
      :ok -> :ok
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  def stop_agent(name) when is_atom(name) do
    case lookup_agent(name) do
      {:ok, pid} -> stop_agent(pid)
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Looks up an agent by name in the Registry.

  ## Returns

  - `{:ok, pid}` - Agent found
  - `{:error, :not_found}` - No agent with this name

  ## Examples

      iex> JidoCode.AgentSupervisor.lookup_agent(:my_agent)
      {:ok, #PID<0.123.0>}

      iex> JidoCode.AgentSupervisor.lookup_agent(:unknown)
      {:error, :not_found}
  """
  @spec lookup_agent(atom()) :: {:ok, pid()} | {:error, :not_found}
  def lookup_agent(name) do
    case Registry.lookup(@registry, name) do
      [{pid, _value}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Returns the count of running agent processes.
  """
  @spec count_children() :: %{
          specs: non_neg_integer(),
          active: non_neg_integer(),
          supervisors: non_neg_integer(),
          workers: non_neg_integer()
        }
  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end

  @doc """
  Returns a list of all child processes.
  """
  @spec which_children() :: [{:undefined, pid() | :restarting, :worker | :supervisor, [module()]}]
  def which_children do
    DynamicSupervisor.which_children(__MODULE__)
  end
end
