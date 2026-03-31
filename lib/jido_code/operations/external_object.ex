defmodule JidoCode.Operations.ExternalObject do
  # covers: architecture.demand_ingress.external_object_tracks_repo_external_entities
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @providers [:github]
  @object_types [:github_issue, :github_pull_request, :github_repository]

  postgres do
    table "external_objects"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_observed, action: :upsert_observed
    define :get_by_canonical_key, action: :read, get_by: [:canonical_key]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :provider,
        :object_type,
        :external_id,
        :canonical_key,
        :canonical_reference,
        :title,
        :url,
        :status,
        :payload,
        :source_metadata
      ]
    end

    create :upsert_observed do
      accept [
        :managed_repo_id,
        :provider,
        :object_type,
        :external_id,
        :canonical_key,
        :canonical_reference,
        :title,
        :url,
        :status,
        :payload,
        :source_metadata
      ]

      upsert? true
      upsert_identity :unique_canonical_key

      upsert_fields [
        :managed_repo_id,
        :canonical_reference,
        :title,
        :url,
        :status,
        :payload,
        :source_metadata
      ]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :managed_repo_orchestrator,
                      :run_worker
                    ]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system,
                      :managed_repo_orchestrator,
                      :external_ingress
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      constraints one_of: @providers
      public? true
    end

    attribute :object_type, :atom do
      allow_nil? false
      constraints one_of: @object_types
      public? true
    end

    attribute :external_id, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :canonical_key, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 512, trim?: true
      public? true
    end

    attribute :canonical_reference, :string do
      allow_nil? true
      constraints min_length: 1, max_length: 512, trim?: true
      public? true
    end

    attribute :title, :string do
      allow_nil? true
      constraints max_length: 2048, trim?: true
      public? true
    end

    attribute :url, :string do
      allow_nil? true
      constraints max_length: 4096, trim?: true
      public? true
    end

    attribute :status, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :payload, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_canonical_key, [:canonical_key]
  end
end
