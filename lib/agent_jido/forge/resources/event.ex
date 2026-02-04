defmodule AgentJido.Forge.Resources.Event do
  @moduledoc false
  use Ash.Resource,
    otp_app: :agent_jido,
    domain: AgentJido.Forge.Domain,
    data_layer: AshPostgres.DataLayer

  require Ash.Query

  postgres do
    table "forge_events"
    repo AgentJido.Repo

    custom_indexes do
      index [:session_id, :timestamp]
      index [:event_type]
    end
  end

  actions do
    defaults [:read]

    create :log do
      accept [:session_id, :event_type, :data, :exec_session_sequence]
    end

    read :for_session do
      argument :session_id, :uuid, allow_nil?: false
      argument :after, :utc_datetime_usec
      argument :event_types, {:array, :string}

      filter expr(session_id == ^arg(:session_id))

      prepare fn query, _context ->
        query
        |> then(fn q ->
          if after_ts = Ash.Query.get_argument(q, :after) do
            Ash.Query.filter(q, timestamp > ^after_ts)
          else
            q
          end
        end)
        |> then(fn q ->
          if types = Ash.Query.get_argument(q, :event_types) do
            Ash.Query.filter(q, event_type in ^types)
          else
            q
          end
        end)
        |> Ash.Query.sort(timestamp: :asc)
      end
    end
  end

  attributes do
    uuid_v7_primary_key :id

    attribute :event_type, :string do
      allow_nil? false
      public? true
      description "Event type (e.g., 'session.started', 'exec_session.output', 'error')"
    end

    attribute :data, :map do
      default %{}
      public? true
    end

    attribute :exec_session_sequence, :integer do
      public? true
      description "Which exec session this event belongs to (if applicable)"
    end

    create_timestamp :timestamp
  end

  relationships do
    belongs_to :session, AgentJido.Forge.Resources.Session do
      allow_nil? false
    end
  end
end
