defmodule JidoCode.Actions.RunTests do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to run tests in the workspace.

  Supports running specific test files or all tests,
  with configurable timeout.
  """

  use Jido.Action,
    name: "jido_code_run_tests",
    description: "Run tests in the workspace.",
    schema: [
      test_path: [type: :string, default: nil],
      command: [type: :string, default: nil],
      timeout_ms: [type: :integer, default: 60_000]
    ]

  @impl true
  def run(%{test_path: test_path, command: command, timeout_ms: timeout_ms}, context) do
    with {:ok, workspace_path} <- workspace_path(context),
         :ok <- validate_workspace(workspace_path) do
      cmd = build_command(command, test_path)
      {output, exit_code} = execute_test_command(workspace_path, cmd, timeout_ms)

      passed = exit_code == 0
      failed = not passed

      {:ok,
       %{
         workspace_path: workspace_path,
         test_path: test_path,
         command: cmd,
         exit_code: exit_code,
         passed: passed,
         failed: failed,
         output: truncate_output(output)
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

  defp validate_workspace(path) do
    if File.dir?(path), do: :ok, else: {:error, :invalid_workspace}
  end

  defp build_command(nil, nil), do: "mix test"
  defp build_command(command, _test_path) when is_binary(command), do: command
  defp build_command(nil, test_path), do: "mix test #{test_path}"

  defp execute_test_command(workspace_path, cmd, timeout_ms) do
    cmd_parts = String.split(cmd, " ", trim: true)

    output =
      case cmd_parts do
        [] -> ""
        _ ->
          {result, _exit_code} =
            System.cmd(
              hd(cmd_parts),
              tl(cmd_parts),
              cd: workspace_path,
              stderr_to_stdout: true,
              timeout: timeout_ms
            )

          result
      end

    # Try to parse exit code from output (mix doesn't always return accurate exit codes)
    exit_code = parse_exit_code(output)

    {output, exit_code}
  end

  defp parse_exit_code(output) do
    # Look for typical ExUnit output patterns
    cond do
      String.contains?(output, ["1 failure", " failures"]) -> 1
      String.contains?(output, ["0 failures", "0 tests"]) -> 0
      String.contains?(output, "Finished in") and not String.contains?(output, "failure") -> 0
      String.contains?(output, "error") -> 1
      true -> 0
    end
  end

  defp truncate_output(output) when byte_size(output) > 10_000 do
    {truncated, _} = String.split_at(output, 10_000)
    truncated <> "\n\n... (output truncated)"
  end

  defp truncate_output(output), do: output
end
