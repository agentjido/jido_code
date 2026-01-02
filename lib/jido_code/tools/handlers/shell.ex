defmodule JidoCode.Tools.Handlers.Shell do
  @moduledoc """
  Handler module for shell execution tools.

  This module contains the RunCommand handler for executing shell commands in a
  controlled environment with security validation, timeout enforcement, and output capture.

  ## Session Context

  Handlers use `HandlerHelpers.get_project_root/1` for session-aware working directory:

  1. `session_id` present → Uses `Session.Manager.project_root/1`
  2. `project_root` present → Uses provided project root (legacy)
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Security Considerations

  - **Command allowlist**: Only pre-approved commands can be executed
  - **Shell interpreter blocking**: bash, sh, zsh, etc. are blocked to prevent bypass
  - **Path argument validation**: Arguments containing path traversal are blocked
  - **Directory containment**: Commands run in session's project directory
  - **Timeout enforcement**: Prevents hanging commands
  - **Output truncation**: Prevents memory exhaustion from large outputs

  ## Usage

  This handler is invoked by the Executor when the LLM calls shell tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "run_command",
        arguments: %{"command" => "mix", "args" => ["test"]}
      }, context: context)

  ## Context

  The context map should contain:
  - `:session_id` - Session ID for project root lookup (preferred)
  - `:project_root` - Base directory for command execution (legacy)
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
  @spec validate_path(String.t(), map()) ::
          {:ok, String.t()} | {:error, atom() | :not_found | :invalid_session_id}
  defdelegate validate_path(path, context), to: HandlerHelpers

  # ============================================================================
  # Telemetry
  # ============================================================================

  @doc false
  @spec emit_shell_telemetry(atom(), integer(), String.t(), map(), atom(), integer()) :: :ok
  def emit_shell_telemetry(operation, start_time, command, context, status, exit_code) do
    duration = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      [:jido_code, :shell, operation],
      %{duration: duration, exit_code: exit_code},
      %{
        command: command,
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  @doc false
  @spec format_error(atom() | {atom(), term()} | String.t(), String.t()) :: String.t()
  def format_error(:enoent, command), do: "Command not found: #{command}"
  def format_error(:eacces, command), do: "Permission denied: #{command}"
  def format_error(:enomem, _command), do: "Out of memory"
  def format_error(:command_not_allowed, command), do: "Command not allowed: #{command}"

  def format_error(:shell_interpreter_blocked, command),
    do: "Shell interpreters are blocked: #{command}"

  def format_error(:timeout, command),
    do: "Command timed out: #{command}"

  def format_error(:path_traversal_blocked, arg),
    do: "Path traversal not allowed in argument: #{arg}"

  def format_error(:absolute_path_blocked, arg),
    do: "Absolute paths outside project not allowed: #{arg}"

  def format_error({:path_traversal_blocked, arg}, _command),
    do: "Path traversal not allowed in argument: #{arg}"

  def format_error({:absolute_path_blocked, arg}, _command),
    do: "Absolute paths outside project not allowed: #{arg}"

  def format_error({kind, reason}, command),
    do: "Shell error executing #{command}: #{kind} - #{inspect(reason)}"

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

    Uses session-aware project root via `HandlerHelpers.get_project_root/1`.
    """

    alias JidoCode.Tools.Handlers.Shell

    @default_timeout 25_000
    @max_timeout 120_000
    @max_output_size 1_048_576

    @doc """
    Executes a shell command.

    ## Arguments

    - `"command"` - Command to execute (must be in allowlist)
    - `"args"` - Command arguments (optional, default: [])
    - `"timeout"` - Timeout in milliseconds (optional, default: 25000)

    ## Context

    - `:session_id` - Session ID for project root lookup (preferred)
    - `:project_root` - Direct project root path (legacy)

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
      start_time = System.monotonic_time(:microsecond)

      with {:ok, _valid_command} <- Shell.validate_command(command),
           {:ok, project_root} <- Shell.get_project_root(context),
           raw_args <- Map.get(args, "args", []),
           cmd_args <- parse_args(raw_args),
           :ok <- validate_path_args(cmd_args, project_root) do
        timeout = cap_timeout(Map.get(args, "timeout", @default_timeout))
        run_command(command, cmd_args, project_root, timeout, start_time, context)
      else
        {:error, reason} when is_atom(reason) ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error(reason, command)}

        {:error, reason} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error(reason, command)}
      end
    end

    def execute(_args, _context) do
      {:error, "run_command requires a command argument"}
    end

    defp parse_args(args) when is_list(args) do
      Enum.map(args, &to_string/1)
    end

    defp parse_args(_args), do: []

    # Cap timeout to prevent resource exhaustion from extremely long timeouts
    defp cap_timeout(timeout) when is_integer(timeout) and timeout > @max_timeout,
      do: @max_timeout

    defp cap_timeout(timeout) when is_integer(timeout) and timeout > 0, do: timeout
    defp cap_timeout(_), do: @default_timeout

    # Validate path-like arguments against project boundary
    defp validate_path_args(args, project_root) do
      Enum.reduce_while(args, :ok, fn arg, _acc ->
        case validate_single_arg(arg, project_root) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end

    # Special system paths that are always allowed
    @allowed_system_paths ~w(/dev/null /dev/stdin /dev/stdout /dev/stderr /dev/zero /dev/random /dev/urandom)

    # Check for path traversal patterns including URL-encoded variants
    defp contains_path_traversal?(arg) do
      lower = String.downcase(arg)

      String.contains?(arg, "../") or
        String.contains?(lower, "%2e%2e%2f") or
        String.contains?(lower, "%2e%2e/") or
        String.contains?(lower, "..%2f") or
        String.contains?(lower, "%2e%2e%5c") or
        String.contains?(lower, "..%5c")
    end

    defp validate_single_arg(arg, project_root) do
      cond do
        # Check for path traversal patterns (literal and URL-encoded)
        contains_path_traversal?(arg) ->
          {:error, {:path_traversal_blocked, arg}}

        # Allow special system paths
        arg in @allowed_system_paths ->
          :ok

        # Check absolute paths - must be within project
        String.starts_with?(arg, "/") ->
          expanded = Path.expand(arg)

          if String.starts_with?(expanded, project_root) do
            :ok
          else
            {:error, {:absolute_path_blocked, arg}}
          end

        # Relative paths and non-path args are OK
        true ->
          :ok
      end
    end

    defp run_command(command, args, project_root, timeout, start_time, context) do
      # Use Task.async with yield/shutdown to enforce timeout
      task =
        Task.async(fn ->
          try do
            System.cmd(command, args,
              cd: project_root,
              stderr_to_stdout: true,
              env: []
            )
          rescue
            e in ErlangError -> {:error, e.original}
          catch
            :exit, reason -> {:error, {:exit, reason}}
          end
        end)

      case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
        {:ok, {:error, :enoent}} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error(:enoent, command)}

        {:ok, {:error, :eacces}} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error(:eacces, command)}

        {:ok, {:error, {:exit, reason}}} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error({:exit, reason}, command)}

        {:ok, {:error, reason}} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :error, -1)
          {:error, Shell.format_error({:system_error, reason}, command)}

        {:ok, {output, exit_code}} ->
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :ok, exit_code)
          stdout = maybe_truncate(output)

          formatted = %{
            exit_code: exit_code,
            stdout: stdout,
            stderr: ""
          }

          {:ok, Jason.encode!(formatted)}

        nil ->
          # Timeout - task was killed
          Shell.emit_shell_telemetry(:run_command, start_time, command, context, :timeout, -1)
          {:error, Shell.format_error(:timeout, command)}
      end
    end

    @spec maybe_truncate(String.t()) :: String.t()
    defp maybe_truncate(output) when is_binary(output) and byte_size(output) > @max_output_size do
      truncated = binary_part(output, 0, @max_output_size)
      truncated <> "\n\n[Output truncated at 1MB]"
    end

    defp maybe_truncate(output) when is_binary(output), do: output
    defp maybe_truncate(_), do: ""
  end

  # ============================================================================
  # BashBackground Handler
  # ============================================================================

  defmodule BashBackground do
    @moduledoc """
    Handler for the bash_background tool.

    Starts a command in the background, returning a shell_id that can be used
    to retrieve output later via bash_output or terminate the process via kill_shell.

    Uses session-aware project root via `HandlerHelpers.get_project_root/1`.
    """

    alias JidoCode.Tools.BackgroundShell
    alias JidoCode.Tools.Handlers.Shell

    @doc """
    Starts a background command.

    ## Arguments

    - `"command"` - Command to execute (must be in allowlist)
    - `"args"` - Command arguments (optional, default: [])
    - `"description"` - Optional description for tracking

    ## Context

    - `:session_id` - Session ID for process tracking (required)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON with shell_id and description
    - `{:error, reason}` - Error message

    ## Security

    - Command must be in the allowed commands list
    - Shell interpreters (bash, sh, etc.) are blocked
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"command" => command} = args, context) when is_binary(command) do
      start_time = System.monotonic_time(:microsecond)

      with {:ok, session_id} <- get_session_id(context),
           {:ok, project_root} <- Shell.get_project_root(context),
           raw_args <- Map.get(args, "args", []),
           cmd_args <- parse_args(raw_args),
           description <- Map.get(args, "description"),
           {:ok, shell_id} <-
             BackgroundShell.start_command(command, cmd_args, session_id, project_root,
               description: description
             ) do
        Shell.emit_shell_telemetry(:bash_background, start_time, command, context, :ok, 0)

        result = %{
          shell_id: shell_id,
          description: description || "Background: #{command} #{Enum.join(cmd_args, " ")}"
        }

        {:ok, Jason.encode!(result)}
      else
        {:error, :no_session_id} ->
          {:error, "bash_background requires a session context"}

        {:error, reason} when is_binary(reason) ->
          Shell.emit_shell_telemetry(:bash_background, start_time, command, context, :error, -1)
          {:error, reason}

        {:error, reason} ->
          Shell.emit_shell_telemetry(:bash_background, start_time, command, context, :error, -1)
          {:error, Shell.format_error(reason, command)}
      end
    end

    def execute(_args, _context) do
      {:error, "bash_background requires a command argument"}
    end

    defp get_session_id(%{session_id: session_id}) when is_binary(session_id), do: {:ok, session_id}
    defp get_session_id(_), do: {:error, :no_session_id}

    defp parse_args(args) when is_list(args), do: Enum.map(args, &to_string/1)
    defp parse_args(_args), do: []
  end

  # ============================================================================
  # BashOutput Handler
  # ============================================================================

  defmodule BashOutput do
    @moduledoc """
    Handler for the bash_output tool.

    Retrieves output from a background shell process started with bash_background.
    Supports blocking (wait for completion) and non-blocking modes.
    """

    alias JidoCode.Tools.BackgroundShell
    alias JidoCode.Tools.Handlers.Shell

    @default_timeout 30_000

    @doc """
    Gets output from a background shell process.

    ## Arguments

    - `"shell_id"` - Shell ID returned by bash_background (required)
    - `"block"` - Wait for completion (optional, default: true)
    - `"timeout"` - Max wait time in ms when blocking (optional, default: 30000)

    ## Returns

    - `{:ok, json}` - JSON with output, status, exit_code
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"shell_id" => shell_id} = args, context) when is_binary(shell_id) do
      start_time = System.monotonic_time(:microsecond)
      block = Map.get(args, "block", true)
      timeout = Map.get(args, "timeout", @default_timeout)

      opts = [block: block, timeout: timeout]

      case BackgroundShell.get_output(shell_id, opts) do
        {:ok, result} ->
          Shell.emit_shell_telemetry(:bash_output, start_time, shell_id, context, :ok, result.exit_code || 0)

          {:ok, Jason.encode!(%{
            output: result.output,
            status: to_string(result.status),
            exit_code: result.exit_code
          })}

        {:error, :not_found} ->
          Shell.emit_shell_telemetry(:bash_output, start_time, shell_id, context, :error, -1)
          {:error, "Shell not found: #{shell_id}"}

        {:error, :timeout} ->
          Shell.emit_shell_telemetry(:bash_output, start_time, shell_id, context, :timeout, -1)
          {:error, "Timeout waiting for shell: #{shell_id}"}

        {:error, reason} ->
          Shell.emit_shell_telemetry(:bash_output, start_time, shell_id, context, :error, -1)
          {:error, "Error getting output: #{inspect(reason)}"}
      end
    end

    def execute(_args, _context) do
      {:error, "bash_output requires a shell_id argument"}
    end
  end

  # ============================================================================
  # KillShell Handler
  # ============================================================================

  defmodule KillShell do
    @moduledoc """
    Handler for the kill_shell tool.

    Terminates a background shell process.
    """

    alias JidoCode.Tools.BackgroundShell
    alias JidoCode.Tools.Handlers.Shell

    @doc """
    Kills a background shell process.

    ## Arguments

    - `"shell_id"` - Shell ID returned by bash_background (required)

    ## Returns

    - `{:ok, json}` - JSON with success status
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"shell_id" => shell_id} = _args, context) when is_binary(shell_id) do
      start_time = System.monotonic_time(:microsecond)

      case BackgroundShell.kill(shell_id) do
        :ok ->
          Shell.emit_shell_telemetry(:kill_shell, start_time, shell_id, context, :ok, 0)
          {:ok, Jason.encode!(%{success: true, message: "Shell terminated: #{shell_id}"})}

        {:error, :not_found} ->
          Shell.emit_shell_telemetry(:kill_shell, start_time, shell_id, context, :error, -1)
          {:error, "Shell not found: #{shell_id}"}

        {:error, :already_finished} ->
          Shell.emit_shell_telemetry(:kill_shell, start_time, shell_id, context, :ok, 0)
          {:ok, Jason.encode!(%{success: true, message: "Shell already finished: #{shell_id}"})}

        {:error, reason} ->
          Shell.emit_shell_telemetry(:kill_shell, start_time, shell_id, context, :error, -1)
          {:error, "Error killing shell: #{inspect(reason)}"}
      end
    end

    def execute(_args, _context) do
      {:error, "kill_shell requires a shell_id argument"}
    end
  end
end
