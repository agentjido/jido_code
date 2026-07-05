defmodule JidoCode.Projects.Project do
  # covers: projects.catalog.project_source_identity_fields
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Control.{Actor, RepoBridge}

  @allowed_actor_classes [:admin, :operator, :factory_system, :managed_repo_orchestrator]

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ [])

  def create(attrs, opts) when is_map(attrs) do
    with :ok <- authorize(opts),
         {:ok, project} <- build_project(attrs),
         {:ok, _managed_repo} <- maybe_sync_managed_repo(project) do
      {:ok, project}
    end
  end

  def create(_attrs, _opts), do: {:error, :invalid_project_attrs}

  @spec update(t(), map(), keyword()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = project, attrs, opts \\ []) when is_map(attrs) do
    project
    |> Map.from_struct()
    |> Map.merge(attrs)
    |> create(opts)
  end

  @spec get_by_github_full_name(String.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def get_by_github_full_name(full_name, opts \\ [])

  def get_by_github_full_name(full_name, opts) when is_binary(full_name) do
    with :ok <- authorize(opts),
         {:ok, scope} <- RepoBridge.repo_scope(full_name),
         %{} = source_repo <- Map.get(scope, :source_repo) do
      {:ok, project_from_scope(scope, source_repo)}
    else
      nil -> {:error, :project_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def get_by_github_full_name(_full_name, _opts), do: {:error, :project_not_found}

  defp authorize(opts) do
    if Actor.allowed?(Keyword.get(opts, :actor), @allowed_actor_classes) do
      :ok
    else
      {:error, forbidden_error()}
    end
  end

  defp build_project(attrs) do
    source_kind = attrs |> map_get(:source_kind, :github) |> normalize_source_kind()

    case source_kind do
      :local -> build_local_project(attrs)
      :github -> build_github_project(attrs)
      other -> {:error, {:invalid_source_kind, other}}
    end
  end

  defp build_github_project(attrs) do
    with {:ok, full_name} <- github_full_name(attrs) do
      name =
        attrs
        |> map_get(:name)
        |> normalize_optional_string() || full_name |> String.split("/") |> List.last()

      {:ok,
       %__MODULE__{
         id: attrs |> map_get(:id) |> normalize_optional_string() || JidoCode.UUID.generate(),
         name: name,
         source_kind: :github,
         source_identifier: full_name,
         github_full_name: full_name,
         local_path: nil,
         default_branch: attrs |> map_get(:default_branch, "main") |> normalize_optional_string() || "main",
         settings: attrs |> map_get(:settings, %{}) |> normalize_map()
       }}
    end
  end

  defp build_local_project(attrs) do
    with {:ok, local_path} <- required_string(map_get(attrs, :local_path), :missing_local_path) do
      name =
        attrs
        |> map_get(:name)
        |> normalize_optional_string() || Path.basename(local_path)

      {:ok,
       %__MODULE__{
         id: attrs |> map_get(:id) |> normalize_optional_string() || JidoCode.UUID.generate(),
         name: name,
         source_kind: :local,
         source_identifier: local_path,
         github_full_name: nil,
         local_path: local_path,
         default_branch: attrs |> map_get(:default_branch, "main") |> normalize_optional_string() || "main",
         settings: attrs |> map_get(:settings, %{}) |> normalize_map()
       }}
    end
  end

  defp github_full_name(attrs) do
    attrs
    |> map_get(:github_full_name)
    |> normalize_optional_string()
    |> case do
      nil -> required_string(map_get(attrs, :source_identifier), :missing_github_full_name)
      full_name -> {:ok, full_name}
    end
  end

  defp maybe_sync_managed_repo(%__MODULE__{source_kind: :github} = project) do
    project
    |> Map.from_struct()
    |> Map.put(:legacy_project_id, project.id)
    |> RepoBridge.sync_project()
  end

  defp maybe_sync_managed_repo(%__MODULE__{}), do: {:ok, nil}

  defp project_from_scope(scope, source_repo) do
    managed_repo = Map.get(scope, :managed_repo) || %{}
    full_name = map_get(source_repo, :full_name)

    %__MODULE__{
      id: map_get(managed_repo, :legacy_project_id) || map_get(managed_repo, :id) || JidoCode.UUID.generate(),
      name: map_get(managed_repo, :display_name) || map_get(source_repo, :name),
      source_kind: :github,
      source_identifier: full_name,
      github_full_name: full_name,
      local_path: nil,
      default_branch: map_get(source_repo, :default_branch, "main"),
      settings: %{
        "workspace" => map_get(managed_repo, :workspace_settings, %{}),
        "execution" => map_get(managed_repo, :execution_settings, %{})
      }
    }
  end

  defp required_string(value, error) do
    case normalize_optional_string(value) do
      nil -> {:error, error}
      normalized -> {:ok, normalized}
    end
  end

  defp normalize_source_kind(value) when value in [:github, :local], do: value

  defp normalize_source_kind(value) when is_binary(value) do
    case String.trim(value) do
      "github" -> :github
      "local" -> :local
      other -> other
    end
  end

  defp normalize_source_kind(_value), do: :github

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp forbidden_error do
    %{
      type: :forbidden,
      reason: :missing_allowed_actor,
      message: "control-plane mutation requires an allowed actor"
    }
  end
end
