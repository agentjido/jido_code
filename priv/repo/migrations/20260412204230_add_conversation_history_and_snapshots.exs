defmodule JidoCode.Repo.Migrations.AddConversationHistoryAndSnapshots do
  @moduledoc """
  Adds durable conversation event history and materialized snapshots.
  """

  use Ecto.Migration

  def up do
    create table(:conversation_events, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add(
        :conversation_id,
        references(:conversations,
          column: :id,
          name: "conversation_events_conversation_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add :sequence, :bigint, null: false
      add :name, :text, null: false
      add :actor, :map, null: false, default: %{}
      add :message_id, :text
      add :turn_id, :text
      add :child_work_id, :text
      add :tool_call_id, :text
      add :correlation, :map, null: false, default: %{}
      add :payload, :map, null: false, default: %{}
      add :occurred_at, :utc_datetime_usec, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:conversation_events, [:conversation_id, :sequence],
             name: "conversation_events_conversation_sequence_index"
           )

    create index(:conversation_events, [:conversation_id], name: "conversation_events_conversation_id_index")
    create index(:conversation_events, [:name], name: "conversation_events_name_index")
    create index(:conversation_events, [:turn_id], name: "conversation_events_turn_id_index")
    create index(:conversation_events, [:child_work_id], name: "conversation_events_child_work_id_index")

    create table(:conversation_snapshots, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true

      add(
        :conversation_id,
        references(:conversations,
          column: :id,
          name: "conversation_snapshots_conversation_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "conversation_snapshots_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :work_item_id,
        references(:work_items,
          column: :id,
          name: "conversation_snapshots_work_item_id_fkey",
          type: :uuid,
          prefix: "public"
        )
      )

      add :status, :text, null: false, default: "active"
      add :admission_paused, :boolean, null: false, default: false
      add :child_execution_paused, :boolean, null: false, default: false
      add :active_turn_id, :text
      add :active_child_work_id, :text
      add :queued_turn_ids, {:array, :text}, null: false, default: []
      add :turns, {:array, :map}, null: false, default: []
      add :child_works, {:array, :map}, null: false, default: []
      add :control_history, {:array, :map}, null: false, default: []
      add :last_event_sequence, :bigint, null: false, default: 0
      add :event_count, :bigint, null: false, default: 0
      add :events, {:array, :map}, null: false, default: []
      add :shared_context, :map, null: false, default: %{}
      add :captured_at, :utc_datetime_usec, null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:conversation_snapshots, [:conversation_id],
             name: "conversation_snapshots_conversation_id_index"
           )

    create index(:conversation_snapshots, [:managed_repo_id],
             name: "conversation_snapshots_managed_repo_id_index"
           )

    create index(:conversation_snapshots, [:work_item_id],
             name: "conversation_snapshots_work_item_id_index"
           )

    create index(:conversation_snapshots, [:status], name: "conversation_snapshots_status_index")
  end

  def down do
    drop_if_exists index(:conversation_snapshots, [:status], name: "conversation_snapshots_status_index")

    drop_if_exists index(:conversation_snapshots, [:work_item_id],
                     name: "conversation_snapshots_work_item_id_index"
                   )

    drop_if_exists index(:conversation_snapshots, [:managed_repo_id],
                     name: "conversation_snapshots_managed_repo_id_index"
                   )

    drop_if_exists unique_index(:conversation_snapshots, [:conversation_id],
                     name: "conversation_snapshots_conversation_id_index"
                   )

    drop table(:conversation_snapshots)

    drop_if_exists index(:conversation_events, [:child_work_id],
                     name: "conversation_events_child_work_id_index"
                   )

    drop_if_exists index(:conversation_events, [:turn_id], name: "conversation_events_turn_id_index")
    drop_if_exists index(:conversation_events, [:name], name: "conversation_events_name_index")

    drop_if_exists index(:conversation_events, [:conversation_id],
                     name: "conversation_events_conversation_id_index"
                   )

    drop_if_exists unique_index(:conversation_events, [:conversation_id, :sequence],
                     name: "conversation_events_conversation_sequence_index"
                   )

    drop table(:conversation_events)
  end
end
