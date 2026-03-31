defmodule JidoCode.Governance.ChangeRequest do
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @statuses [:open, :approved, :rejected, :deferred]

  postgres do
    table "change_requests"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_for_run, action: :upsert_for_run
    define :get_by_run_id, action: :read, get_by: [:run_id]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :run_id,
        :managed_repo_id,
        :work_item_id,
        :status,
        :summary,
        :review_context,
        :request_metadata,
        :evidence_ids,
        :requested_at,
        :resolved_at
      ]

      change &normalize_request_defaults/2
    end

    create :upsert_for_run do
      accept [
        :run_id,
        :managed_repo_id,
        :work_item_id,
        :status,
        :summary,
        :review_context,
        :request_metadata,
        :evidence_ids,
        :requested_at,
        :resolved_at
      ]

      upsert? true
      upsert_identity :unique_run

      upsert_fields [
        :managed_repo_id,
        :work_item_id,
        :status,
        :summary,
        :review_context,
        :request_metadata,
        :evidence_ids,
        :requested_at,
        :resolved_at
      ]

      change &normalize_request_defaults/2
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
                      :managed_repo_orchestrator,
                      :run_worker
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system, :managed_repo_orchestrator]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :run_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :managed_repo_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :work_item_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :open
      constraints one_of: @statuses
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :review_context, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :request_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :evidence_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
    end

    attribute :requested_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    attribute :resolved_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_run, [:run_id]
  end

  defp normalize_request_defaults(changeset, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :review_context,
      changeset |> Ash.Changeset.get_attribute(:review_context) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :request_metadata,
      changeset |> Ash.Changeset.get_attribute(:request_metadata) |> normalize_map()
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
end
