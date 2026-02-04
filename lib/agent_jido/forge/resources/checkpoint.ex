defmodule AgentJido.Forge.Resources.Checkpoint do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "forge_checkpoints"
    repo AgentJido.Repo
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :session_id,
        :sprites_checkpoint_id,
        :name,
        :exec_session_sequence,
        :runner_state_snapshot,
        :metadata
      ]
    end

    read :latest_for_session do
      argument :session_id, :uuid, allow_nil?: false

      filter expr(session_id == ^arg(:session_id))

      prepare fn query, _context ->
        query
        |> Ash.Query.sort(created_at: :desc)
        |> Ash.Query.limit(1)
      end
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :sprites_checkpoint_id, :string do
      allow_nil? false
      public? true
      description "Checkpoint ID from Sprites API"
    end

    attribute :name, :string do
      public? true
      description "Human-readable checkpoint name"
    end

    attribute :exec_session_sequence, :integer do
      public? true
      description "After which exec session this checkpoint was created"
    end

    attribute :runner_state_snapshot, :map do
      public? true
      description "Snapshot of runner_state at checkpoint time"
    end

    attribute :metadata, :map do
      default %{}
      public? true
    end

    create_timestamp :created_at
  end

  relationships do
    belongs_to :session, AgentJido.Forge.Resources.Session do
      allow_nil? false
    end
  end
end
