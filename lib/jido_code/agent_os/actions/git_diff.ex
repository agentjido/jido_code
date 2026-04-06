defmodule JidoCode.AgentOS.Actions.GitDiff do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to get git diff for the workspace.
  """

  use Jido.Action,
    name: "jido_code_git_diff",
    description: "Get git diff for the workspace.",
    schema: [
      path: [type: :string, default: nil],
      cached: [type: :boolean, default: false],
      max_lines: [type: :integer, default: 500]
    ]

  @impl true
  def run(%{path: path, cached: cached, max_lines: max_lines}, context) do
    with {:ok, workspace_path} <- workspace_path(context) do
      args = build_diff_args(path, cached)
      {output, exit_code} = execute_git_command(workspace_path, args)

      diff_output = truncate_lines(output, max_lines)

      {:ok,
       %{
         workspace_path: workspace_path,
         path: path,
         cached: cached,
         exit_code: exit_code,
         diff: diff_output,
         truncated: String.split(output, "\n") |> length() > max_lines,
         lines: String.split(diff_output, "\n") |> length()
       }}
    else
      {:error, :missing_workspace_path} -> {:error, :invalid_context, "Missing workspace_path in context"}
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

  defp build_diff_args(nil, false), do: ["diff"]
  defp build_diff_args(nil, true), do: ["diff", "--cached"]
  defp build_diff_args(path, false), do: ["diff", "--", path]
  defp build_diff_args(path, true), do: ["diff", "--cached", "--", path]

  defp execute_git_command(path, args) do
    System.cmd("git", args, cd: path, stderr_to_stdout: true)
  end

  defp truncate_lines(output, max_lines) do
    lines = String.split(output, "\n")

    if length(lines) > max_lines do
      truncated = Enum.take(lines, max_lines)
      Enum.join(truncated, "\n") <> "\n\n... (diff truncated at #{max_lines} lines)"
    else
      output
    end
  end
end
