defmodule JidoCode.Setup.SystemConfigRecord do
  # covers: setup.runtime_environment_defaults.selection_persisted_in_database_backed_system_config
  # covers: setup.onboarding.runtime_environment_selection_persisted_metadata
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Setup,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "system_configs"
    repo JidoCode.Repo
  end

  code_interface do
    define :upsert_singleton, action: :upsert_singleton
    define :read_all, action: :read
  end

  actions do
    defaults [:read]

    create :upsert_singleton do
      primary? true
      upsert? true
      upsert_identity :unique_key

      accept [
        :onboarding_completed,
        :onboarding_step,
        :onboarding_state,
        :default_environment,
        :workspace_root
      ]

      change set_attribute(:key, "singleton")
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :key, :string do
      allow_nil? false
      default "singleton"
      public? false
    end

    attribute :onboarding_completed, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :onboarding_step, :integer do
      allow_nil? false
      default 1
      constraints min: 1
      public? true
    end

    attribute :onboarding_state, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :default_environment, :atom do
      allow_nil? false
      default :sprite
      constraints one_of: [:sprite, :local]
      public? true
    end

    attribute :workspace_root, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_key, [:key]
  end
end
