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

      # Start an agent (implementation in task 1.2.2)
      {:ok, pid} = JidoCode.AgentSupervisor.start_agent(agent_spec)

      # Stop an agent
      :ok = JidoCode.AgentSupervisor.stop_agent(pid)

      # List running agents
      agents = JidoCode.AgentSupervisor.which_children()
  """

  use DynamicSupervisor

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
