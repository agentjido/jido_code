defmodule JidoCode.Repo.Migrations.AddRunGovernanceRecords do
  @moduledoc """
  Adds evidence, change request, and decision records around governed runs.
  """

  use Ecto.Migration

  def up do
    create table(:evidence_records, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :run_id, references(:runs, type: :uuid, prefix: "public"), null: false
      add :managed_repo_id, references(:managed_repos, type: :uuid, prefix: "public"), null: false
      add :work_item_id, references(:work_items, type: :uuid, prefix: "public")
      add :key, :text, null: false
      add :evidence_type, :text, null: false
      add :summary, :text, null: false
      add :evidence_details, :map, null: false, default: %{}
      add :source, :text, null: false, default: "workflow_run"
      add :recorded_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:evidence_records, [:run_id, :key], name: "evidence_records_run_key_index")
    create index(:evidence_records, [:managed_repo_id], name: "evidence_records_managed_repo_index")

    create table(:change_requests, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :run_id, references(:runs, type: :uuid, prefix: "public"), null: false
      add :managed_repo_id, references(:managed_repos, type: :uuid, prefix: "public"), null: false
      add :work_item_id, references(:work_items, type: :uuid, prefix: "public")
      add :status, :text, null: false, default: "open"
      add :summary, :text, null: false
      add :review_context, :map, null: false, default: %{}
      add :request_metadata, :map, null: false, default: %{}
      add :evidence_ids, {:array, :uuid}, null: false, default: []
      add :requested_at, :utc_datetime_usec, null: false
      add :resolved_at, :utc_datetime_usec
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:change_requests, [:run_id], name: "change_requests_run_id_index")
    create index(:change_requests, [:managed_repo_id], name: "change_requests_managed_repo_index")

    create table(:decisions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :decision_key, :text, null: false
      add :run_id, references(:runs, type: :uuid, prefix: "public"), null: false
      add :change_request_id, references(:change_requests, type: :uuid, prefix: "public")
      add :managed_repo_id, references(:managed_repos, type: :uuid, prefix: "public"), null: false
      add :work_item_id, references(:work_items, type: :uuid, prefix: "public")
      add :decision, :text, null: false
      add :actor, :map, null: false, default: %{}
      add :rationale, :text
      add :evidence_ids, {:array, :uuid}, null: false, default: []
      add :decision_metadata, :map, null: false, default: %{}
      add :decided_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:decisions, [:decision_key], name: "decisions_decision_key_index")
    create index(:decisions, [:run_id], name: "decisions_run_id_index")
    create index(:decisions, [:change_request_id], name: "decisions_change_request_id_index")
  end

  def down do
    drop_if_exists index(:decisions, [:change_request_id], name: "decisions_change_request_id_index")
    drop_if_exists index(:decisions, [:run_id], name: "decisions_run_id_index")
    drop_if_exists unique_index(:decisions, [:decision_key], name: "decisions_decision_key_index")
    drop table(:decisions)

    drop_if_exists index(:change_requests, [:managed_repo_id], name: "change_requests_managed_repo_index")
    drop_if_exists unique_index(:change_requests, [:run_id], name: "change_requests_run_id_index")
    drop table(:change_requests)

    drop_if_exists index(:evidence_records, [:managed_repo_id], name: "evidence_records_managed_repo_index")
    drop_if_exists unique_index(:evidence_records, [:run_id, :key], name: "evidence_records_run_key_index")
    drop table(:evidence_records)
  end
end
