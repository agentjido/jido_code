defmodule JidoCode.AgentOS.Manager.Supervisor do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.dynamic_kernel_lifecycle
  @moduledoc """
  Dynamic supervisor for managing AgentOS kernels.

  This supervisor manages one kernel process per ManagedRepo, allowing
  kernels to be created and shut down dynamically.
  """

  use DynamicSupervisor
  require Logger

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_children: 100, # Maximum concurrent kernels
      max_seconds: 60
    )
  end
end
