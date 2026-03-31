defmodule JidoCode.Governance.Evidence do
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Governance,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  postgres do
    table "evidence_records"
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
        :run_id,
        :managed_repo_id,
        :work_item_id,
        :key,
        :evidence_type,
        :summary,
        :evidence_details,
        :source,
        :recorded_at
      ]

      change &normalize_evidence_defaults/2
    end

    create :upsert_for_run do
      accept [
        :run_id,
        :managed_repo_id,
        :work_item_id,
        :key,
        :evidence_type,
        :summary,
        :evidence_details,
        :source,
        :recorded_at
      ]

      upsert? true
      upsert_identity :unique_run_key
      upsert_fields [:managed_repo_id, :work_item_id, :summary, :evidence_details, :source, :recorded_at]

      change &normalize_evidence_defaults/2
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

    attribute :key, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :evidence_type, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :summary, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :evidence_details, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      default "workflow_run"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :recorded_at, :utc_datetime_usec do
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_run_key, [:run_id, :key]
  end

  defp normalize_evidence_defaults(changeset, _context) do
    changeset
    |> Ash.Changeset.force_change_attribute(
      :evidence_details,
      changeset |> Ash.Changeset.get_attribute(:evidence_details) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :source,
      changeset |> Ash.Changeset.get_attribute(:source) |> normalize_string("workflow_run")
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

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
