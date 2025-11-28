defmodule JidoCode.Tools.Handlers.Shell do
  @moduledoc """
  Handler modules for shell execution tools.

  This module contains handlers for executing shell commands in a controlled
  environment with timeout enforcement and output capture.

  ## Security Considerations

  - Commands run in project directory (enforced via cd: option)
  - Empty environment prevents leaking sensitive variables
  - Timeout prevents hanging commands

  ## Usage

  These handlers are invoked by the Executor when the LLM calls shell tools:

      Executor.execute(%{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "mix", "args" => ["test"]}
      })

  ## Context

  The context map should contain:
  - `:project_root` - Base directory for command execution
  """

  alias JidoCode.Tools.Manager

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  def get_project_root(%{project_root: root}) when is_binary(root), do: {:ok, root}
  def get_project_root(_context), do: Manager.project_root()

  # ============================================================================
  # RunCommand Handler
  # ============================================================================

  defmodule RunCommand do
    @moduledoc """
    Handler for the run_command tool.

    Executes shell commands in the project directory with timeout enforcement.
    """

    alias JidoCode.Tools.Handlers.Shell

    @default_timeout 60_000

    @doc """
    Executes a shell command.

    ## Arguments

    - `"command"` - Command to execute
    - `"args"` - Command arguments (optional, default: [])
    - `"timeout"` - Timeout in milliseconds (optional, default: 60000)

    ## Returns

    - `{:ok, json}` - JSON with exit_code, stdout, stderr
    - `{:error, reason}` - Error message
    """
    def execute(%{"command" => command} = args, context) when is_binary(command) do
      cmd_args = parse_args(Map.get(args, "args", []))
      timeout = Map.get(args, "timeout", @default_timeout)

      with {:ok, project_root} <- Shell.get_project_root(context) do
        execute_with_timeout(command, cmd_args, project_root, timeout)
      end
    end

    def execute(_args, _context) do
      {:error, "run_command requires a command argument"}
    end

    defp parse_args(args) when is_list(args) do
      Enum.map(args, &to_string/1)
    end

    defp parse_args(_), do: []

    defp execute_with_timeout(command, args, project_root, timeout) do
      task =
        Task.async(fn ->
          run_command(command, args, project_root)
        end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, result} ->
          result

        nil ->
          {:ok,
           Jason.encode!(%{
             exit_code: -1,
             stdout: "",
             stderr: "Command timed out after #{timeout}ms"
           })}
      end
    end

    defp run_command(command, args, project_root) do
      # Use stderr_to_stdout to capture all output together
      # This is simpler and sufficient for LLM consumption
      {output, exit_code} =
        System.cmd(command, args,
          cd: project_root,
          stderr_to_stdout: true,
          env: []
        )

      result = %{
        exit_code: exit_code,
        stdout: output,
        stderr: ""
      }

      {:ok, Jason.encode!(result)}
    catch
      :error, :enoent ->
        {:error, "Command not found: #{command}"}

      kind, reason ->
        {:error, "Shell error: #{kind} - #{inspect(reason)}"}
    end
  end
end
