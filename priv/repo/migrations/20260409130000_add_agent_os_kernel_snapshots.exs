defmodule JidoCode.Repo.Migrations.AddAgentOsKernelSnapshots do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.agent_os_integration.ecto_persistence_per_kernel
  # covers: architecture.agent_os_integration.kernel_snapshots_restore_resumable_runtime_state
  @moduledoc """
  Adds durable AgentOS kernel snapshot storage for repository-scoped runtime restoration.
  """

  use Ecto.Migration

  def up do
    create table(:agent_os_kernel_snapshots, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :kernel_name, :text, null: false
      add :managed_repo_id, :text, null: false
      add :snapshot_data, :binary, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:agent_os_kernel_snapshots, [:kernel_name],
             name: "agent_os_kernel_snapshots_kernel_name_index"
           )

    create index(:agent_os_kernel_snapshots, [:managed_repo_id],
             name: "agent_os_kernel_snapshots_managed_repo_id_index"
           )
  end

  def down do
    drop_if_exists index(:agent_os_kernel_snapshots, [:managed_repo_id],
                     name: "agent_os_kernel_snapshots_managed_repo_id_index"
                   )

    drop_if_exists unique_index(:agent_os_kernel_snapshots, [:kernel_name],
                     name: "agent_os_kernel_snapshots_kernel_name_index"
                   )

    drop table(:agent_os_kernel_snapshots)
  end
end
