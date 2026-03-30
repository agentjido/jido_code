defmodule JidoCode.Repo.Migrations.AddOperationsWorkItems do
  @moduledoc """
  Adds durable work items for baseline control-plane work synthesis.
  """

  use Ecto.Migration

  def up do
    create table(:work_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :category, :text, null: false
      add :status, :text, null: false, default: "open"
      add :priority, :text, null: false
      add :recommended_action, :text, null: false
      add :summary, :text, null: false
      add :dedup_key, :text, null: false
      add :initiating_actor, :map, null: false, default: %{}
      add :work_metadata, :map, null: false, default: %{}
      add :audit_log, {:array, :map}, null: false, default: []
      add :opened_at, :utc_datetime_usec, null: false
      add :last_assessed_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "work_items_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :assessment_id,
        references(:assessments,
          column: :id,
          name: "work_items_assessment_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :event_id,
        references(:events,
          column: :id,
          name: "work_items_event_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :external_object_id,
        references(:external_objects,
          column: :id,
          name: "work_items_external_object_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :observation_id,
        references(:observations,
          column: :id,
          name: "work_items_observation_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :intake_id,
        references(:intakes,
          column: :id,
          name: "work_items_intake_id_fkey",
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

    create index(:work_items, [:managed_repo_id], name: "work_items_managed_repo_id_index")
    create index(:work_items, [:assessment_id], name: "work_items_assessment_id_index")
    create index(:work_items, [:event_id], name: "work_items_event_id_index")
    create index(:work_items, [:external_object_id], name: "work_items_external_object_id_index")
    create index(:work_items, [:observation_id], name: "work_items_observation_id_index")
    create index(:work_items, [:intake_id], name: "work_items_intake_id_index")
    create index(:work_items, [:status], name: "work_items_status_index")
    create index(:work_items, [:priority], name: "work_items_priority_index")
    create index(:work_items, [:dedup_key], name: "work_items_dedup_key_index")
  end

  def down do
    drop_if_exists index(:work_items, [:dedup_key], name: "work_items_dedup_key_index")
    drop_if_exists index(:work_items, [:priority], name: "work_items_priority_index")
    drop_if_exists index(:work_items, [:status], name: "work_items_status_index")
    drop_if_exists index(:work_items, [:intake_id], name: "work_items_intake_id_index")
    drop_if_exists index(:work_items, [:observation_id], name: "work_items_observation_id_index")
    drop_if_exists index(:work_items, [:external_object_id], name: "work_items_external_object_id_index")
    drop_if_exists index(:work_items, [:event_id], name: "work_items_event_id_index")
    drop_if_exists index(:work_items, [:assessment_id], name: "work_items_assessment_id_index")
    drop_if_exists index(:work_items, [:managed_repo_id], name: "work_items_managed_repo_id_index")
    drop table(:work_items)
  end
end
