defmodule JidoCode.Orchestration.ExecutionProfile do
  # covers: architecture.run_governance.execution_profile_governs_environment_defaults
  # covers: architecture.run_governance.execution_profile_preserves_repo_and_workflow_compatibility
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Orchestration,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn

  @default_governed_stages [
    "repo_attach",
    "repo_sync",
    "repo_prep",
    "validation",
    "approval",
    "cleanup"
  ]

  @default_validation_plan ["lint", "tests", "spec_check"]
  @default_repo_prep_plan ["repo_attach", "repo_sync", "repo_prep"]
  @default_checkpoint_strategy "resume_from_runic_state"

  postgres do
    table "execution_profiles"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :upsert_for_managed_repo, action: :upsert_for_managed_repo
    define :get_by_managed_repo_name, action: :read, get_by: [:managed_repo_id, :name]
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true

      accept [
        :managed_repo_id,
        :name,
        :sandbox_profile,
        :repo_prep_plan,
        :validation_plan,
        :governed_stages,
        :checkpoint_strategy,
        :resume_strategy,
        :profile_metadata,
        :source
      ]

      change &normalize_profile_defaults/2
    end

    create :upsert_for_managed_repo do
      accept [
        :managed_repo_id,
        :name,
        :sandbox_profile,
        :repo_prep_plan,
        :validation_plan,
        :governed_stages,
        :checkpoint_strategy,
        :resume_strategy,
        :profile_metadata,
        :source
      ]

      upsert? true
      upsert_identity :unique_managed_repo_name

      upsert_fields [
        :sandbox_profile,
        :repo_prep_plan,
        :validation_plan,
        :governed_stages,
        :checkpoint_strategy,
        :resume_strategy,
        :profile_metadata,
        :source
      ]

      change &normalize_profile_defaults/2
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

    attribute :name, :string do
      allow_nil? false
      default "default"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :sandbox_profile, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :repo_prep_plan, {:array, :string} do
      allow_nil? false
      default @default_repo_prep_plan
      public? true
    end

    attribute :validation_plan, {:array, :string} do
      allow_nil? false
      default @default_validation_plan
      public? true
    end

    attribute :governed_stages, {:array, :string} do
      allow_nil? false
      default @default_governed_stages
      public? true
    end

    attribute :checkpoint_strategy, :string do
      allow_nil? false
      default @default_checkpoint_strategy
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :resume_strategy, :string do
      allow_nil? false
      default @default_checkpoint_strategy
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :profile_metadata, :map do
      allow_nil? false
      default %{}
      public? true
    end

    attribute :source, :string do
      allow_nil? false
      default "managed_repo.execution_settings"
      constraints min_length: 1, max_length: 255, trim?: true
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
  end

  identities do
    identity :unique_managed_repo_name, [:managed_repo_id, :name]
  end

  def default_governed_stages, do: @default_governed_stages
  def default_repo_prep_plan, do: @default_repo_prep_plan
  def default_validation_plan, do: @default_validation_plan
  def default_checkpoint_strategy, do: @default_checkpoint_strategy

  defp normalize_profile_defaults(changeset, _context) do
    repo_prep_plan =
      changeset
      |> Ash.Changeset.get_attribute(:repo_prep_plan)
      |> normalize_string_list(@default_repo_prep_plan)

    validation_plan =
      changeset
      |> Ash.Changeset.get_attribute(:validation_plan)
      |> normalize_string_list(@default_validation_plan)

    governed_stages =
      changeset
      |> Ash.Changeset.get_attribute(:governed_stages)
      |> normalize_string_list(@default_governed_stages)

    checkpoint_strategy =
      changeset
      |> Ash.Changeset.get_attribute(:checkpoint_strategy)
      |> normalize_string(@default_checkpoint_strategy)

    resume_strategy =
      changeset
      |> Ash.Changeset.get_attribute(:resume_strategy)
      |> normalize_string(checkpoint_strategy)

    changeset
    |> Ash.Changeset.force_change_attribute(:repo_prep_plan, repo_prep_plan)
    |> Ash.Changeset.force_change_attribute(:validation_plan, validation_plan)
    |> Ash.Changeset.force_change_attribute(:governed_stages, governed_stages)
    |> Ash.Changeset.force_change_attribute(:checkpoint_strategy, checkpoint_strategy)
    |> Ash.Changeset.force_change_attribute(:resume_strategy, resume_strategy)
    |> Ash.Changeset.force_change_attribute(
      :sandbox_profile,
      changeset |> Ash.Changeset.get_attribute(:sandbox_profile) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :profile_metadata,
      changeset |> Ash.Changeset.get_attribute(:profile_metadata) |> normalize_map()
    )
    |> Ash.Changeset.force_change_attribute(
      :source,
      changeset |> Ash.Changeset.get_attribute(:source) |> normalize_string("managed_repo.execution_settings")
    )
  end

  defp normalize_string_list(value, default) when is_list(value) do
    normalized =
      value
      |> Enum.map(&normalize_optional_string/1)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    if normalized == [], do: default, else: normalized
  end

  defp normalize_string_list(_value, default), do: default

  defp normalize_string(value, default) do
    case normalize_optional_string(value) do
      nil -> default
      normalized -> normalized
    end
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
