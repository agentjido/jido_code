defmodule JidoCode.Repo.Migrations.EnforceActiveWorkItemConversationUniqueness do
  @moduledoc """
  Enforces one active or paused productive conversation per work item.
  """

  use Ecto.Migration

  def up do
    create unique_index(
             :conversations,
             [:work_item_id],
             where: "work_item_id IS NOT NULL AND status IN ('active', 'paused')",
             name: "conversations_active_work_item_unique_index"
           )
  end

  def down do
    drop_if_exists unique_index(
                     :conversations,
                     [:work_item_id],
                     name: "conversations_active_work_item_unique_index"
                   )
  end
end
