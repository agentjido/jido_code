defmodule JidoCode.Control.RepoBridge do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  @moduledoc """
  Canonical managed-repository provisioning and scope resolution for product code.

  The module name remains stable for existing call sites, but greenfield setup and
  runtime entrypoints now resolve repository scope through `SourceRepo` and
  `ManagedRepo` directly instead of repairing that scope from older `Project`
  records on demand.
  """

  alias JidoCode.Control.{ManagedRepo, ManagedRepoStore, SourceRepo, SourceRepoStore}

  @execution_setting_keys ["execution", "workflow", "llm", "llm_selection"]
  @type scope :: %{
          route_id: String.t(),
          repo_id: String.t() | nil,
          project_id: String.t() | nil,
          managed_repo_id: String.t() | nil,
          source_repo_id: String.t() | nil,
          project: nil,
          managed_repo: ManagedRepo.t() | nil,
          source_repo: SourceRepo.t() | nil
        }

  @spec upsert_managed_repo(map()) ::
          {:ok, %{managed_repo: ManagedRepo.t(), source_repo: SourceRepo.t()}} | {:error, term()}
  def upsert_managed_repo(%{} = attrs) do
    with {:ok, source_repo_attrs} <- source_repo_attrs(attrs),
         {:ok, source_repo} <- SourceRepoStore.upsert(source_repo_attrs),
         {:ok, managed_repo} <-
           ManagedRepoStore.upsert(managed_repo_attrs(attrs, source_repo)) do
      {:ok, %{managed_repo: managed_repo, source_repo: source_repo}}
    end
  end

  def upsert_managed_repo(_attrs), do: {:error, :invalid_repo_attrs}

  @spec sync_project(struct() | map()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def sync_project(%{} = project) do
    with {:ok, %{managed_repo: managed_repo}} <- upsert_managed_repo(project) do
      {:ok, managed_repo}
    end
  end

  def sync_project(_project), do: {:error, :invalid_project}

  @spec managed_repo_for_project(term()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def managed_repo_for_project(identifier) when is_binary(identifier) do
    with {:ok, scope} <- repo_scope(identifier),
         %ManagedRepo{} = managed_repo <- Map.get(scope, :managed_repo) do
      {:ok, managed_repo}
    else
      nil -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def managed_repo_for_project(_identifier), do: {:error, :invalid_project_id}

  @spec repo_scope(term()) :: {:ok, scope()} | {:error, term()}
  def repo_scope(identifier) do
    with {:ok, normalized_identifier} <- normalize_identifier(identifier),
         {:ok, scope} <- fetch_scope(normalized_identifier) do
      {:ok, scope}
    end
  end

  @spec list_repo_scopes() :: {:ok, [scope()]} | {:error, term()}
  def list_repo_scopes do
    with {:ok, managed_repos} <- ManagedRepoStore.list() do
      scopes =
        managed_repos
        |> Enum.map(fn managed_repo ->
          managed_repo
          |> map_get(:id, "id")
          |> repo_scope()
          |> case do
            {:ok, scope} -> scope
            {:error, _reason} -> fallback_scope(managed_repo)
          end
        end)

      {:ok, scopes}
    end
  end

  defp normalize_identifier(identifier) do
    case normalize_optional_string(identifier) do
      nil -> {:error, :invalid_identifier}
      normalized_identifier -> {:ok, normalized_identifier}
    end
  end

  defp fetch_scope(identifier) do
    managed_repo =
      fetch_managed_repo_by_id(identifier) ||
        fetch_managed_repo_by_source_repo_identifier(identifier) ||
        fetch_managed_repo_by_legacy_project_id(identifier)

    source_repo =
      case managed_repo do
        %ManagedRepo{} = repo ->
          fetch_source_repo_by_id(
            repo
            |> map_get(:source_repo_id, "source_repo_id")
            |> normalize_optional_string()
          )

        nil ->
          fetch_source_repo_by_identifier(identifier)
      end

    managed_repo =
      case managed_repo do
        %ManagedRepo{} = repo ->
          repo

        nil ->
          source_repo
          |> map_get(:id, "id")
          |> normalize_optional_string()
          |> fetch_managed_repo_by_source_repo_id()
      end

    case {managed_repo, source_repo} do
      {nil, nil} ->
        {:error, :repo_scope_not_found}

      _other ->
        managed_repo_id =
          managed_repo
          |> map_get(:id, "id")
          |> normalize_optional_string()

        source_repo_id =
          source_repo
          |> map_get(:id, "id")
          |> normalize_optional_string() ||
            managed_repo
            |> map_get(:source_repo_id, "source_repo_id")
            |> normalize_optional_string()

        legacy_project_id =
          managed_repo
          |> map_get(:legacy_project_id, "legacy_project_id")
          |> normalize_optional_string()

        route_id = managed_repo_id || source_repo_id || identifier

        {:ok,
         %{
           route_id: route_id,
           repo_id: route_id,
           project_id: legacy_project_id,
           managed_repo_id: managed_repo_id,
           source_repo_id: source_repo_id,
           project: nil,
           managed_repo: managed_repo,
           source_repo: source_repo
         }}
    end
  end

  defp fetch_managed_repo_by_id(managed_repo_id) when is_binary(managed_repo_id) do
    case ManagedRepoStore.get_by_id(managed_repo_id) do
      {:ok, %ManagedRepo{} = managed_repo} -> managed_repo
      _other -> nil
    end
  end

  defp fetch_managed_repo_by_id(_managed_repo_id), do: nil

  defp fetch_managed_repo_by_source_repo_id(source_repo_id) when is_binary(source_repo_id) do
    case ManagedRepoStore.get_by_source_repo_id(source_repo_id) do
      {:ok, %ManagedRepo{} = managed_repo} -> managed_repo
      _other -> nil
    end
  end

  defp fetch_managed_repo_by_source_repo_id(_source_repo_id), do: nil

  defp fetch_managed_repo_by_source_repo_identifier(identifier) when is_binary(identifier) do
    identifier
    |> fetch_source_repo_by_identifier()
    |> map_get(:id, "id")
    |> normalize_optional_string()
    |> fetch_managed_repo_by_source_repo_id()
  end

  defp fetch_managed_repo_by_source_repo_identifier(_identifier), do: nil

  defp fetch_managed_repo_by_legacy_project_id(project_id) when is_binary(project_id) do
    case ManagedRepoStore.get_by_legacy_project_id(project_id) do
      {:ok, %ManagedRepo{} = managed_repo} -> managed_repo
      _other -> nil
    end
  end

  defp fetch_managed_repo_by_legacy_project_id(_project_id), do: nil

  defp fetch_source_repo_by_identifier(identifier) when is_binary(identifier) do
    fetch_source_repo_by_id(identifier) || fetch_source_repo_by_source_key(identifier) ||
      fetch_source_repo_by_full_name(identifier)
  end

  defp fetch_source_repo_by_identifier(_identifier), do: nil

  defp fetch_source_repo_by_id(source_repo_id) when is_binary(source_repo_id) do
    case SourceRepoStore.get_by_id(source_repo_id) do
      {:ok, %SourceRepo{} = source_repo} -> source_repo
      _other -> nil
    end
  end

  defp fetch_source_repo_by_id(_source_repo_id), do: nil

  defp fetch_source_repo_by_source_key(source_key) when is_binary(source_key) do
    case String.split(source_key, ":", parts: 2) do
      [provider, full_name] when provider in ["github", "gitlab", "bitbucket"] and full_name != "" ->
        case SourceRepoStore.get_by_provider_and_full_name(provider, full_name) do
          {:ok, %SourceRepo{} = source_repo} -> source_repo
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp fetch_source_repo_by_source_key(_source_key), do: nil

  defp fetch_source_repo_by_full_name(full_name) when is_binary(full_name) do
    case SourceRepoStore.get_by_provider_and_full_name(:github, full_name) do
      {:ok, %SourceRepo{} = source_repo} -> source_repo
      _other -> nil
    end
  end

  defp fetch_source_repo_by_full_name(_full_name), do: nil

  defp source_repo_attrs(attrs) do
    repo_full_name =
      attrs
      |> map_get(:full_name, "full_name")
      |> normalize_optional_string()
      |> fallback_optional_string(
        attrs
        |> map_get(:github_full_name, "github_full_name")
        |> normalize_optional_string()
      )
      |> fallback_optional_string(
        attrs
        |> map_get(:source_identifier, "source_identifier")
        |> normalize_optional_string()
      )

    default_branch =
      attrs
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string()
      |> Kernel.||("main")

    provider =
      attrs
      |> map_get(:provider, "provider", :github)
      |> normalize_provider(:github)

    source_metadata =
      attrs
      |> map_get(:source_metadata, "source_metadata", %{})
      |> normalize_map()

    case normalize_repo_identity(repo_full_name) do
      {:ok, owner, name, full_name} ->
        {:ok,
         %{
           provider: provider,
           owner: owner,
           name: name,
           full_name: full_name,
           default_branch: default_branch,
           source_metadata: source_metadata
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp managed_repo_attrs(attrs, source_repo) do
    settings =
      attrs
      |> map_get(:settings, "settings", %{})
      |> normalize_map()

    explicit_workspace_settings =
      attrs
      |> map_get(:workspace_settings, "workspace_settings")
      |> normalize_optional_map()

    explicit_execution_settings =
      attrs
      |> map_get(:execution_settings, "execution_settings")
      |> normalize_optional_map()

    explicit_integration_settings =
      attrs
      |> map_get(:integration_settings, "integration_settings")
      |> normalize_optional_map()

    execution_settings =
      explicit_execution_settings ||
        settings
        |> Map.take(@execution_setting_keys)
        |> normalize_map()

    integration_settings =
      explicit_integration_settings ||
        settings
        |> Map.drop(["workspace" | Map.keys(execution_settings)])
        |> normalize_map()

    workspace_settings =
      explicit_workspace_settings ||
        settings
        |> Map.get("workspace", %{})
        |> normalize_map()

    legacy_project_id =
      attrs
      |> map_get(:legacy_project_id, "legacy_project_id")
      |> normalize_optional_string()
      |> fallback_optional_string(
        attrs
        |> map_get(:id, "id")
        |> normalize_optional_string()
      )

    display_name =
      attrs
      |> map_get(:display_name, "display_name")
      |> normalize_optional_string()
      |> fallback_optional_string(
        attrs
        |> map_get(:name, "name")
        |> normalize_optional_string()
      )
      |> fallback_optional_string(
        source_repo
        |> map_get(:name, "name")
        |> normalize_optional_string()
      )
      |> Kernel.||("unknown-repo")

    %{
      display_name: display_name,
      source_key:
        SourceRepoStore.source_key(
          source_repo |> map_get(:provider, "provider", :github),
          source_repo |> map_get(:full_name, "full_name")
        ),
      source_repo_id:
        source_repo
        |> map_get(:id, "id")
        |> normalize_optional_string(),
      workspace_settings: workspace_settings,
      execution_settings: execution_settings,
      integration_settings: integration_settings
    }
    |> maybe_put(:legacy_project_id, legacy_project_id)
  end

  defp normalize_repo_identity(nil), do: {:error, :missing_github_full_name}

  defp normalize_repo_identity(github_full_name) when is_binary(github_full_name) do
    normalized_full_name = String.trim(github_full_name)

    case String.split(normalized_full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name, normalized_full_name}

      _other ->
        {:error, :invalid_github_full_name}
    end
  end

  defp normalize_repo_identity(_github_full_name), do: {:error, :invalid_github_full_name}

  defp normalize_provider(provider, _default) when provider in [:github, :gitlab, :bitbucket],
    do: provider

  defp normalize_provider(provider, default) when is_binary(provider) do
    case String.trim(provider) do
      "github" -> :github
      "gitlab" -> :gitlab
      "bitbucket" -> :bitbucket
      _other -> default
    end
  end

  defp normalize_provider(_provider, default), do: default

  defp fallback_optional_string(nil, fallback), do: fallback
  defp fallback_optional_string(value, _fallback), do: value

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(%{} = map, atom_key, string_key, default) do
    case Map.fetch(map, atom_key) do
      {:ok, value} ->
        value

      :error ->
        Map.get(map, string_key, default)
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default

  defp normalize_optional_map(value) when is_map(value), do: normalize_map(value)
  defp normalize_optional_map(_value), do: nil

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
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp fallback_scope(%ManagedRepo{} = managed_repo) do
    managed_repo_id = managed_repo |> map_get(:id, "id") |> normalize_optional_string()
    source_repo_id = managed_repo |> map_get(:source_repo_id, "source_repo_id") |> normalize_optional_string()
    legacy_project_id = managed_repo |> map_get(:legacy_project_id, "legacy_project_id") |> normalize_optional_string()

    %{
      route_id: managed_repo_id || source_repo_id,
      repo_id: managed_repo_id || source_repo_id,
      project_id: legacy_project_id,
      managed_repo_id: managed_repo_id,
      source_repo_id: source_repo_id,
      project: nil,
      managed_repo: managed_repo,
      source_repo: nil
    }
  end
end
