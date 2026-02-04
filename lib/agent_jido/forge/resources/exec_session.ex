defmodule AgentJido.Forge.Resources.ExecSession do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "forge_exec_sessions"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read]

    create :start do
      accept [:session_id, :sequence, :command, :sprites_session_id, :metadata]
      change set_attribute(:status, :started)
    end

    update :complete do
      accept [:exit_code, :output, :cost_usd, :duration_ms, :metadata]
      require_atomic? false

      argument :result_status, :atom do
        constraints one_of: [:completed, :needs_continuation, :needs_input, :failed, :timeout]
        allow_nil? false
      end

      change fn changeset, _context ->
        result_status = Ash.Changeset.get_argument(changeset, :result_status)
        output = Ash.Changeset.get_attribute(changeset, :output) || ""

        changeset
        |> Ash.Changeset.change_attribute(:status, result_status)
        |> Ash.Changeset.change_attribute(:completed_at, DateTime.utc_now())
        |> Ash.Changeset.change_attribute(:output_size_bytes, byte_size(output))
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sequence, :integer do
      allow_nil? false
      public? true
      description "Execution number within session (1-indexed)"
    end

    attribute :status, :atom do
      constraints one_of: [:started, :completed, :needs_continuation, :needs_input, :failed, :timeout]
      default :started
      allow_nil? false
      public? true
    end

    attribute :command, :string do
      public? true
      description "Command that was executed"
    end

    attribute :exit_code, :integer, public?: true

    attribute :output, :string do
      public? true
      description "Full output from this execution"
    end

    attribute :output_size_bytes, :integer do
      default 0
      public? true
    end

    attribute :error, :map, public?: true

    attribute :cost_usd, :decimal do
      public? true
      description "Cost in USD (for Claude Code)"
    end

    attribute :duration_ms, :integer, public?: true

    attribute :sprites_session_id, :string do
      public? true
      description "Session ID from Sprites API"
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    create_timestamp :started_at
    attribute :completed_at, :utc_datetime_usec, public?: true
  end

  relationships do
    belongs_to :session, AgentJido.Forge.Resources.Session do
      allow_nil? false
    end
  end
end
