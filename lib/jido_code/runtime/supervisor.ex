defmodule JidoCode.Runtime.Supervisor do
  @moduledoc """
  Supervision root for repository runtime containers.
  """

  use Supervisor

  alias JidoCode.Runtime.InstanceManagers

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children =
      [
        {Registry, keys: :unique, name: JidoCode.Runtime.Registry}
      ] ++
        InstanceManagers.child_specs() ++
        [
          JidoCode.Runtime.RepositorySupervisor
        ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
