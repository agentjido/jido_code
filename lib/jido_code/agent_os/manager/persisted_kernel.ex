defmodule JidoCode.AgentOS.Manager.PersistedKernel do
  # covers: architecture.agent_os_integration.ecto_persistence_per_kernel
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @timestamps_opts [type: :utc_datetime_usec]

  schema "agent_os_kernel_snapshots" do
    field :kernel_name, :string
    field :managed_repo_id, :string
    field :snapshot_data, :binary

    timestamps()
  end

  def changeset(record, attrs) do
    record
    |> cast(attrs, [:kernel_name, :managed_repo_id, :snapshot_data])
    |> validate_required([:kernel_name, :managed_repo_id, :snapshot_data])
    |> unique_constraint(:kernel_name, name: "agent_os_kernel_snapshots_kernel_name_index")
  end
end
