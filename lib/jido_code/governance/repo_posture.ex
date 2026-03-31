defmodule JidoCode.Governance.RepoPosture do
  # covers: architecture.repo_posture.repo_posture_summarizes_trust_dimensions
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @level_pattern ~r/^(low|medium|high)$/
  @supervision_mode_pattern ~r/^(directed|guided|delegated|autonomous)$/
  @escalation_status_pattern ~r/^(normal|review|algedonic)$/

  postgres do
    table "repo_postures"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_for_managed_repo, action: :upsert_for_managed_repo
    define :get_by_managed_repo_id, action: :read, get_by: [:managed_repo_id]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :summary,
        :overall_trust,
        :execution_readiness,
        :validation_reliability,
        :review_burden,
        :drift_rate,
        :recovery_resilience,
        :requirements_confidence,
        :supervision_mode,
        :escalation_status,
        :algedonic_check_id,
        :contributing_check_ids,
        :posture_metadata
      ]
    end

    create :upsert_for_managed_repo do
      accept [
        :managed_repo_id,
        :summary,
        :overall_trust,
        :execution_readiness,
        :validation_reliability,
        :review_burden,
        :drift_rate,
        :recovery_resilience,
        :requirements_confidence,
        :supervision_mode,
        :escalation_status,
        :algedonic_check_id,
        :contributing_check_ids,
        :posture_metadata
      ]

      upsert? true
      upsert_identity :unique_managed_repo

      upsert_fields [
        :summary,
        :overall_trust,
        :execution_readiness,
        :validation_reliability,
        :review_burden,
        :drift_rate,
        :recovery_resilience,
        :requirements_confidence,
        :supervision_mode,
        :escalation_status,
        :algedonic_check_id,
        :contributing_check_ids,
        :posture_metadata
      ]
    end

    read :read do
      primary? true
    end
  end

  policies do
    policy action_type(:read) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator, :run_worker]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [:admin, :operator, :factory_system, :managed_repo_orchestrator]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :overall_trust, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :execution_readiness, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :validation_reliability, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :review_burden, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :drift_rate, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :recovery_resilience, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :requirements_confidence, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :supervision_mode, :string do
      allow_nil? false
      default "guided"
      constraints match: @supervision_mode_pattern
      public? true
    end

    attribute :escalation_status, :string do
      allow_nil? false
      default "normal"
      constraints match: @escalation_status_pattern
      public? true
    end

    attribute :algedonic_check_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :contributing_check_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
    end

    attribute :posture_metadata, :map do
      allow_nil? false
      default %{}
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

    belongs_to :algedonic_check, JidoCode.Governance.PostureCheck do
      allow_nil? true
      public? true
      attribute_type :uuid
      source_attribute :algedonic_check_id
    end
  end

  identities do
    identity :unique_managed_repo, [:managed_repo_id]
  end
end
