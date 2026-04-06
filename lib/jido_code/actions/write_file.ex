defmodule JidoCode.Actions.WriteFile do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to write content to a file in the workspace.

  Creates parent directories as needed and supports
  atomic writes for safety.
  """

  use Jido.Action,
    name: "jido_code_write_file",
    description: "Write content to a file in the workspace.",
    schema: [
      path: [type: :string, required: true],
      content: [type: :string, required: true],
      create_dirs: [type: :boolean, default: true]
    ]

  @impl true
  def run(%{path: path, content: content, create_dirs: create_dirs}, context) do
    with {:ok, workspace_path} <- workspace_path(context),
         full_path = Path.expand(path, workspace_path),
         :ok <- validate_path_within_workspace(full_path, workspace_path),
         :ok <- maybe_create_dirs(full_path, create_dirs) do
      case File.write(full_path, content) do
        :ok ->
          {:ok,
           %{
             path: path,
             full_path: full_path,
             bytes_written: byte_size(content),
             chars_written: String.length(content)
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :outside_workspace} -> {:error, :invalid_path, "Path outside workspace: #{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp workspace_path(context) do
    path =
      context[:workspace_path] ||
        get_in(context, [:project, :workspace_path]) ||
        get_in(context, [:tool_context, :workspace_path]) ||
        get_in(context, [:tool_context, "workspace_path"])

    if is_binary(path) and String.trim(path) != "" do
      {:ok, path}
    else
      {:error, :missing_workspace_path}
    end
  end

  defp validate_path_within_workspace(path, workspace_path) do
    workspace_expanded = Path.expand(workspace_path)
    path_expanded = Path.expand(path)

    case String.starts_with?(path_expanded, workspace_expanded) do
      true -> :ok
      false -> {:error, :outside_workspace}
    end
  end

  defp maybe_create_dirs(full_path, true) do
    dir = Path.dirname(full_path)
    case File.mkdir_p(dir) do
      :ok -> :ok
      {:error, reason} -> {:error, {:mkdir_failed, reason}}
    end
  end

  defp maybe_create_dirs(_full_path, false), do: :ok
end
