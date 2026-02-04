defmodule AgentJido.Forge.Resources.Session do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshJsonApi.Resource]

  postgres do
    table "forge_sessions"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :runner_type, :runner_config, :spec, :metadata]
      change set_attribute(:phase, :created)
    end

    update :start do
      accept []
      change set_attribute(:phase, :provisioning)
      change set_attribute(:started_at, &DateTime.utc_now/0)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :provision_complete do
      accept [:sprite_id, :sprite_name]
      change set_attribute(:phase, :bootstrapping)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :bootstrap_complete do
      change set_attribute(:phase, :ready)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :begin_execution do
      require_atomic? false
      change set_attribute(:phase, :running)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
      change atomic_update(:execution_count, expr(execution_count + 1))
    end

    update :execution_complete do
      require_atomic? false
      accept [:runner_state, :output_buffer]

      argument :result_status, :atom do
        constraints one_of: [:completed, :needs_continuation, :needs_input, :failed]
        allow_nil? false
      end

      change fn changeset, _context ->
        status = Ash.Changeset.get_argument(changeset, :result_status)

        phase =
          case status do
            :completed -> :completed
            :needs_continuation -> :ready
            :needs_input -> :needs_input
            :failed -> :failed
          end

        Ash.Changeset.change_attribute(changeset, :phase, phase)
      end

      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :apply_input do
      accept [:runner_state]
      change set_attribute(:phase, :ready)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :record_checkpoint do
      accept [:last_checkpoint_id]
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    update :mark_failed do
      accept [:last_error]
      change set_attribute(:phase, :failed)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :cancel do
      change set_attribute(:phase, :cancelled)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :complete do
      change set_attribute(:phase, :completed)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
      change set_attribute(:completed_at, &DateTime.utc_now/0)
    end

    update :begin_resume do
      change set_attribute(:phase, :resuming)
      change set_attribute(:last_activity_at, &DateTime.utc_now/0)
    end

    read :list_active do
      filter expr(phase in [:created, :provisioning, :bootstrapping, :ready, :running, :needs_input, :resuming])
    end

    read :list_resumable do
      filter expr(phase in [:failed, :cancelled] and not is_nil(last_checkpoint_id))
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :phase, :atom do
      constraints one_of: [
                    :created,
                    :provisioning,
                    :bootstrapping,
                    :ready,
                    :running,
                    :needs_input,
                    :completed,
                    :failed,
                    :cancelled,
                    :resuming
                  ]

      default :created
      allow_nil? false
      public? true
    end

    attribute :runner_type, :atom do
      constraints one_of: [:shell, :claude_code, :workflow, :custom]
      default :shell
      allow_nil? false
      public? true
    end

    attribute :runner_config, :map do
      default %{}
      public? true
    end

    attribute :runner_state, :map do
      default %{}
      description "Mutable state maintained by the runner between executions"
    end

    attribute :spec, :map do
      default %{}
      description "Session specification (sprite config, bootstrap steps, env)"
    end

    attribute :sprite_id, :string do
      description "ID of the provisioned sprite (from Sprites API)"
    end

    attribute :sprite_name, :string do
      description "Name of the sprite container"
    end

    attribute :last_checkpoint_id, :string do
      description "Most recent Sprites checkpoint ID for resumption"
    end

    attribute :execution_count, :integer do
      default 0
      description "Number of runner executions"
    end

    attribute :output_buffer, :string do
      description "Recent output (truncated)"
    end

    attribute :last_error, :map do
      description "Last error details"
    end

    attribute :metadata, :map do
      default %{}
      description "Arbitrary metadata"
    end

    attribute :started_at, :utc_datetime_usec
    attribute :completed_at, :utc_datetime_usec
    attribute :last_activity_at, :utc_datetime_usec

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :exec_sessions, AgentJido.Forge.Resources.ExecSession do
      destination_attribute :session_id
    end

    has_many :events, AgentJido.Forge.Resources.Event do
      destination_attribute :session_id
    end

    has_many :checkpoints, AgentJido.Forge.Resources.Checkpoint do
      destination_attribute :session_id
    end
  end

  calculations do
    calculate :duration_ms,
              :integer,
              expr(
                if not is_nil(completed_at) and not is_nil(started_at) do
                  fragment("EXTRACT(EPOCH FROM (? - ?)) * 1000", completed_at, started_at)
                end
              )

    calculate :is_terminal?, :boolean, expr(phase in [:completed, :failed, :cancelled])
  end

  identities do
    identity :unique_name, [:name]
  end
end
