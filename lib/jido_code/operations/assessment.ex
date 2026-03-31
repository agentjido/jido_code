defmodule JidoCode.Operations.Assessment do
  # covers: architecture.event_assessment_synthesis.assessment_records_interpret_events
  # covers: architecture.event_assessment_synthesis.assessment_priority_and_next_action
  # covers: architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @priority_levels [:critical, :high, :medium, :low]
  @urgency_levels [:immediate, :high, :medium, :low]

  postgres do
    table "assessments"
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
        :event_id,
        :external_object_id,
        :category,
        :summary,
        :priority,
        :urgency,
        :recommended_action,
        :rationale,
        :inputs,
        :assessment_metadata,
        :assessed_at
      ]

      change fn changeset, _context ->
        assessed_at =
          changeset
          |> Ash.Changeset.get_attribute(:assessed_at)
          |> normalize_datetime()

        Ash.Changeset.force_change_attribute(changeset, :assessed_at, assessed_at)
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

    attribute :priority, :atom do
      allow_nil? false
      constraints one_of: @priority_levels
      public? true
    end

    attribute :urgency, :atom do
      allow_nil? false
      constraints one_of: @urgency_levels
      public? true
    end

    attribute :recommended_action, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :rationale, :string do
      allow_nil? true
      constraints max_length: 4096, trim?: true
      public? true
    end

    attribute :inputs, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :assessment_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :assessed_at, :utc_datetime_usec do
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

    belongs_to :event, JidoCode.Operations.Event do
      allow_nil? false
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
