defmodule JidoCode.Repo.Migrations.AddGovernancePolicySets do
  @moduledoc """
  Adds the initial governance policy set resource for managed repositories.
  """

  use Ecto.Migration

  def up do
    create table(:policy_sets, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false, default: "default"
      add :review_policy, :map, null: false
      add :policy_metadata, :map, null: false, default: %{}

      add(
        :managed_repo_id,
        references(:managed_repos,
          column: :id,
          name: "policy_sets_managed_repo_id_fkey",
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

    create unique_index(:policy_sets, [:managed_repo_id, :name],
             name: "policy_sets_unique_managed_repo_name_index"
           )
  end

  def down do
    drop_if_exists unique_index(:policy_sets, [:managed_repo_id, :name],
                     name: "policy_sets_unique_managed_repo_name_index"
                   )

    drop table(:policy_sets)
  end
end
