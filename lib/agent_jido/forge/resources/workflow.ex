defmodule AgentJido.Forge.Resources.Workflow do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "forge_workflows"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :name,
        :description,
        :steps,
        :timeout_ms,
        :on_error,
        :max_retries,
        :tags,
        :metadata
      ]
    end

    update :update do
      require_atomic? false

      accept [
        :name,
        :description,
        :steps,
        :timeout_ms,
        :on_error,
        :max_retries,
        :tags,
        :metadata
      ]

      change fn changeset, _ ->
        current = Ash.Changeset.get_attribute(changeset, :version) || 0
        Ash.Changeset.change_attribute(changeset, :version, current + 1)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :description, :string, public?: true
    attribute :version, :integer, default: 1, public?: true

    attribute :steps, {:array, :map}, allow_nil?: false, public?: true

    attribute :timeout_ms, :integer, default: 3_600_000, public?: true
    attribute :on_error, :atom, default: :halt, public?: true
    attribute :max_retries, :integer, default: 0, public?: true

    attribute :tags, {:array, :string}, default: [], public?: true
    attribute :metadata, :map, default: %{}, public?: true

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_name, [:name]
  end
end
