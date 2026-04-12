defmodule JidoCode.Conversations.Conversation do
  # covers: architecture.conversation_orchestration.conversation_is_repo_and_work_scoped
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Conversations,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @statuses [:active, :paused, :completed, :cancelled]
  @scopes [:repo_scoped, :work_item_scoped]
  @attachment_modes [:pre_work, :existing_work_item, :synthesized_work_item]

  postgres do
    table "conversations"
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
        :work_item_id,
        :status,
        :scope,
        :attachment_mode,
        :source,
        :title,
        :objective,
        :initiating_actor,
        :source_metadata,
        :conversation_metadata,
        :started_at,
        :last_activity_at
      ]

      change &normalize_attributes/2
    end

    update :update do
      primary? true
      require_atomic? false

      accept [
        :work_item_id,
        :status,
        :scope,
        :attachment_mode,
        :source,
        :title,
        :objective,
        :initiating_actor,
        :source_metadata,
        :conversation_metadata,
        :last_activity_at
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

    attribute :status, :atom do
      allow_nil? false
      default :active
      constraints one_of: @statuses
      public? true
    end

    attribute :scope, :atom do
      allow_nil? false
      constraints one_of: @scopes
      public? true
    end

    attribute :attachment_mode, :atom do
      allow_nil? false
      constraints one_of: @attachment_modes
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :title, :string do
      allow_nil? true
      constraints max_length: 255, trim?: true
      public? true
    end

    attribute :objective, :string do
      allow_nil? true
      constraints max_length: 4096, trim?: true
      public? true
    end

    attribute :initiating_actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :conversation_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :last_activity_at, :utc_datetime_usec do
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

    belongs_to :work_item, JidoCode.Operations.WorkItem do
      allow_nil? true
      public? true
      attribute_type :uuid
    end
  end

  defp normalize_attributes(changeset, _context) do
    started_at =
      changeset
      |> Ash.Changeset.get_attribute(:started_at)
      |> normalize_datetime()

    last_activity_at =
      changeset
      |> Ash.Changeset.get_attribute(:last_activity_at)
      |> normalize_datetime()

    changeset
    |> Ash.Changeset.force_change_attribute(
      :initiating_actor,
      normalize_map(Ash.Changeset.get_attribute(changeset, :initiating_actor))
    )
    |> Ash.Changeset.force_change_attribute(
      :source_metadata,
      normalize_map(Ash.Changeset.get_attribute(changeset, :source_metadata))
    )
    |> Ash.Changeset.force_change_attribute(
      :conversation_metadata,
      normalize_map(Ash.Changeset.get_attribute(changeset, :conversation_metadata))
    )
    |> Ash.Changeset.force_change_attribute(:started_at, started_at)
    |> Ash.Changeset.force_change_attribute(:last_activity_at, last_activity_at)
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
