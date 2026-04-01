defmodule JidoCode.Repo.Migrations.AddOperationsEventAndAssessmentResources do
  @moduledoc """
  Adds baseline event and assessment resources for control-plane work synthesis.
  """

  use Ecto.Migration

  def up do
    create table(:events, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :category, :text, null: false
      add :summary, :text, null: false
      add :correlation_key, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :source_metadata, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "events_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :external_object_id,
        references(:external_objects,
          column: :id,
          name: "events_external_object_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :observation_id,
        references(:observations,
          column: :id,
          name: "events_observation_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :intake_id,
        references(:intakes,
          column: :id,
          name: "events_intake_id_fkey",
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

    create index(:events, [:managed_repo_id], name: "events_managed_repo_id_index")
    create index(:events, [:external_object_id], name: "events_external_object_id_index")
    create index(:events, [:observation_id], name: "events_observation_id_index")
    create index(:events, [:intake_id], name: "events_intake_id_index")
    create index(:events, [:category], name: "events_category_index")
    create index(:events, [:correlation_key], name: "events_correlation_key_index")

    create table(:assessments, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :category, :text, null: false
      add :summary, :text, null: false
      add :priority, :text, null: false
      add :urgency, :text, null: false
      add :recommended_action, :text, null: false
      add :rationale, :text
      add :inputs, :map, null: false, default: %{}
      add :assessment_metadata, :map, null: false, default: %{}
      add :assessed_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "assessments_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :event_id,
        references(:events,
          column: :id,
          name: "assessments_event_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :external_object_id,
        references(:external_objects,
          column: :id,
          name: "assessments_external_object_id_fkey",
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

    create index(:assessments, [:managed_repo_id], name: "assessments_managed_repo_id_index")
    create index(:assessments, [:event_id], name: "assessments_event_id_index")

    create index(:assessments, [:external_object_id],
             name: "assessments_external_object_id_index"
           )

    create index(:assessments, [:category], name: "assessments_category_index")
    create index(:assessments, [:priority], name: "assessments_priority_index")
  end

  def down do
    drop_if_exists index(:assessments, [:priority], name: "assessments_priority_index")
    drop_if_exists index(:assessments, [:category], name: "assessments_category_index")

    drop_if_exists index(:assessments, [:external_object_id],
                     name: "assessments_external_object_id_index"
                   )

    drop_if_exists index(:assessments, [:event_id], name: "assessments_event_id_index")

    drop_if_exists index(:assessments, [:managed_repo_id],
                     name: "assessments_managed_repo_id_index"
                   )

    drop table(:assessments)

    drop_if_exists index(:events, [:correlation_key], name: "events_correlation_key_index")
    drop_if_exists index(:events, [:category], name: "events_category_index")
    drop_if_exists index(:events, [:intake_id], name: "events_intake_id_index")
    drop_if_exists index(:events, [:observation_id], name: "events_observation_id_index")
    drop_if_exists index(:events, [:external_object_id], name: "events_external_object_id_index")
    drop_if_exists index(:events, [:managed_repo_id], name: "events_managed_repo_id_index")
    drop table(:events)
  end
end
