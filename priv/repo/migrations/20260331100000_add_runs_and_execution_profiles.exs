defmodule JidoCode.Repo.Migrations.AddRunsAndExecutionProfiles do
  @moduledoc """
  Adds governed run projections and execution profiles for the control-plane migration.
  """

  use Ecto.Migration

  def up do
    create table(:execution_profiles, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false, default: "default"
      add :sandbox_profile, :map, null: false, default: %{}
      add :repo_prep_plan, {:array, :text}, null: false, default: []
      add :validation_plan, {:array, :text}, null: false, default: []
      add :governed_stages, {:array, :text}, null: false, default: []
      add :checkpoint_strategy, :text, null: false, default: "resume_from_runic_state"
      add :resume_strategy, :text, null: false, default: "resume_from_runic_state"
      add :profile_metadata, :map, null: false, default: %{}
      add :source, :text, null: false, default: "managed_repo.execution_settings"

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "execution_profiles_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:execution_profiles, [:managed_repo_id, :name],
             name: "execution_profiles_managed_repo_name_index"
           )

    create index(:execution_profiles, [:managed_repo_id],
             name: "execution_profiles_managed_repo_id_index"
           )

    create table(:runs, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :legacy_project_id, :uuid, null: false
      add :run_id, :text, null: false
      add :workflow_name, :text, null: false
      add :workflow_version, :bigint, null: false
      add :status, :text, null: false, default: "pending"
      add :current_step, :text, null: false, default: "unknown"
      add :current_stage, :text, null: false, default: "repo_attach"
      add :governed_stages, {:array, :text}, null: false, default: []
      add :stage_statuses, :map, null: false, default: %{}
      add :trigger, :map, null: false, default: %{}
      add :inputs, :map, null: false, default: %{}
      add :input_metadata, :map, null: false, default: %{}
      add :initiating_actor, :map, null: false, default: %{}
      add :execution_engine, :text, null: false, default: "jido_runic"
      add :workflow_state_ref, :map, null: false, default: %{}
      add :run_metadata, :map, null: false, default: %{}
      add :retry_of_run_id, :text
      add :retry_attempt, :bigint, null: false, default: 1
      add :retry_lineage, {:array, :map}, null: false, default: []
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec

      add(
        :workflow_run_id,
        references(:workflow_runs,
          column: :id,
          name: "runs_workflow_run_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "runs_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :work_item_id,
        references(:work_items,
          column: :id,
          name: "runs_work_item_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :execution_profile_id,
        references(:execution_profiles,
          column: :id,
          name: "runs_execution_profile_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:runs, [:workflow_run_id], name: "runs_workflow_run_id_index")
    create unique_index(:runs, [:managed_repo_id, :run_id], name: "runs_managed_repo_run_id_index")
    create index(:runs, [:work_item_id], name: "runs_work_item_id_index")
    create index(:runs, [:execution_profile_id], name: "runs_execution_profile_id_index")
    create index(:runs, [:status], name: "runs_status_index")
  end

  def down do
    drop_if_exists index(:runs, [:status], name: "runs_status_index")
    drop_if_exists index(:runs, [:execution_profile_id], name: "runs_execution_profile_id_index")
    drop_if_exists index(:runs, [:work_item_id], name: "runs_work_item_id_index")
    drop_if_exists unique_index(:runs, [:managed_repo_id, :run_id], name: "runs_managed_repo_run_id_index")
    drop_if_exists unique_index(:runs, [:workflow_run_id], name: "runs_workflow_run_id_index")
    drop table(:runs)

    drop_if_exists index(:execution_profiles, [:managed_repo_id], name: "execution_profiles_managed_repo_id_index")

    drop_if_exists unique_index(:execution_profiles, [:managed_repo_id, :name],
                     name: "execution_profiles_managed_repo_name_index"
                   )

    drop table(:execution_profiles)
  end
end
