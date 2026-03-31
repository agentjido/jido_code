defmodule JidoCode.Governance.Decision do
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @decisions [:approve, :reject, :defer]

  postgres do
    table "decisions"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_for_run, action: :upsert_for_run
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :decision_key,
        :run_id,
        :change_request_id,
        :managed_repo_id,
        :work_item_id,
        :decision,
        :actor,
        :rationale,
        :evidence_ids,
        :decision_metadata,
        :decided_at
      ]

      change &normalize_decision_defaults/2
    end

    create :upsert_for_run do
      accept [
        :decision_key,
        :run_id,
        :change_request_id,
        :managed_repo_id,
        :work_item_id,
        :decision,
        :actor,
        :rationale,
        :evidence_ids,
        :decision_metadata,
        :decided_at
      ]

      upsert? true
      upsert_identity :unique_decision_key

      upsert_fields [
        :change_request_id,
        :managed_repo_id,
        :work_item_id,
        :decision,
        :actor,
        :rationale,
        :evidence_ids,
        :decision_metadata,
        :decided_at
      ]

      change &normalize_decision_defaults/2
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

    attribute :decision_key, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 512, trim?: true
      public? true
    end

    attribute :run_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :change_request_id, :uuid do
      allow_nil? true
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

    attribute :decision, :atom do
      allow_nil? false
      constraints one_of: @decisions
      public? true
    end

    attribute :actor, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :rationale, :string do
      allow_nil? true
      constraints max_length: 2048, trim?: true
      public? true
    end

    attribute :evidence_ids, {:array, :uuid} do
      allow_nil? false
      default []
      public? true
    end

    attribute :decision_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :decided_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_decision_key, [:decision_key]
  end

  defp normalize_decision_defaults(changeset, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :actor,
      changeset |> Ash.Changeset.get_attribute(:actor) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :decision_metadata,
      changeset |> Ash.Changeset.get_attribute(:decision_metadata) |> normalize_map()
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
