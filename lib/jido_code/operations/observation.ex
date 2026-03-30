defmodule JidoCode.Operations.Observation do
  # covers: architecture.demand_ingress.observation_captures_repo_and_system_facts
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "observations"
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
        :external_object_id,
        :source,
        :category,
        :summary,
        :payload,
        :source_metadata,
        :captured_by,
        :observed_at
      ]

      change fn changeset, _context ->
        observed_at =
          changeset
          |> Ash.Changeset.get_attribute(:observed_at)
          |> normalize_datetime()

        Ash.Changeset.force_change_attribute(changeset, :observed_at, observed_at)
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

    attribute :source, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :category, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
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

    attribute :captured_by, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :observed_at, :utc_datetime_usec do
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

    belongs_to :external_object, JidoCode.Operations.ExternalObject do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
