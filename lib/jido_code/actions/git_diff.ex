defmodule JidoCode.Actions.GitDiff do
  # covers: architecture.repository_runtime_integration.actions
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

  alias JidoCode.ContextBudget

  @impl true
  def run(%{path: path, cached: cached, max_lines: max_lines}, context) do
    with {:ok, workspace_path} <- workspace_path(context) do
      max_lines = ContextBudget.clamp_tool_limit(max_lines, :max_lines)
      args = build_diff_args(path, cached)
      {output, exit_code} = execute_git_command(workspace_path, args)

      bounded = ContextBudget.bound_tool_text(output, max_lines: max_lines)

      {:ok,
       %{
         workspace_path: workspace_path,
         path: path,
         cached: cached,
         exit_code: exit_code,
         diff: bounded.text,
         truncated: bounded.diagnostics.state == :truncated,
         lines: bounded.text |> String.split("\n") |> length(),
         budget: bounded.diagnostics
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
end
