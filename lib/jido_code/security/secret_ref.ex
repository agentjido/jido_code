defmodule JidoCode.Security.SecretRef do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Security,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "secret_refs"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :list_metadata, action: :metadata
    define :get_by_scope_name, action: :read, get_by: [:scope, :name]
  end

  actions do
    defaults [:destroy]

    create :create do
      accept [:scope, :name, :ciphertext, :key_version, :source, :last_rotated_at, :expires_at]
      upsert? true
      upsert_identity :unique_scope_name
      upsert_fields [:ciphertext, :key_version, :source, :last_rotated_at, :expires_at]
      primary? true

      change fn changeset, _context ->
        last_rotated_at =
          changeset
          |> Ash.Changeset.get_attribute(:last_rotated_at)
          |> case do
            %DateTime{} = datetime -> datetime
            _other -> DateTime.utc_now() |> DateTime.truncate(:second)
          end

        Ash.Changeset.force_change_attribute(changeset, :last_rotated_at, last_rotated_at)
      end
    end

    read :read do
      primary? true
    end

    read :metadata do
      prepare build(select: [:id, :scope, :name, :key_version, :source, :last_rotated_at, :expires_at])
      prepare build(sort: [updated_at: :desc])
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:update) do
      authorize_if always()
    end

    policy action_type(:destroy) do
      authorize_if always()
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: [:instance, :project, :integration]
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, trim?: true
      public? true
    end

    attribute :ciphertext, :string do
      allow_nil? false
      sensitive? true
      public? false
    end

    attribute :key_version, :integer do
      allow_nil? false
      default 1
      public? true
    end

    attribute :source, :atom do
      allow_nil? false
      constraints one_of: [:env, :onboarding, :rotation]
      default :onboarding
      public? true
    end

    attribute :last_rotated_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :expires_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_scope_name, [:scope, :name]
  end
end
