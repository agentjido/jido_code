defmodule JidoCode.Governance.PostureCheck do
  # covers: architecture.repo_posture.posture_checks_preserve_explainable_links
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @level_pattern ~r/^(low|medium|high)$/
  @dimension_pattern ~r/^(execution_readiness|validation_reliability|review_burden|drift_rate|recovery_resilience|requirements_confidence)$/

  postgres do
    table "posture_checks"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_for_managed_repo_dimension, action: :upsert_for_managed_repo_dimension
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :repo_posture_id,
        :managed_repo_id,
        :observation_id,
        :assessment_id,
        :evidence_id,
        :dimension,
        :value,
        :summary,
        :details,
        :source,
        :checked_at
      ]

      change &normalize_checked_at/2
    end

    create :upsert_for_managed_repo_dimension do
      accept [
        :repo_posture_id,
        :managed_repo_id,
        :observation_id,
        :assessment_id,
        :evidence_id,
        :dimension,
        :value,
        :summary,
        :details,
        :source,
        :checked_at
      ]

      upsert? true
      upsert_identity :unique_managed_repo_dimension

      upsert_fields [
        :repo_posture_id,
        :observation_id,
        :assessment_id,
        :evidence_id,
        :value,
        :summary,
        :details,
        :source,
        :checked_at
      ]

      change &normalize_checked_at/2
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

    attribute :dimension, :string do
      allow_nil? false
      constraints match: @dimension_pattern
      public? true
    end

    attribute :value, :string do
      allow_nil? false
      constraints match: @level_pattern
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :details, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      default "posture_bridge"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :checked_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :repo_posture, JidoCode.Governance.RepoPosture do
      allow_nil? true
      public? true
      attribute_type :uuid
    end

    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :observation, JidoCode.Operations.Observation do
      allow_nil? true
      public? true
      attribute_type :uuid
    end

    belongs_to :assessment, JidoCode.Operations.Assessment do
      allow_nil? true
      public? true
      attribute_type :uuid
    end

    belongs_to :evidence, JidoCode.Governance.Evidence do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_managed_repo_dimension, [:managed_repo_id, :dimension]
  end

  defp normalize_checked_at(changeset, _context) do
    checked_at =
      changeset
      |> Ash.Changeset.get_attribute(:checked_at)
      |> case do
        %DateTime{} = datetime -> DateTime.truncate(datetime, :microsecond)
        _other -> DateTime.utc_now() |> DateTime.truncate(:microsecond)
      end

    Ash.Changeset.force_change_attribute(changeset, :checked_at, checked_at)
  end
end
