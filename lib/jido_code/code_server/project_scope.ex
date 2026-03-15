defmodule JidoCode.CodeServer.ProjectScope do
  @moduledoc """
  Resolves project scope required by the `JidoCode.CodeServer` facade.
  """

  alias JidoCode.CodeServer.Error
  alias JidoCode.Projects.Project

  @project_not_found_remediation """
  Open Workbench, select an imported project, and retry the conversation action.
  """

  @workspace_unavailable_remediation """
  Complete project import and baseline sync, then ensure a local absolute workspace path is available.
  """

  @workspace_environment_unsupported_remediation """
  Switch the project workspace environment to local and rerun baseline sync before starting a conversation.
  """

  @type scope :: %{
          project_id: String.t(),
          root_path: String.t(),
          project: map()
        }

  @spec resolve(term()) :: {:ok, scope()} | {:error, Error.typed_error()}
  def resolve(project_id) do
    with {:ok, normalized_project_id} <- normalize_project_id(project_id),
         {:ok, project} <- fetch_project(normalized_project_id),
         {:ok, root_path} <- resolve_workspace_root(project, normalized_project_id) do
      {:ok, %{project_id: normalized_project_id, root_path: root_path, project: project}}
    end
  end

  defp normalize_project_id(project_id) do
    case normalize_optional_string(project_id) do
      nil ->
        {:error,
         Error.build(
           "code_server_project_not_found",
           "Project identifier is missing.",
           @project_not_found_remediation
         )}

      normalized_project_id ->
        {:ok, normalized_project_id}
    end
  end

  defp fetch_project(project_id) do
    case project_reader_module().read(query: [filter: [id: project_id], limit: 1]) do
      {:ok, [project | _rest]} ->
        {:ok, project}

      {:ok, []} ->
        {:error,
         Error.build(
           "code_server_project_not_found",
           "Project #{project_id} was not found.",
           @project_not_found_remediation,
           project_id: project_id
         )}

      {:error, reason} ->
        {:error,
         Error.build(
           "code_server_project_not_found",
           "Project lookup failed (#{format_reason(reason)}).",
           @project_not_found_remediation,
           project_id: project_id
         )}
    end
  end

  defp project_reader_module do
    Application.get_env(:jido_code, :code_server_project_reader_module, Project)
  end

  defp resolve_workspace_root(project, project_id) when is_map(project) do
    settings =
      project
      |> map_get(:settings, "settings", %{})
      |> normalize_map()

    workspace_settings =
      settings
      |> map_get(:workspace, "workspace", %{})
      |> normalize_map()

    with :ok <- validate_workspace_readiness(workspace_settings, project_id) do
      case normalize_workspace_environment(
             map_get(workspace_settings, :workspace_environment, "workspace_environment", nil)
           ) do
        :local ->
          workspace_settings
          |> map_get(:workspace_path, "workspace_path", nil)
          |> validate_workspace_path(project_id)

        :sprite ->
          {:error,
           Error.build(
             "code_server_workspace_environment_unsupported",
             "Project workspace environment is sprite/cloud and cannot run local conversations.",
             @workspace_environment_unsupported_remediation,
             project_id: project_id
           )}

        :unknown ->
          {:error,
           Error.build(
             "code_server_workspace_environment_unsupported",
             "Project workspace environment is unavailable or unsupported.",
             @workspace_environment_unsupported_remediation,
             project_id: project_id
           )}
      end
    end
  end

  defp resolve_workspace_root(_project, project_id) do
    {:error,
     Error.build(
       "code_server_workspace_unavailable",
       "Project settings are unavailable for workspace resolution.",
       @workspace_unavailable_remediation,
       project_id: project_id
     )}
  end

  defp validate_workspace_path(path, project_id) do
    normalized_path = normalize_optional_string(path)

    cond do
      is_nil(normalized_path) ->
        {:error,
         Error.build(
           "code_server_workspace_unavailable",
           "Local workspace path is missing from project settings.",
           @workspace_unavailable_remediation,
           project_id: project_id
         )}

      Path.type(normalized_path) != :absolute ->
        {:error,
         Error.build(
           "code_server_workspace_unavailable",
           "Workspace path must be absolute: #{normalized_path}.",
           @workspace_unavailable_remediation,
           project_id: project_id
         )}

      not File.dir?(normalized_path) ->
        {:error,
         Error.build(
           "code_server_workspace_unavailable",
           "Workspace path does not exist on disk: #{normalized_path}.",
           @workspace_unavailable_remediation,
           project_id: project_id
         )}

      true ->
        {:ok, normalized_path}
    end
  end

  defp validate_workspace_readiness(workspace_settings, project_id) when is_map(workspace_settings) do
    clone_status =
      workspace_settings
      |> map_get(:clone_status, "clone_status")
      |> normalize_clone_status()

    workspace_initialized? =
      workspace_settings
      |> map_get(:workspace_initialized, "workspace_initialized", false)
      |> truthy?()

    baseline_synced? =
      workspace_settings
      |> map_get(:baseline_synced, "baseline_synced", false)
      |> truthy?()

    if clone_status == :ready and workspace_initialized? and baseline_synced? do
      :ok
    else
      retry_instructions =
        workspace_settings
        |> map_get(:retry_instructions, "retry_instructions")
        |> normalize_optional_string()

      workspace_error_type =
        workspace_settings
        |> map_get(:last_error_type, "last_error_type")
        |> normalize_optional_string()

      detail =
        clone_status
        |> blocked_readiness_detail(workspace_initialized?, baseline_synced?)
        |> append_workspace_error_type(workspace_error_type)

      {:error,
       Error.build(
         "code_server_workspace_unavailable",
         detail,
         retry_instructions || @workspace_unavailable_remediation,
         project_id: project_id
       )}
    end
  end

  defp validate_workspace_readiness(_workspace_settings, project_id) do
    {:error,
     Error.build(
       "code_server_workspace_unavailable",
       "Project workspace metadata is unavailable.",
       @workspace_unavailable_remediation,
       project_id: project_id
     )}
  end

  defp blocked_readiness_detail(:ready, _workspace_initialized?, _baseline_synced?) do
    "Project workspace metadata is incomplete for conversations."
  end

  defp blocked_readiness_detail(:cloning, _workspace_initialized?, _baseline_synced?) do
    "Project workspace clone is still running."
  end

  defp blocked_readiness_detail(:pending, _workspace_initialized?, _baseline_synced?) do
    "Project workspace import has not completed yet."
  end

  defp blocked_readiness_detail(:error, _workspace_initialized?, _baseline_synced?) do
    "Project workspace clone or baseline sync failed."
  end

  defp blocked_readiness_detail(_clone_status, _workspace_initialized?, _baseline_synced?) do
    "Project workspace prerequisites are incomplete for conversation runtime."
  end

  defp append_workspace_error_type(detail, nil), do: detail

  defp append_workspace_error_type(detail, workspace_error_type),
    do: "#{detail} (workspace error: #{workspace_error_type})."

  defp normalize_workspace_environment(:local), do: :local
  defp normalize_workspace_environment("local"), do: :local
  defp normalize_workspace_environment(:sprite), do: :sprite
  defp normalize_workspace_environment("sprite"), do: :sprite
  defp normalize_workspace_environment(:cloud), do: :sprite
  defp normalize_workspace_environment("cloud"), do: :sprite
  defp normalize_workspace_environment(_other), do: :unknown

  defp normalize_clone_status(:pending), do: :pending
  defp normalize_clone_status(:cloning), do: :cloning
  defp normalize_clone_status(:ready), do: :ready
  defp normalize_clone_status(:error), do: :error
  defp normalize_clone_status("pending"), do: :pending
  defp normalize_clone_status("cloning"), do: :cloning
  defp normalize_clone_status("ready"), do: :ready
  defp normalize_clone_status("error"), do: :error
  defp normalize_clone_status(_clone_status), do: nil

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("TRUE"), do: true
  defp truthy?("1"), do: true
  defp truthy?(1), do: true
  defp truthy?(_value), do: false

  defp format_reason(reason) do
    Exception.message(reason)
  rescue
    _exception -> inspect(reason)
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_boolean(value), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized_value -> normalized_value
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(value) when is_float(value), do: :erlang.float_to_binary(value)
  defp normalize_optional_string(_value), do: nil

  defp normalize_map(value) when is_map(value), do: value
  defp normalize_map(_value), do: %{}

  defp map_get(map, atom_key, string_key, default \\ nil)

  defp map_get(map, atom_key, string_key, default) when is_map(map) do
    cond do
      Map.has_key?(map, atom_key) -> Map.get(map, atom_key)
      Map.has_key?(map, string_key) -> Map.get(map, string_key)
      true -> default
    end
  end

  defp map_get(_map, _atom_key, _string_key, default), do: default
end
