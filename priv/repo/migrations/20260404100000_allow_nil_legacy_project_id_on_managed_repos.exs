defmodule JidoCode.Repo.Migrations.AllowNilLegacyProjectIdOnManagedRepos do
  @moduledoc """
  Allows managed repositories provisioned directly from canonical source identity
  to omit any legacy project linkage.
  """

  use Ecto.Migration

  def up do
    alter table(:managed_repos) do
      modify :legacy_project_id, :uuid, null: true
    end
  end

  def down do
    execute("""
    DELETE FROM managed_repos
    WHERE legacy_project_id IS NULL
    """)

    alter table(:managed_repos) do
      modify :legacy_project_id, :uuid, null: false
    end
  end
end
