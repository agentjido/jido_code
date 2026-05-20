defmodule JidoCode.Actions.ReadFile do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to read a file from the workspace.

  Resolves paths relative to the workspace root and supports
  truncation for large files.
  """

  use Jido.Action,
    name: "jido_code_read_file",
    description: "Read a file from the workspace.",
    schema: [
      path: [type: :string, required: true],
      max_chars: [type: :integer, default: 50_000]
    ]

  alias JidoCode.ContextBudget

  @impl true
  def run(%{path: path, max_chars: max_chars}, context) do
    with {:ok, workspace_path} <- workspace_path(context),
         full_path = Path.expand(path, workspace_path),
         :ok <- validate_path_within_workspace(full_path, workspace_path),
         {:ok, content} <- File.read(full_path) do
      max_bytes = ContextBudget.clamp_tool_limit(max_chars, :max_bytes)
      bounded = ContextBudget.bound_tool_text(content, max_bytes: max_bytes)

      {:ok,
       %{
         path: path,
         full_path: full_path,
         content: bounded.text,
         size: String.length(content),
         truncated?: bounded.diagnostics.state == :truncated,
         budget: bounded.diagnostics
       }}
    else
      {:error, :enoent} -> {:error, :file_not_found, "File not found: #{path}"}
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
end
