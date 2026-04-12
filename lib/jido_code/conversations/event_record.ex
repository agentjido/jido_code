defmodule JidoCode.Conversations.EventRecord do
  # covers: architecture.conversation_orchestration.event_log_is_append_only_and_sequenced
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Conversations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "conversation_events"
    repo JidoCode.Repo
  end

  code_interface do
    define :append, action: :append
    define :read
    define :after_sequence, action: :after_sequence
  end

  actions do
    defaults [:destroy]

    create :append do
      primary? true

      accept [
        :id,
        :conversation_id,
        :sequence,
        :name,
        :actor,
        :message_id,
        :turn_id,
        :child_work_id,
        :tool_call_id,
        :correlation,
        :payload,
        :occurred_at
      ]

      upsert? true
      upsert_identity :unique_conversation_sequence

      upsert_fields [
        :name,
        :actor,
        :message_id,
        :turn_id,
        :child_work_id,
        :tool_call_id,
        :correlation,
        :payload,
        :occurred_at
      ]

      change &normalize_attributes/2
    end

    read :read do
      primary? true
    end

    read :after_sequence do
      argument :conversation_id, :uuid, allow_nil?: false
      argument :after_sequence, :integer, allow_nil?: false, default: 0

      filter expr(conversation_id == ^arg(:conversation_id) and sequence > ^arg(:after_sequence))
      prepare build(sort: [sequence: :asc])
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

    attribute :sequence, :integer do
      allow_nil? false
      constraints min: 1
      public? true
    end

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :message_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :turn_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :child_work_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :tool_call_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :correlation, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :payload, :map do
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
    belongs_to :conversation, JidoCode.Conversations.Conversation do
      allow_nil? false
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_conversation_sequence, [:conversation_id, :sequence]
  end

  defp normalize_attributes(changeset, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :actor,
      normalize_map(Ash.Changeset.get_attribute(changeset, :actor))
    )
    |> Ash.Changeset.force_change_attribute(
      :correlation,
      normalize_map(Ash.Changeset.get_attribute(changeset, :correlation))
    )
    |> Ash.Changeset.force_change_attribute(
      :payload,
      normalize_map(Ash.Changeset.get_attribute(changeset, :payload))
    )
    |> Ash.Changeset.force_change_attribute(
      :occurred_at,
      normalize_datetime(Ash.Changeset.get_attribute(changeset, :occurred_at))
    )
  end

  defp normalize_map(value) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, nested_value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(nested_value))
    end)
  end

  defp normalize_map(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
