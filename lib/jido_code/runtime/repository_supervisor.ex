defmodule JidoCode.Runtime.RepositorySupervisor do
  @moduledoc false

  use DynamicSupervisor

  alias JidoCode.Runtime.RepositoryRuntime

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec start_repository(keyword()) :: DynamicSupervisor.on_start_child()
  def start_repository(opts) when is_list(opts) do
    DynamicSupervisor.start_child(__MODULE__, {RepositoryRuntime, opts})
  end

  @spec stop_repository(pid()) :: :ok | {:error, :not_found}
  def stop_repository(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
