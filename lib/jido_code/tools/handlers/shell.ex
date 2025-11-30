defmodule JidoCode.Tools.Handlers.Shell do
  @moduledoc """
  Handler module for shell execution tools.

  This module contains the RunCommand handler for executing shell commands in a
  controlled environment with security validation, timeout enforcement, and output capture.

  ## Security Considerations

  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked to prevent bypass
  - **Path argument validation**: Arguments containing path traversal are blocked
  - **Directory containment**: Commands run in project directory (enforced via cd: option)
  - **Empty environment**: Prevents leaking sensitive environment variables
  - **Timeout enforcement**: Prevents hanging commands
  - **Output truncation**: Prevents memory exhaustion from large outputs

  ## Usage

  This handler is invoked by the Executor when the LLM calls shell tools:

      Executor.execute(%{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "mix", "args" => ["test"]}
      })

  ## Context

  The context map should contain:
  - `:project_root` - Base directory for command execution
  """

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Constants
  # ============================================================================

  @allowed_commands ~w(
    mix elixir iex
    git
    npm npx yarn pnpm node
    cargo rustc
    go
    python python3 pip pip3
    ls cat head tail grep find wc diff sort uniq
    test true false echo printf pwd
    mkdir rmdir cp mv ln touch rm
    date time sleep
    rebar3 erlc erl
    make cmake
    curl wget
  )

  @shell_interpreters ~w(bash sh zsh fish dash ksh csh tcsh ash)

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec get_project_root(map()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  @spec format_error(atom() | {atom(), term()} | String.t(), String.t()) :: String.t()
  def format_error(:enoent, command), do: "Command not found: #{command}"
  def format_error(:eacces, command), do: "Permission denied: #{command}"
  def format_error(:enomem, _command), do: "Out of memory"
  def format_error(:command_not_allowed, command), do: "Command not allowed: #{command}"
  def format_error(:shell_interpreter_blocked, command), do: "Shell interpreters are blocked: #{command}"
  def format_error(:path_traversal_blocked, arg), do: "Path traversal not allowed in argument: #{arg}"
  def format_error(:absolute_path_blocked, arg), do: "Absolute paths outside project not allowed: #{arg}"
  def format_error({kind, reason}, command), do: "Shell error executing #{command}: #{kind} - #{inspect(reason)}"
  def format_error(reason, command) when is_atom(reason), do: "Error (#{reason}): #{command}"
  def format_error(reason, _command) when is_binary(reason), do: reason
  def format_error(reason, command), do: "Error (#{inspect(reason)}): #{command}"

  @doc false
  @spec validate_command(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_command(command) do
    cond do
      command in @shell_interpreters ->
        {:error, :shell_interpreter_blocked}

      command in @allowed_commands ->
        {:ok, command}

      true ->
        {:error, :command_not_allowed}
    end
  end

  @doc false
  @spec allowed_commands() :: [String.t()]
  def allowed_commands, do: @allowed_commands

  @doc false
  @spec shell_interpreters() :: [String.t()]
  def shell_interpreters, do: @shell_interpreters

  # ============================================================================
  # RunCommand Handler
  # ============================================================================

  defmodule RunCommand do
    @moduledoc """
    Handler for the run_command tool.

    Executes shell commands in the project directory with security validation,
    timeout enforcement, and output size limits.
    """

    alias JidoCode.Tools.Handlers.Shell

    @default_timeout 25_000
    @max_output_size 1_048_576

    @doc """
    Executes a shell command.

    ## Arguments

    - `"command"` - Command to execute (must be in allowlist)
    - `"args"` - Command arguments (optional, default: [])
    - `"timeout"` - Timeout in milliseconds (optional, default: 25000)

    ## Returns

    - `{:ok, json}` - JSON with exit_code, stdout (stderr merged into stdout)
    - `{:error, reason}` - Error message

    ## Security

    - Command must be in the allowed commands list
    - Shell interpreters (bash, sh, etc.) are blocked
    - Arguments with path traversal patterns are blocked
    - Absolute paths outside project root are blocked
    - Output is truncated at 1MB to prevent memory exhaustion
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"command" => command} = args, context) when is_binary(command) do
      with {:ok, _valid_command} <- Shell.validate_command(command),
           {:ok, project_root} <- Shell.get_project_root(context),
           raw_args <- Map.get(args, "args", []),
           {:ok, cmd_args} <- validate_and_parse_args(raw_args, project_root) do
        timeout = Map.get(args, "timeout", @default_timeout)
        execute_with_timeout(command, cmd_args, project_root, timeout)
      else
        {:error, reason} when is_atom(reason) ->
          {:error, Shell.format_error(reason, command)}

        {:error, {:arg_error, reason, arg}} ->
          {:error, Shell.format_error(reason, arg)}

        {:error, reason} ->
          {:error, Shell.format_error(reason, command)}
      end
    end

    def execute(_args, _context) do
      {:error, "run_command requires a command argument"}
    end

    @spec validate_and_parse_args(term(), String.t()) ::
            {:ok, [String.t()]} | {:error, {:arg_error, atom(), String.t()}}
    defp validate_and_parse_args(args, project_root) when is_list(args) do
      Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
        arg_str = to_string(arg)

        case validate_arg(arg_str, project_root) do
          :ok -> {:cont, {:ok, acc ++ [arg_str]}}
          {:error, reason} -> {:halt, {:error, {:arg_error, reason, arg_str}}}
        end
      end)
    end

    defp validate_and_parse_args(_args, _project_root), do: {:ok, []}

    # System paths that are safe to access
    @safe_system_paths ~w(/dev/null /dev/zero /dev/urandom /dev/random /dev/stdin /dev/stdout /dev/stderr)

    @spec validate_arg(String.t(), String.t()) :: :ok | {:error, atom()}
    defp validate_arg(arg, project_root) do
      cond do
        String.contains?(arg, "..") ->
          {:error, :path_traversal_blocked}

        String.starts_with?(arg, "/") and arg in @safe_system_paths ->
          :ok

        String.starts_with?(arg, "/") and not String.starts_with?(arg, project_root) ->
          {:error, :absolute_path_blocked}

        true ->
          :ok
      end
    end

    @spec execute_with_timeout(String.t(), [String.t()], String.t(), non_neg_integer()) :: {:ok, String.t()}
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

    @spec run_command(String.t(), [String.t()], String.t()) :: {:ok, String.t()} | {:error, String.t()}
    defp run_command(command, args, project_root) do
      # Use stderr_to_stdout to capture all output together
      # This is simpler and sufficient for LLM consumption
      {output, exit_code} =
        System.cmd(command, args,
          cd: project_root,
          stderr_to_stdout: true,
          env: []
        )

      truncated_output = maybe_truncate(output)

      result = %{
        exit_code: exit_code,
        stdout: truncated_output,
        stderr: ""
      }

      {:ok, Jason.encode!(result)}
    catch
      :error, :enoent ->
        {:error, Shell.format_error(:enoent, command)}

      :error, :eacces ->
        {:error, Shell.format_error(:eacces, command)}

      :error, :enomem ->
        {:error, Shell.format_error(:enomem, command)}

      kind, reason ->
        {:error, Shell.format_error({kind, reason}, command)}
    end

    @spec maybe_truncate(String.t()) :: String.t()
    defp maybe_truncate(output) when byte_size(output) > @max_output_size do
      truncated = binary_part(output, 0, @max_output_size)
      truncated <> "\n\n[Output truncated at 1MB]"
    end

    defp maybe_truncate(output), do: output
  end
end
