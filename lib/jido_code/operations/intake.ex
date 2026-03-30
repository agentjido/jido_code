defmodule JidoCode.Operations.Intake do
  # covers: architecture.demand_ingress.intake_captures_operator_and_trusted_requests
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "intakes"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :channel,
        :intent,
        :payload,
        :source_metadata,
        :requested_by,
        :received_at
      ]

      change fn changeset, _context ->
        received_at =
          changeset
          |> Ash.Changeset.get_attribute(:received_at)
          |> normalize_datetime()

        Ash.Changeset.force_change_attribute(changeset, :received_at, received_at)
      end
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

    attribute :channel, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :intent, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
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

    attribute :requested_by, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :received_at, :utc_datetime_usec do
      allow_nil? false
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

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
