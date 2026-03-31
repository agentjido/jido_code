defmodule JidoCode.Control.RepoBridge do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  @moduledoc """
  Keeps the transitional `Project` resource mirrored into control-plane repo resources.
  """

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Governance.{PolicyBridge, PostureBridge}
  alias JidoCode.Operations.RepoNativeState
  alias JidoCode.Projects.Project

  @execution_setting_keys ["execution", "workflow"]
  @read_actor Actor.operator_actor()

  @spec sync_project(struct() | map()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def sync_project(%{} = project) do
    with {:ok, source_repo_attrs} <- source_repo_attrs(project),
         {:ok, source_repo} <- SourceRepo.upsert_identity(source_repo_attrs, actor: Actor.factory_system_actor()),
         {:ok, managed_repo} <-
           ManagedRepo.upsert_projection(
             managed_repo_attrs(project, source_repo),
             actor: Actor.factory_system_actor()
           ),
         {:ok, _policy_set} <- PolicyBridge.sync_managed_repo(managed_repo),
         {:ok, _repo_native_state} <- RepoNativeState.sync_managed_repo(managed_repo),
         {:ok, _repo_posture} <- PostureBridge.sync_managed_repo(managed_repo) do
      {:ok, managed_repo}
    end
  end

  def sync_project(_project), do: {:error, :invalid_project}

  @spec managed_repo_for_project(term()) :: {:ok, ManagedRepo.t()} | {:error, term()}
  def managed_repo_for_project(project_id) when is_binary(project_id) do
    ManagedRepo.get_by_legacy_project_id(project_id, actor: Actor.factory_system_actor())
  end

  def managed_repo_for_project(_project_id), do: {:error, :invalid_project_id}

  @spec repo_scope(term()) ::
          {:ok,
           %{
             route_id: String.t(),
             project_id: String.t() | nil,
             managed_repo_id: String.t() | nil,
             source_repo_id: String.t() | nil,
             project: Project.t() | nil,
             managed_repo: ManagedRepo.t() | nil,
             source_repo: SourceRepo.t() | nil
           }}
          | {:error, term()}
  def repo_scope(identifier) do
    with {:ok, normalized_identifier} <- normalize_identifier(identifier),
         {:ok, scope} <- fetch_scope(normalized_identifier) do
      {:ok, scope}
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
      case fetch_managed_repo_by_id(identifier) do
        {:ok, %ManagedRepo{} = managed_repo} -> managed_repo
        _other -> nil
      end

    project =
      case managed_repo do
        %ManagedRepo{} = repo ->
          repo
          |> map_get(:legacy_project_id, "legacy_project_id")
          |> fetch_project_by_id()
          |> case do
            {:ok, %Project{} = project} -> project
            _other -> nil
          end

        nil ->
          case fetch_project_by_id(identifier) do
            {:ok, %Project{} = project} -> project
            _other -> nil
          end
      end

    managed_repo =
      case managed_repo do
        %ManagedRepo{} = repo ->
          repo

        nil ->
          project
          |> map_get(:id, "id")
          |> normalize_optional_string()
          |> case do
            nil -> nil
            project_id -> managed_repo_for_project(project_id)
          end
          |> case do
            {:ok, %ManagedRepo{} = repo} -> repo
            _other -> nil
          end
      end

    source_repo =
      managed_repo
      |> map_get(:source_repo_id, "source_repo_id")
      |> fetch_source_repo_by_id()
      |> case do
        {:ok, %SourceRepo{} = source_repo} -> source_repo
        _other -> nil
      end

    project_id =
      project
      |> map_get(:id, "id")
      |> normalize_optional_string() ||
        managed_repo
        |> map_get(:legacy_project_id, "legacy_project_id")
        |> normalize_optional_string()

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

    cond do
      is_nil(project) and is_nil(managed_repo) ->
        {:error, :repo_scope_not_found}

      true ->
        {:ok,
         %{
           route_id: identifier,
           project_id: project_id,
           managed_repo_id: managed_repo_id,
           source_repo_id: source_repo_id,
           project: project,
           managed_repo: managed_repo,
           source_repo: source_repo
         }}
    end
  end

  defp fetch_project_by_id(project_id) when is_binary(project_id) do
    case Project.read(query: [filter: [id: project_id], limit: 1], actor: @read_actor) do
      {:ok, [%Project{} = project | _rest]} -> {:ok, project}
      {:ok, []} -> {:error, :project_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_project_by_id(_project_id), do: {:error, :project_not_found}

  defp fetch_managed_repo_by_id(managed_repo_id) when is_binary(managed_repo_id) do
    case ManagedRepo.read(query: [filter: [id: managed_repo_id], limit: 1], actor: @read_actor) do
      {:ok, [%ManagedRepo{} = managed_repo | _rest]} -> {:ok, managed_repo}
      {:ok, []} -> {:error, :managed_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_managed_repo_by_id(_managed_repo_id), do: {:error, :managed_repo_not_found}

  defp fetch_source_repo_by_id(source_repo_id) when is_binary(source_repo_id) do
    case SourceRepo.read(query: [filter: [id: source_repo_id], limit: 1], actor: @read_actor) do
      {:ok, [%SourceRepo{} = source_repo | _rest]} -> {:ok, source_repo}
      {:ok, []} -> {:error, :source_repo_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_source_repo_by_id(_source_repo_id), do: {:error, :source_repo_not_found}

  defp source_repo_attrs(project) do
    github_full_name =
      project
      |> map_get(:github_full_name, "github_full_name")
      |> normalize_optional_string()

    default_branch =
      project
      |> map_get(:default_branch, "default_branch")
      |> normalize_optional_string() || "main"

    case normalize_repo_identity(github_full_name) do
      {:ok, owner, name, full_name} ->
        {:ok,
         %{
           provider: :github,
           owner: owner,
           name: name,
           full_name: full_name,
           default_branch: default_branch,
           source_metadata: %{}
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp managed_repo_attrs(project, source_repo) do
    settings =
      project
      |> map_get(:settings, "settings", %{})
      |> normalize_map()

    execution_settings =
      settings
      |> Map.take(@execution_setting_keys)
      |> normalize_map()

    integration_settings =
      settings
      |> Map.drop(["workspace" | Map.keys(execution_settings)])
      |> normalize_map()

    %{
      display_name:
        project
        |> map_get(:name, "name")
        |> normalize_optional_string() ||
          source_repo |> map_get(:name, "name") |> normalize_optional_string() ||
          "unknown-repo",
      legacy_project_id: project |> map_get(:id, "id"),
      source_repo_id: source_repo |> map_get(:id, "id"),
      workspace_settings: settings |> Map.get("workspace", %{}) |> normalize_map(),
      execution_settings: execution_settings,
      integration_settings: integration_settings
    }
  end

  defp normalize_repo_identity(nil), do: {:error, :missing_github_full_name}

  defp normalize_repo_identity(github_full_name) when is_binary(github_full_name) do
    normalized_full_name = String.trim(github_full_name)

    case String.split(normalized_full_name, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" ->
        {:ok, owner, name, normalized_full_name}

      [name] when name != "" ->
        {:ok, "unknown", name, normalized_full_name}

      _other ->
        {:error, :invalid_github_full_name}
    end
  end

  defp normalize_repo_identity(_github_full_name), do: {:error, :invalid_github_full_name}

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

  defp normalize_map(value) when is_map(value) do
    value
    |> Enum.reduce(%{}, fn {key, nested_value}, acc ->
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
end
