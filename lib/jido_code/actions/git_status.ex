defmodule JidoCode.Actions.GitStatus do
  # covers: architecture.repository_runtime_integration.actions
  @moduledoc """
  Action to get git status for the workspace.
  """

  use Jido.Action,
    name: "jido_code_git_status",
    description: "Get git status for the workspace.",
    schema: [
      path: [type: :string, default: "."]
    ]

  @impl true
  def run(%{path: path}, context) do
    with {:ok, workspace_path} <- workspace_path(context),
         full_path = Path.expand(path, workspace_path),
         :ok <- validate_git_repo(full_path) do
      {output, exit_code} = execute_git_command(full_path, ["status", "--porcelain"])

      case exit_code do
        0 ->
          status = parse_git_status(output)
          branch = get_current_branch(full_path)

          {:ok,
           %{
             path: path,
             full_path: full_path,
             branch: branch,
             dirty: status != :clean,
             status: status,
             files: parse_files(output)
           }}

        _ ->
          {:ok,
           %{
             path: path,
             full_path: full_path,
             error: "git command failed",
             output: output
           }}
      end
    else
      {:error, :not_a_git_repo} ->
        {:ok,
         %{
           path: path,
           not_a_git_repo: true
         }}

      {:error, reason} ->
        {:error, reason}
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

  defp validate_git_repo(path) do
    git_dir = Path.join(path, ".git")

    if File.dir?(git_dir) or File.dir?(Path.join([path, "..", ".git"])) do
      :ok
    else
      {:error, :not_a_git_repo}
    end
  end

  defp execute_git_command(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, exit_code} -> {output, exit_code}
    end
  end

  defp get_current_branch(path) do
    {output, _exit_code} = execute_git_command(path, ["rev-parse", "--abbrev-ref", "HEAD"])
    String.trim(output)
  end

  defp parse_git_status(output) do
    if String.trim(output) == "" do
      :clean
    else
      :dirty
    end
  end

  defp parse_files(output) do
    output
    |> String.split("\n", trim: true)
    |> Enum.map(fn line ->
      <<status::binary-size(2), " ", file::binary>> = line

      %{
        file: file,
        status: parse_file_status(status)
      }
    end)
  end

  defp parse_file_status(<<m::utf8, s::utf8>>) do
    %{
      staged: status_code(m),
      unstaged: status_code(s)
    }
  end

  defp status_code(?\s), do: :unmodified
  defp status_code(?M), do: :modified
  defp status_code(?A), do: :added
  defp status_code(?D), do: :deleted
  defp status_code(?R), do: :renamed
  defp status_code(?C), do: :copied
  defp status_code(?U), do: :unmerged
  defp status_code(_), do: :unknown
end
