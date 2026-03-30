defmodule JidoCode.Control.ManagedRepo do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Control,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "managed_repos"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_projection, action: :upsert_projection
    define :get_by_legacy_project_id, action: :read, get_by: [:legacy_project_id]
    define :get_by_source_repo_id, action: :read, get_by: [:source_repo_id]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :display_name,
        :legacy_project_id,
        :source_repo_id,
        :workspace_settings,
        :execution_settings,
        :integration_settings
      ]
    end

    create :upsert_projection do
      accept [
        :display_name,
        :legacy_project_id,
        :source_repo_id,
        :workspace_settings,
        :execution_settings,
        :integration_settings
      ]

      upsert? true
      upsert_identity :unique_legacy_project_id

      upsert_fields [
        :display_name,
        :source_repo_id,
        :workspace_settings,
        :execution_settings,
        :integration_settings
      ]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator, :run_worker]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn, classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :display_name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :legacy_project_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :workspace_settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :execution_settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :integration_settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :source_repo, JidoCode.Control.SourceRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    has_one :policy_set, JidoCode.Governance.PolicySet do
      destination_attribute :managed_repo_id
    end
  end

  identities do
    identity :unique_legacy_project_id, [:legacy_project_id]
    identity :unique_source_repo, [:source_repo_id]
  end
end
