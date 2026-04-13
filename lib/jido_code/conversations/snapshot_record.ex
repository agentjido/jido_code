defmodule JidoCode.Conversations.SnapshotRecord do
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.steering_preserves_short_term_context
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Conversations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @statuses [:active, :paused, :completed, :cancelled]

  postgres do
    table "conversation_snapshots"
    repo JidoCode.Repo
  end

  code_interface do
    define :upsert_for_conversation, action: :upsert_for_conversation
    define :read
    define :get_by_conversation_id, action: :read, get_by: [:conversation_id]
  end

  actions do
    defaults [:destroy]

    create :upsert_for_conversation do
      primary? true

      accept [
        :conversation_id,
        :managed_repo_id,
        :work_item_id,
        :status,
        :admission_paused,
        :child_execution_paused,
        :active_turn_id,
        :active_child_work_id,
        :queued_turn_ids,
        :turns,
        :child_works,
        :control_history,
        :last_event_sequence,
        :event_count,
        :events,
        :shared_context,
        :captured_at
      ]

      upsert? true
      upsert_identity :unique_conversation

      upsert_fields [
        :managed_repo_id,
        :work_item_id,
        :status,
        :admission_paused,
        :child_execution_paused,
        :active_turn_id,
        :active_child_work_id,
        :queued_turn_ids,
        :turns,
        :child_works,
        :control_history,
        :last_event_sequence,
        :event_count,
        :events,
        :shared_context,
        :captured_at
      ]

      change &normalize_attributes/2
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

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: @statuses
      public? true
    end

    attribute :admission_paused, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :child_execution_paused, :boolean do
      allow_nil? false
      default false
      public? true
    end

    attribute :active_turn_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :active_child_work_id, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :queued_turn_ids, {:array, :string} do
      allow_nil? false
      default []
      public? true
    end

    attribute :turns, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :child_works, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :control_history, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :last_event_sequence, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      public? true
    end

    attribute :event_count, :integer do
      allow_nil? false
      default 0
      constraints min: 0
      public? true
    end

    attribute :events, {:array, :map} do
      allow_nil? false
      default []
      public? true
    end

    attribute :shared_context, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :captured_at, :utc_datetime_usec do
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

    belongs_to :managed_repo, JidoCode.Control.ManagedRepo do
      allow_nil? false
      public? true
      attribute_type :uuid
    end

    belongs_to :work_item, JidoCode.Operations.WorkItem do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_conversation, [:conversation_id]
  end

  defp normalize_attributes(changeset, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :queued_turn_ids,
      normalize_string_list(Ash.Changeset.get_attribute(changeset, :queued_turn_ids))
    )
    |> Ash.Changeset.force_change_attribute(
      :turns,
      normalize_map_list(Ash.Changeset.get_attribute(changeset, :turns))
    )
    |> Ash.Changeset.force_change_attribute(
      :child_works,
      normalize_map_list(Ash.Changeset.get_attribute(changeset, :child_works))
    )
    |> Ash.Changeset.force_change_attribute(
      :control_history,
      normalize_map_list(Ash.Changeset.get_attribute(changeset, :control_history))
    )
    |> Ash.Changeset.force_change_attribute(
      :events,
      normalize_map_list(Ash.Changeset.get_attribute(changeset, :events))
    )
    |> Ash.Changeset.force_change_attribute(
      :shared_context,
      normalize_map(Ash.Changeset.get_attribute(changeset, :shared_context))
    )
    |> Ash.Changeset.force_change_attribute(
      :captured_at,
      normalize_datetime(Ash.Changeset.get_attribute(changeset, :captured_at))
    )
  end

  defp normalize_map_list(value) when is_list(value) do
    value
    |> Enum.filter(&is_map/1)
    |> Enum.map(&normalize_map/1)
  end

  defp normalize_map_list(_value), do: []

  defp normalize_string_list(value) when is_list(value) do
    value
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_string_list(_value), do: []

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

  defp normalize_nested_value(%DateTime{} = value),
    do: value |> DateTime.truncate(:microsecond) |> DateTime.to_iso8601()

  defp normalize_nested_value(%NaiveDateTime{} = value),
    do: value |> NaiveDateTime.truncate(:microsecond) |> NaiveDateTime.to_iso8601()

  defp normalize_nested_value(%Date{} = value), do: Date.to_iso8601(value)
  defp normalize_nested_value(%Time{} = value), do: Time.to_iso8601(value)
  defp normalize_nested_value(value) when is_map(value), do: normalize_map(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: value |> Atom.to_string() |> normalize_optional_string()
  defp normalize_optional_string(_value), do: nil

  defp normalize_datetime(%DateTime{} = datetime), do: DateTime.truncate(datetime, :microsecond)
  defp normalize_datetime(_datetime), do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
