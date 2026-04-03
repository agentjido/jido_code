defmodule JidoCode.Security.SecretLifecycleAudit do
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Security,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "secret_lifecycle_audits"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
  end

  actions do
    create :create do
      accept [
        :secret_ref_id,
        :scope,
        :name,
        :action_type,
        :outcome_status,
        :actor_id,
        :actor_email,
        :occurred_at
      ]

      primary? true

      change fn changeset, _context ->
        occurred_at =
          changeset
          |> Ash.Changeset.get_attribute(:occurred_at)
          |> case do
            %DateTime{} = datetime -> datetime
            _other -> DateTime.utc_now() |> DateTime.truncate(:second)
          end

        Ash.Changeset.force_change_attribute(changeset, :occurred_at, occurred_at)
      end
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
  end

  attributes do
    uuid_primary_key :id

    attribute :secret_ref_id, :uuid do
      allow_nil? false
      public? true
    end

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

    attribute :action_type, :atom do
      allow_nil? false
      constraints one_of: [:create, :rotate, :revoke]
      public? true
    end

    attribute :outcome_status, :atom do
      allow_nil? false
      constraints one_of: [:succeeded, :failed]
      default :succeeded
      public? true
    end

    attribute :actor_id, :string do
      allow_nil? false
      constraints min_length: 1, trim?: true
      public? true
    end

    attribute :actor_email, :string do
      allow_nil? true
      constraints trim?: true
      public? true
    end

    attribute :occurred_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end
end
