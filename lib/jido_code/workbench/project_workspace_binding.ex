defmodule JidoCode.Workbench.ProjectWorkspaceBinding do
  @moduledoc """
  Validates and updates repo-scoped workspace binding for one managed repository.
  """

  alias Ash.Error.Forbidden
  alias JidoCode.Control.ManagedRepo

  @default_error_type "managed_repo_workspace_binding_update_failed"
  @missing_repo_error_type "managed_repo_workspace_binding_repo_not_found"
  @missing_path_error_type "managed_repo_workspace_path_required"
  @invalid_path_error_type "managed_repo_workspace_path_invalid"
  @missing_directory_error_type "managed_repo_workspace_path_missing"
  @unsupported_environment_error_type "managed_repo_workspace_environment_invalid"
  @forbidden_error_type "managed_repo_workspace_binding_update_forbidden"

  @default_remediation "Review the repository workspace binding inputs and retry."
  @local_path_remediation "Choose an existing absolute local workspace path for this repository and retry."
  @missing_repo_remediation "Open an imported managed repository and retry the workspace update."

  @type update_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t()
        }

  @type update_result :: %{
          managed_repo: ManagedRepo.t(),
          workspace_settings: map()
        }

  @spec update(term(), map() | nil, map() | nil) :: {:ok, update_result()} | {:error, update_error()}
  def update(identifier, attrs, actor) when is_map(attrs) do
    with {:ok, managed_repo} <- load_managed_repo(identifier, actor),
         {:ok, workspace_settings} <- next_workspace_settings(managed_repo, attrs),
         {:ok, updated_managed_repo} <-
           ManagedRepo.update(managed_repo, %{workspace_settings: workspace_settings}, actor: actor) do
      {:ok, %{managed_repo: updated_managed_repo, workspace_settings: workspace_settings}}
    else
      {:error, %{error_type: _error_type} = error} ->
        {:error, error}

      {:error, %Forbidden{}} ->
        {:error,
         update_error(
           @forbidden_error_type,
           "Current actor is not allowed to update this repository workspace binding.",
           @default_remediation
         )}

      {:error, reason} ->
        {:error,
         update_error(
           @default_error_type,
           "Repository workspace binding update failed (#{format_reason(reason)}).",
           @default_remediation
         )}
    end
  end

  def update(_identifier, _attrs, _actor) do
    {:error,
     update_error(
       @default_error_type,
       "Repository workspace binding update requires workspace-binding attributes.",
       @default_remediation
     )}
  end

  defp load_managed_repo(%ManagedRepo{} = managed_repo, _actor), do: {:ok, managed_repo}

  defp load_managed_repo(identifier, actor) do
    case normalize_managed_repo_id(identifier) do
      nil ->
        {:error,
         update_error(
           @missing_repo_error_type,
           "Managed repository scope is missing for workspace binding update.",
           @missing_repo_remediation
         )}

      managed_repo_id ->
        case ManagedRepo.read(query: [filter: [id: managed_repo_id], limit: 1], actor: actor) do
          {:ok, [%ManagedRepo{} = managed_repo | _rest]} ->
            {:ok, managed_repo}

          {:ok, []} ->
            {:error,
             update_error(
               @missing_repo_error_type,
               "Managed repository #{managed_repo_id} was not found for workspace binding update.",
               @missing_repo_remediation
             )}

          {:error, %Forbidden{} = error} ->
            {:error, error}

          {:error, reason} ->
            {:error,
             update_error(
               @default_error_type,
               "Repository workspace binding lookup failed (#{format_reason(reason)}).",
               @missing_repo_remediation
             )}
        end
    end
  end

  defp next_workspace_settings(%ManagedRepo{} = managed_repo, attrs) when is_map(attrs) do
    existing_workspace_settings =
      managed_repo
      |> Map.get(:workspace_settings, %{})
      |> normalize_map()

    normalized_attrs = normalize_map(attrs)

    case workspace_binding_update(normalized_attrs) do
      {:ok, binding_update} ->
        {:ok, Map.merge(existing_workspace_settings, binding_update)}

      {:error, %{error_type: _error_type} = error} ->
        {:error, error}
    end
  end

  defp workspace_binding_update(attrs) when is_map(attrs) do
    workspace_environment =
      attrs
      |> Map.get("workspace_environment")
      |> normalize_workspace_environment()

    workspace_path =
      attrs
      |> Map.get("workspace_path")
      |> normalize_optional_string()

    workspace_root =
      attrs
      |> Map.get("workspace_root")
      |> normalize_optional_string()

    cond do
      workspace_environment in [:sprite, :cloud] ->
        {:ok,
         %{
           "workspace_environment" => "sprite",
           "workspace_root" => nil,
           "workspace_path" => nil
         }}

      workspace_environment == :local or is_binary(workspace_path) or is_binary(workspace_root) ->
        local_workspace_binding_update(workspace_path)

      true ->
        {:error,
         update_error(
           @unsupported_environment_error_type,
           "Repository workspace binding update must choose `local` or `sprite` execution.",
           @default_remediation
         )}
    end
  end

  defp local_workspace_binding_update(nil) do
    {:error,
     update_error(
       @missing_path_error_type,
       "Repo-scoped local workspace updates require an explicit workspace path; the workspace root is derived from that path.",
       @local_path_remediation
     )}
  end

  defp local_workspace_binding_update(workspace_path) when is_binary(workspace_path) do
    cond do
      Path.type(workspace_path) != :absolute ->
        {:error,
         update_error(
           @invalid_path_error_type,
           "Repo-scoped local workspace path must be absolute.",
           @local_path_remediation
         )}

      not File.dir?(workspace_path) ->
        {:error,
         update_error(
           @missing_directory_error_type,
           "Repo-scoped local workspace path does not exist on disk.",
           @local_path_remediation
         )}

      true ->
        normalized_workspace_path = Path.expand(workspace_path)

        {:ok,
         %{
           "workspace_environment" => "local",
           "workspace_root" => Path.dirname(normalized_workspace_path),
           "workspace_path" => normalized_workspace_path
         }}
    end
  end

  defp normalize_managed_repo_id(%{} = identifier) do
    identifier
    |> map_get(:managed_repo_id, "managed_repo_id")
    |> fallback_optional_string(
      identifier
      |> map_get(:id, "id")
      |> normalize_optional_string()
    )
  end

  defp normalize_managed_repo_id(identifier), do: normalize_optional_string(identifier)

  defp normalize_workspace_environment(:local), do: :local
  defp normalize_workspace_environment(:sprite), do: :sprite
  defp normalize_workspace_environment(:cloud), do: :cloud
  defp normalize_workspace_environment("local"), do: :local
  defp normalize_workspace_environment("sprite"), do: :sprite
  defp normalize_workspace_environment("cloud"), do: :cloud
  defp normalize_workspace_environment(_workspace_environment), do: nil

  defp map_get(%{} = map, atom_key, string_key) do
    case Map.fetch(map, atom_key) do
      {:ok, value} -> value
      :error -> Map.get(map, string_key)
    end
  end

  defp map_get(_map, _atom_key, _string_key), do: nil

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

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(_value), do: nil

  defp fallback_optional_string(nil, fallback), do: fallback
  defp fallback_optional_string(value, _fallback), do: value

  defp update_error(error_type, detail, remediation) do
    %{
      error_type: error_type,
      detail: detail,
      remediation: remediation
    }
  end

  defp format_reason(%module{} = reason), do: Exception.message(reason) || inspect(module)
  defp format_reason(reason), do: inspect(reason)
end
