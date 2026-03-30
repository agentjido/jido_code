defmodule JidoCode.Control.SourceRepo do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Control,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @providers [:github, :gitlab, :bitbucket]

  postgres do
    table "source_repos"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_identity, action: :upsert_identity
    define :get_by_provider_and_full_name, action: :read, get_by: [:provider, :full_name]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :provider,
        :owner,
        :name,
        :full_name,
        :default_branch,
        :source_metadata
      ]
    end

    create :upsert_identity do
      accept [
        :provider,
        :owner,
        :name,
        :full_name,
        :default_branch,
        :source_metadata
      ]

      upsert? true
      upsert_identity :unique_provider_full_name
      upsert_fields [:owner, :name, :default_branch, :source_metadata]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      constraints one_of: @providers
      public? true
    end

    attribute :owner, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :full_name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :default_branch, :string do
      allow_nil? false
      default "main"
      constraints min_length: 1, max_length: 255, trim?: true
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

  identities do
    identity :unique_provider_full_name, [:provider, :full_name]
  end
end
