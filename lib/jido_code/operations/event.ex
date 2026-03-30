defmodule JidoCode.Operations.Event do
  # covers: architecture.event_assessment_synthesis.event_records_derived_from_ingress
  # covers: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "events"
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
        :observation_id,
        :intake_id,
        :category,
        :summary,
        :correlation_key,
        :payload,
        :source_metadata,
        :occurred_at
      ]

      change fn changeset, _context ->
        occurred_at =
          changeset
          |> Ash.Changeset.get_attribute(:occurred_at)
          |> normalize_datetime()

        Ash.Changeset.force_change_attribute(changeset, :occurred_at, occurred_at)
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
                      :managed_repo_orchestrator
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

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

    attribute :correlation_key, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 1024, trim?: true
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

    attribute :occurred_at, :utc_datetime_usec do
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

    belongs_to :observation, JidoCode.Operations.Observation do
      allow_nil? true
      public? true
      attribute_type :uuid
    end

    belongs_to :intake, JidoCode.Operations.Intake do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
