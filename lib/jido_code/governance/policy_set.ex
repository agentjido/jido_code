defmodule JidoCode.Governance.PolicySet do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn
  alias JidoCode.Governance.ReviewPolicy

  postgres do
    table "policy_sets"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_default_for_managed_repo, action: :upsert_default_for_managed_repo
    define :get_by_managed_repo_name, action: :read, get_by: [:managed_repo_id, :name]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :name,
        :review_policy,
        :policy_metadata
      ]
    end

    create :upsert_default_for_managed_repo do
      accept [
        :managed_repo_id,
        :review_policy,
        :policy_metadata
      ]

      upsert? true
      upsert_identity :unique_managed_repo_name
      upsert_fields [:review_policy, :policy_metadata]

      change set_attribute(:name, "default")
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

    attribute :name, :string do
      allow_nil? false
      default "default"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :review_policy, ReviewPolicy do
      allow_nil? false
      public? true
    end

    attribute :policy_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_managed_repo_name, [:managed_repo_id, :name]
  end
end
