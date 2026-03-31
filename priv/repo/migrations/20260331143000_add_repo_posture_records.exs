defmodule JidoCode.Repo.Migrations.AddRepoPostureRecords do
  @moduledoc """
  Adds durable repo posture summary and contributing check records.
  """

  use Ecto.Migration

  def up do
    create table(:repo_postures, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :managed_repo_id, references(:managed_repos, type: :uuid, prefix: "public"), null: false
      add :summary, :text, null: false
      add :overall_trust, :text, null: false
      add :execution_readiness, :text, null: false
      add :validation_reliability, :text, null: false
      add :review_burden, :text, null: false
      add :drift_rate, :text, null: false
      add :recovery_resilience, :text, null: false
      add :requirements_confidence, :text, null: false
      add :contributing_check_ids, {:array, :uuid}, null: false, default: []
      add :posture_metadata, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:repo_postures, [:managed_repo_id], name: "repo_postures_managed_repo_id_index")

    create table(:posture_checks, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :repo_posture_id, references(:repo_postures, type: :uuid, prefix: "public")
      add :managed_repo_id, references(:managed_repos, type: :uuid, prefix: "public"), null: false
      add :observation_id, references(:observations, type: :uuid, prefix: "public")
      add :assessment_id, references(:assessments, type: :uuid, prefix: "public")
      add :evidence_id, references(:evidence_records, type: :uuid, prefix: "public")
      add :dimension, :text, null: false
      add :value, :text, null: false
      add :summary, :text, null: false
      add :details, :map, null: false, default: %{}
      add :source, :text, null: false, default: "posture_bridge"
      add :checked_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:posture_checks, [:managed_repo_id, :dimension],
             name: "posture_checks_managed_repo_dimension_index"
           )

    create index(:posture_checks, [:repo_posture_id], name: "posture_checks_repo_posture_id_index")
    create index(:posture_checks, [:observation_id], name: "posture_checks_observation_id_index")
    create index(:posture_checks, [:assessment_id], name: "posture_checks_assessment_id_index")
    create index(:posture_checks, [:evidence_id], name: "posture_checks_evidence_id_index")
  end

  def down do
    drop_if_exists index(:posture_checks, [:evidence_id], name: "posture_checks_evidence_id_index")
    drop_if_exists index(:posture_checks, [:assessment_id], name: "posture_checks_assessment_id_index")
    drop_if_exists index(:posture_checks, [:observation_id], name: "posture_checks_observation_id_index")
    drop_if_exists index(:posture_checks, [:repo_posture_id], name: "posture_checks_repo_posture_id_index")

    drop_if_exists unique_index(:posture_checks, [:managed_repo_id, :dimension],
                     name: "posture_checks_managed_repo_dimension_index"
                   )

    drop table(:posture_checks)

    drop_if_exists unique_index(:repo_postures, [:managed_repo_id],
                     name: "repo_postures_managed_repo_id_index"
                   )

    drop table(:repo_postures)
  end
end
