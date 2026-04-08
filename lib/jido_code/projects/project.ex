defmodule JidoCode.Projects.Project do
  # covers: setup.onboarding.repo_source_per_project
  # covers: architecture.policy_layers.ash_policy_is_first_class_data_plane_membrane
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  use Ash.Resource,
    otp_app: :jido_code,
    domain: JidoCode.Projects,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias JidoCode.Control.Checks.ActorClassIn
  alias JidoCode.Control.RepoBridge
  @source_kinds [:github, :local]

  postgres do
    table "projects"
    repo JidoCode.Repo
  end

  code_interface do
    define :create
    define :read
    define :get_by_github_full_name, action: :read, get_by: [:github_full_name]
    define :get_by_source_identity, action: :read, get_by: [:source_kind, :source_identifier]
    define :update
  end

  actions do
    defaults [:destroy]

    create :create do
      primary? true
      accept [:name, :source_kind, :source_identifier, :github_full_name, :local_path, :default_branch, :settings]

      change &normalize_source_fields/2

      change after_action(fn _changeset, project, _context ->
               case project.source_kind do
                 :local ->
                   {:ok, project}

                 _other ->
                   case RepoBridge.sync_project(project) do
                     {:ok, _managed_repo} -> {:ok, project}
                     {:error, reason} -> {:error, reason}
                   end
               end
             end)
    end

    read :read do
      primary? true
    end

    update :update do
      primary? true
      require_atomic? false
      accept [:name, :source_kind, :source_identifier, :github_full_name, :local_path, :default_branch, :settings]

      change &normalize_source_fields/2

      change after_action(fn _changeset, project, _context ->
               case project.source_kind do
                 :local ->
                   {:ok, project}

                 _other ->
                   case RepoBridge.sync_project(project) do
                     {:ok, _managed_repo} -> {:ok, project}
                     {:error, reason} -> {:error, reason}
                   end
               end
             end)
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
                      :run_worker,
                      :external_ingress
                    ]}
    end

    policy action_type(:create) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system
                    ]}
    end

    policy action_type(:update) do
      authorize_if {ActorClassIn,
                    classes: [
                      :admin,
                      :operator,
                      :factory_system
                    ]}
    end

    policy action_type(:destroy) do
      authorize_if {ActorClassIn, classes: [:admin, :factory_system]}
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :source_kind, :atom do
      allow_nil? false
      default :github
      constraints one_of: @source_kinds
      public? true
    end

    attribute :source_identifier, :string do
      allow_nil? true
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :github_full_name, :string do
      allow_nil? true
      constraints min_length: 3, max_length: 255, trim?: true
      public? true
    end

    attribute :local_path, :string do
      allow_nil? true
      constraints min_length: 1, max_length: 2048, trim?: true
      public? true
    end

    attribute :default_branch, :string do
      allow_nil? false
      default "main"
      constraints min_length: 1, max_length: 255, trim?: true
      public? true
    end

    attribute :settings, :map do
      allow_nil? false
      default %{}
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_source_identity, [:source_kind, :source_identifier]
    identity :unique_github_full_name, [:github_full_name]
  end

  defp normalize_source_fields(changeset, _context) do
    source_kind =
      changeset
      |> Ash.Changeset.get_attribute(:source_kind)
      |> normalize_source_kind(:github)

    source_identifier =
      changeset
      |> Ash.Changeset.get_attribute(:source_identifier)
      |> normalize_optional_string()

    github_full_name =
      changeset
      |> Ash.Changeset.get_attribute(:github_full_name)
      |> normalize_optional_string()

    local_path =
      changeset
      |> Ash.Changeset.get_attribute(:local_path)
      |> normalize_optional_string()

    changeset =
      maybe_derive_local_name(
        changeset,
        source_kind,
        local_path || source_identifier
      )

    case source_kind do
      :github ->
        identifier = source_identifier || github_full_name

        if is_binary(identifier) do
          changeset
          |> Ash.Changeset.force_change_attribute(:source_kind, :github)
          |> Ash.Changeset.force_change_attribute(:source_identifier, identifier)
          |> Ash.Changeset.force_change_attribute(:github_full_name, identifier)
          |> Ash.Changeset.force_change_attribute(:local_path, nil)
        else
          Ash.Changeset.add_error(
            changeset,
            field: :source_identifier,
            message: "GitHub projects require a repository identifier."
          )
        end

      :local ->
        identifier = source_identifier || local_path
        resolved_local_path = local_path || identifier

        if is_binary(resolved_local_path) do
          changeset
          |> Ash.Changeset.force_change_attribute(:source_kind, :local)
          |> Ash.Changeset.force_change_attribute(:source_identifier, identifier)
          |> Ash.Changeset.force_change_attribute(:local_path, resolved_local_path)
          |> Ash.Changeset.force_change_attribute(:github_full_name, nil)
        else
          Ash.Changeset.add_error(
            changeset,
            field: :local_path,
            message: "Local projects require a repository path."
          )
        end
    end
  end

  defp maybe_derive_local_name(changeset, :local, source_path) when is_binary(source_path) do
    case normalize_optional_string(Ash.Changeset.get_attribute(changeset, :name)) do
      nil ->
        source_path
        |> Path.basename()
        |> normalize_optional_string()
        |> case do
          nil -> changeset
          derived_name -> Ash.Changeset.force_change_attribute(changeset, :name, derived_name)
        end

      _existing_name ->
        changeset
    end
  end

  defp maybe_derive_local_name(changeset, _source_kind, _source_path), do: changeset

  defp normalize_source_kind(source_kind, _default) when source_kind in @source_kinds,
    do: source_kind

  defp normalize_source_kind(source_kind, default) when is_binary(source_kind) do
    case String.trim(source_kind) do
      "github" -> :github
      "local" -> :local
      _other -> default
    end
  end

  defp normalize_source_kind(_source_kind, default), do: default

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil
end
