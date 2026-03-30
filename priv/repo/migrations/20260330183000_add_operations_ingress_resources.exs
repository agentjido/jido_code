defmodule JidoCode.Repo.Migrations.AddOperationsIngressResources do
  @moduledoc """
  Adds baseline ingress resources for external objects, observations, and operator intakes.
  """

  use Ecto.Migration

  def up do
    create table(:external_objects, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :provider, :text, null: false
      add :object_type, :text, null: false
      add :external_id, :text, null: false
      add :canonical_key, :text, null: false
      add :canonical_reference, :text
      add :title, :text
      add :url, :text
      add :status, :text
      add :payload, :map, null: false, default: %{}
      add :source_metadata, :map, null: false, default: %{}

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "external_objects_managed_repo_id_fkey",
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

    create unique_index(:external_objects, [:canonical_key],
             name: "external_objects_unique_canonical_key_index"
           )

    create index(:external_objects, [:managed_repo_id], name: "external_objects_managed_repo_id_index")

    create table(:observations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :source, :text, null: false
      add :category, :text, null: false
      add :summary, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :source_metadata, :map, null: false, default: %{}
      add :captured_by, :map, null: false, default: %{}
      add :observed_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "observations_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add(
        :external_object_id,
        references(:external_objects,
          column: :id,
          name: "observations_external_object_id_fkey",
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

    create index(:observations, [:managed_repo_id], name: "observations_managed_repo_id_index")
    create index(:observations, [:external_object_id], name: "observations_external_object_id_index")

    create table(:intakes, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :channel, :text, null: false
      add :intent, :text, null: false
      add :payload, :map, null: false, default: %{}
      add :source_metadata, :map, null: false, default: %{}
      add :requested_by, :map, null: false, default: %{}
      add :received_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "intakes_managed_repo_id_fkey",
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

    create index(:intakes, [:managed_repo_id], name: "intakes_managed_repo_id_index")
    create index(:intakes, [:channel, :intent], name: "intakes_channel_intent_index")
  end

  def down do
    drop_if_exists index(:intakes, [:channel, :intent], name: "intakes_channel_intent_index")
    drop_if_exists index(:intakes, [:managed_repo_id], name: "intakes_managed_repo_id_index")
    drop table(:intakes)

    drop_if_exists index(:observations, [:external_object_id], name: "observations_external_object_id_index")
    drop_if_exists index(:observations, [:managed_repo_id], name: "observations_managed_repo_id_index")
    drop table(:observations)

    drop_if_exists index(:external_objects, [:managed_repo_id], name: "external_objects_managed_repo_id_index")

    drop_if_exists unique_index(:external_objects, [:canonical_key],
                     name: "external_objects_unique_canonical_key_index"
                   )

    drop table(:external_objects)
  end
end
