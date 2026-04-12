defmodule JidoCode.Repo.Migrations.AddConversationsResource do
  @moduledoc """
  Adds durable conversations that bind coding sessions to managed repositories and optional work items.
  """

  use Ecto.Migration

  def up do
    create table(:conversations, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :status, :text, null: false, default: "active"
      add :scope, :text, null: false
      add :attachment_mode, :text, null: false
      add :source, :text, null: false
      add :title, :text
      add :objective, :text
      add :initiating_actor, :map, null: false, default: %{}
      add :source_metadata, :map, null: false, default: %{}
      add :conversation_metadata, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :last_activity_at, :utc_datetime_usec, null: false

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "conversations_managed_repo_id_fkey",
          type: :uuid,
          prefix: "public"
        ),
        null: false
      )

      add(
        :work_item_id,
        references(:work_items,
          column: :id,
          name: "conversations_work_item_id_fkey",
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

    create index(:conversations, [:managed_repo_id], name: "conversations_managed_repo_id_index")
    create index(:conversations, [:work_item_id], name: "conversations_work_item_id_index")
    create index(:conversations, [:status], name: "conversations_status_index")
    create index(:conversations, [:scope], name: "conversations_scope_index")
  end

  def down do
    drop_if_exists index(:conversations, [:scope], name: "conversations_scope_index")
    drop_if_exists index(:conversations, [:status], name: "conversations_status_index")

    drop_if_exists index(:conversations, [:work_item_id],
                     name: "conversations_work_item_id_index"
                   )

    drop_if_exists index(:conversations, [:managed_repo_id],
                     name: "conversations_managed_repo_id_index"
                   )

    drop table(:conversations)
  end
end
