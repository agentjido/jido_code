defmodule JidoCode.AuthProviders.ProviderConfig do
  # covers: auth.provider_foundation.provider_catalog
  # covers: auth.provider_foundation.provider_login_configuration
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.AuthProviders,
    data_layer: AshPostgres.DataLayer

  @providers [:github, :gitlab, :bitbucket]
  @allowlist_modes [:none, :users, :organizations, :teams, :groups, :workspaces]

  postgres do
    table "auth_provider_configs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :upsert, action: :upsert
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_provider_host, action: :read, get_by: [:provider, :provider_host]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :provider,
        :provider_host,
        :enabled,
        :login_enabled,
        :allowlist_mode,
        :allowlist_values,
        :broker_issuer,
        :broker_audience,
        :broker_base_url
      ]
    end

    create :upsert do
      accept [
        :provider,
        :provider_host,
        :enabled,
        :login_enabled,
        :allowlist_mode,
        :allowlist_values,
        :broker_issuer,
        :broker_audience,
        :broker_base_url
      ]

      upsert? true
      upsert_identity :unique_provider_host

      upsert_fields [
        :enabled,
        :login_enabled,
        :allowlist_mode,
        :allowlist_values,
        :broker_issuer,
        :broker_audience,
        :broker_base_url
      ]
    end

    update :update do
      primary? true

      accept [
        :enabled,
        :login_enabled,
        :allowlist_mode,
        :allowlist_values,
        :broker_issuer,
        :broker_audience,
        :broker_base_url
      ]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :provider, :atom do
      allow_nil? false
      constraints one_of: @providers
      public? true
    end

    attribute :provider_host, :string do
      allow_nil? false
      constraints min_length: 1, trim?: true
      public? true
    end

    attribute :enabled, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :login_enabled, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :allowlist_mode, :atom do
      allow_nil? false
      default :none
      constraints one_of: @allowlist_modes
      public? true
    end

    attribute :allowlist_values, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :broker_issuer, :string do
      allow_nil? true
      constraints trim?: true
      public? true
    end

    attribute :broker_audience, :string do
      allow_nil? true
      constraints trim?: true
      public? true
    end

    attribute :broker_base_url, :string do
      allow_nil? true
      constraints trim?: true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_provider_host, [:provider, :provider_host]
  end
end
