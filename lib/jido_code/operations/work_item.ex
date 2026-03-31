defmodule JidoCode.Operations.WorkItem do
  # covers: architecture.work_synthesis.work_item_is_canonical_operational_record
  # covers: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  # covers: architecture.work_synthesis.work_item_creation_can_stop_before_execution
  # covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  # covers: architecture.work_synthesis.work_item_auditability_preserved
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Operations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @statuses [:open, :in_progress, :blocked, :completed, :cancelled, :suppressed]
  @priority_levels [:critical, :high, :medium, :low]

  postgres do
    table "work_items"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :update
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :assessment_id,
        :event_id,
        :external_object_id,
        :observation_id,
        :intake_id,
        :category,
        :status,
        :priority,
        :recommended_action,
        :summary,
        :dedup_key,
        :initiating_actor,
        :work_metadata,
        :audit_log,
        :opened_at,
        :last_assessed_at
      ]

      change fn changeset, _context ->
        opened_at =
          changeset
          |> Ash.Changeset.get_attribute(:opened_at)
          |> normalize_datetime()

        changeset
        |> Ash.Changeset.force_change_attribute(:opened_at, opened_at)
        |> ensure_last_assessed_at()
      end
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :assessment_id,
        :event_id,
        :external_object_id,
        :observation_id,
        :intake_id,
        :category,
        :status,
        :priority,
        :recommended_action,
        :summary,
        :dedup_key,
        :initiating_actor,
        :work_metadata,
        :audit_log,
        :last_assessed_at
      ]

      change &ensure_last_assessed_at/2
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

    policy action_type([:create, :update]) do
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

    attribute :status, :atom do
      allow_nil? false
      default :open
      constraints one_of: @statuses
      public? true
    end

    attribute :priority, :atom do
      allow_nil? false
      constraints one_of: @priority_levels
      public? true
    end

    attribute :recommended_action, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :dedup_key, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 1024, trim?: true
      public? true
    end

    attribute :initiating_actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :work_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :audit_log, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :opened_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :last_assessed_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :assessment, JidoCode.Operations.Assessment do
      allow_nil? false
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

  defp ensure_last_assessed_at(changeset, _context) do
    ensure_last_assessed_at(changeset)
  end

  defp ensure_last_assessed_at(changeset) do
    last_assessed_at =
      changeset
      |> Ash.Changeset.get_attribute(:last_assessed_at)
      |> normalize_datetime()

    Ash.Changeset.force_change_attribute(changeset, :last_assessed_at, last_assessed_at)
  end

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
