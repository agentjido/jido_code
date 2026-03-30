defmodule JidoCode.Repo.Migrations.AddControlPlaneRepoResources do
  @moduledoc """
  Introduces transitional control-plane repository resources and their first workflow linkage.
  """

  use Ecto.Migration

  def up do
    create table(:source_repos, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :provider, :text, null: false
      add :owner, :text, null: false
      add :name, :text, null: false
      add :full_name, :text, null: false
      add :default_branch, :text, null: false, default: "main"
      add :source_metadata, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:source_repos, [:provider, :full_name],
             name: "source_repos_unique_provider_full_name_index"
           )

    create table(:managed_repos, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :display_name, :text, null: false
      add :legacy_project_id, :uuid, null: false

      add(
        :source_repo_id,
        references(:source_repos,
          column: :id,
          name: "managed_repos_source_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add :workspace_settings, :map, null: false, default: %{}
      add :execution_settings, :map, null: false, default: %{}
      add :integration_settings, :map, null: false, default: %{}

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:managed_repos, [:legacy_project_id],
             name: "managed_repos_unique_legacy_project_id_index"
           )

    create unique_index(:managed_repos, [:source_repo_id],
             name: "managed_repos_unique_source_repo_id_index"
           )

    alter table(:workflow_runs) do
      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "workflow_runs_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )
    end

    create index(:workflow_runs, [:managed_repo_id], name: "workflow_runs_managed_repo_id_index")
  end

  def down do
    drop_if_exists index(:workflow_runs, [:managed_repo_id],
                     name: "workflow_runs_managed_repo_id_index"
                   )

    alter table(:workflow_runs) do
      remove :managed_repo_id
    end

    drop_if_exists unique_index(:managed_repos, [:source_repo_id],
                     name: "managed_repos_unique_source_repo_id_index"
                   )

    drop_if_exists unique_index(:managed_repos, [:legacy_project_id],
                     name: "managed_repos_unique_legacy_project_id_index"
                   )

    drop table(:managed_repos)

    drop_if_exists unique_index(:source_repos, [:provider, :full_name],
                     name: "source_repos_unique_provider_full_name_index"
                   )

    drop table(:source_repos)
  end
end
