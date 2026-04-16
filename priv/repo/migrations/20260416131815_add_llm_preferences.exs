defmodule JidoCode.Repo.Migrations.AddLlmPreferences do
  use Ecto.Migration

  def change do
    create table(:llm_preferences, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :managed_repo_id, :uuid, null: false
      add :enabled_providers, {:array, :text}, default: ["anthropic"]
      add :default_provider, :text, default: "anthropic"
      add :default_model, :text, default: "claude-3-5-sonnet-20250929"
      add :require_capabilities, :map, default: "{}"
      add :max_context_length, :integer
      add :allow_custom_models, :boolean, default: true
      timestamps()
    end

    create unique_index(:llm_preferences, [:managed_repo_id])
  end
end
