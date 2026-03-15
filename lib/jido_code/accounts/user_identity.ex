defmodule JidoCode.Accounts.UserIdentity do
  # covers: auth.provider_foundation.local_user_identity_mapping
  # covers: auth.provider_foundation.provider_catalog
  # covers: auth.provider_foundation.identity_auth_metadata
  # covers: auth.github_integration.local_user_mapping
  # covers: auth.provider_identity_linking.auth_timestamps
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Accounts,
    data_layer: AshPostgres.DataLayer

  @providers [:github, :gitlab, :bitbucket]

  postgres do
    table "user_identities"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
    define :get_by_id, action: :read, get_by: [:id]
    define :get_by_provider_subject, action: :read, get_by: [:provider, :provider_host, :provider_subject]
    define :list_for_user, action: :list_for_user
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      primary? true

      accept [
        :user_id,
        :provider,
        :provider_host,
        :provider_subject,
        :provider_login,
        :provider_email,
        :email_verified,
        :first_authenticated_at,
        :last_authenticated_at
      ]
    end

    update :update do
      primary? true

      accept [
        :provider_login,
        :provider_email,
        :email_verified,
        :first_authenticated_at,
        :last_authenticated_at
      ]
    end

    read :list_for_user do
      argument :user_id, :uuid do
        allow_nil? false
      end

      filter expr(user_id == ^arg(:user_id))
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

    attribute :provider_subject, :string do
      allow_nil? false
      constraints min_length: 1, trim?: true
      public? true
    end

    attribute :provider_login, :string do
      allow_nil? true
      constraints min_length: 1, trim?: true
      public? true
    end

    attribute :provider_email, :ci_string do
      allow_nil? true
      public? true
    end

    attribute :email_verified, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :first_authenticated_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :last_authenticated_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, JidoCode.Accounts.User do
      allow_nil? false
      public? true
    end
  end

  identities do
    identity :unique_provider_subject, [:provider, :provider_host, :provider_subject]
  end
end
