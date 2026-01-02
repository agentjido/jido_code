defmodule JidoCode.Tools.Handlers.Elixir do
  @moduledoc """
  Handler module for Elixir-specific tools.

  This module contains handlers for Elixir and BEAM runtime operations including
  Mix task execution, ExUnit test running, process inspection, and more.

  ## Session Context

  Handlers use `HandlerHelpers.get_project_root/1` for session-aware working directory:

  1. `session_id` present → Uses `Session.Manager.project_root/1`
  2. `project_root` present → Uses provided project root (legacy)
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Security Considerations

  - **Task allowlist**: Only pre-approved Mix tasks can be executed
  - **Task blocklist**: Dangerous tasks are explicitly blocked
  - **Environment restriction**: prod environment is blocked
  - **Timeout enforcement**: Prevents hanging tasks
  - **Output capture**: stdout/stderr are captured and returned

  ## Usage

  This handler is invoked by the Executor when the LLM calls Elixir tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "mix_task",
        arguments: %{"task" => "test", "args" => ["--trace"]}
      }, context: context)

  ## Context

  The context map should contain:
  - `:session_id` - Session ID for project root lookup (preferred)
  - `:project_root` - Base directory for task execution (legacy)
  """

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Constants
  # ============================================================================

  @allowed_tasks ~w(
    compile test format
    deps.get deps.compile deps.tree deps.unlock
    help credo dialyzer docs hex.info
  )

  # Blocked tasks with security rationale:
  # - release: Creates production releases, could deploy malicious code
  # - archive.install: Installs global archives, modifies system state
  # - escript.build: Creates executables, potential malware vector
  # - local.hex/local.rebar: Modifies global package managers
  # - hex.publish: Publishes packages publicly, irreversible
  # - deps.update: Can introduce supply chain vulnerabilities
  # - do: Allows arbitrary task chaining, bypasses allowlist
  # - ecto.drop/ecto.reset: Destructive database operations
  # - phx.gen.secret: Generates secrets, could expose sensitive data
  @blocked_tasks ~w(
    release archive.install escript.build
    local.hex local.rebar hex.publish
    deps.update do
    ecto.drop ecto.reset
    phx.gen.secret
  )

  # Valid task name pattern: alphanumeric, dots, underscores, hyphens only
  @task_name_pattern ~r/^[a-zA-Z][a-zA-Z0-9._-]*$/

  @allowed_envs ~w(dev test)

  # Shared constants are defined in JidoCode.Tools.Handlers.Elixir.Constants
  # to allow nested modules to access them during compilation

  @doc """
  Returns the shared list of blocked process prefixes.
  """
  @spec blocked_prefixes() :: [String.t()]
  defdelegate blocked_prefixes, to: __MODULE__.Constants

  @doc """
  Returns the shared list of sensitive field names for redaction.
  """
  @spec sensitive_fields() :: [String.t()]
  defdelegate sensitive_fields, to: __MODULE__.Constants

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec get_project_root(map()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc """
  Returns the list of allowed Mix tasks.
  """
  @spec allowed_tasks() :: [String.t()]
  def allowed_tasks, do: @allowed_tasks

  @doc """
  Returns the list of blocked Mix tasks.
  """
  @spec blocked_tasks() :: [String.t()]
  def blocked_tasks, do: @blocked_tasks

  @doc """
  Returns the list of allowed Mix environments.
  """
  @spec allowed_envs() :: [String.t()]
  def allowed_envs, do: @allowed_envs

  @doc """
  Validates a Mix task against the allowlist and blocklist.

  Also validates the task name format to prevent shell metacharacter injection.

  ## Returns

  - `{:ok, task}` - Task is allowed
  - `{:error, :invalid_task_name}` - Task name contains invalid characters
  - `{:error, :task_blocked}` - Task is explicitly blocked
  - `{:error, :task_not_allowed}` - Task is not in allowlist
  """
  @spec validate_task(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_task(task) do
    cond do
      # First validate task name format (defense in depth)
      not Regex.match?(@task_name_pattern, task) ->
        {:error, :invalid_task_name}

      task in @blocked_tasks ->
        {:error, :task_blocked}

      task in @allowed_tasks ->
        {:ok, task}

      true ->
        {:error, :task_not_allowed}
    end
  end

  @doc """
  Validates a Mix environment.

  ## Returns

  - `{:ok, env}` - Environment is allowed
  - `{:error, :env_blocked}` - Environment is not allowed (e.g., prod)
  """
  @spec validate_env(String.t() | nil) :: {:ok, String.t()} | {:error, atom()}
  def validate_env(nil), do: {:ok, "dev"}
  def validate_env(env) when env in @allowed_envs, do: {:ok, env}
  def validate_env(_env), do: {:error, :env_blocked}

  # ============================================================================
  # Telemetry
  # ============================================================================

  @doc false
  @spec emit_elixir_telemetry(atom(), integer(), String.t(), map(), atom(), integer()) :: :ok
  def emit_elixir_telemetry(operation, start_time, task, context, status, exit_code) do
    duration = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      [:jido_code, :elixir, operation],
      %{duration: duration, exit_code: exit_code},
      %{
        task: task,
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  @doc false
  @spec format_error(atom() | String.t() | tuple(), String.t()) :: String.t()
  def format_error(:task_not_allowed, task), do: "Mix task not allowed: #{task}"
  def format_error(:task_blocked, task), do: "Mix task is blocked: #{task}"
  def format_error(:invalid_task_name, task), do: "Invalid task name format: #{task}"
  def format_error(:env_blocked, _task), do: "Environment 'prod' is blocked for safety"
  def format_error(:timeout, task), do: "Mix task timed out: #{task}"
  def format_error(:enoent, _task), do: "Mix command not found"
  def format_error(:path_traversal_blocked, _task), do: "Path traversal not allowed in arguments"
  def format_error({:path_traversal_blocked, arg}, _task), do: "Path traversal not allowed in argument: #{arg}"
  def format_error(reason, task) when is_atom(reason), do: "Error (#{reason}): mix #{task}"
  def format_error(reason, _task) when is_binary(reason), do: reason
  def format_error(reason, task), do: "Error (#{inspect(reason)}): mix #{task}"

  # ============================================================================
  # MixTask Handler
  # ============================================================================

  defmodule MixTask do
    @moduledoc """
    Handler for the mix_task tool.

    Executes Mix tasks in the project directory with security validation,
    timeout enforcement, and output capture.

    Uses session-aware project root via `HandlerHelpers.get_project_root/1`.

    ## Security Features

    - Task allowlist/blocklist validation
    - Task name format validation (prevents shell metacharacters)
    - Path traversal detection in arguments
    - Environment restriction (prod blocked)
    - Timeout enforcement (default 60s, max 5min)
    - Output truncation (max 1MB)
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler

    @default_timeout 60_000
    @max_timeout 300_000
    @max_output_size 1_048_576

    @doc """
    Executes a Mix task.

    ## Arguments

    - `"task"` - Mix task to execute (must be in allowlist)
    - `"args"` - Task arguments (optional, default: [])
    - `"env"` - Mix environment (optional, default: "dev")

    ## Context

    - `:session_id` - Session ID for project root lookup (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON with output and exit_code
    - `{:error, reason}` - Error message

    ## Security

    - Task must be in the allowed tasks list
    - Blocked tasks (release, hex.publish, etc.) are rejected
    - prod environment is blocked
    - Output is truncated at 1MB
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"task" => task} = args, context) when is_binary(task) do
      start_time = System.monotonic_time(:microsecond)
      task_args = Map.get(args, "args", [])

      # Validate args early (before get_project_root) to surface validation errors first
      with :ok <- validate_args(task_args),
           :ok <- validate_args_security(task_args),
           {:ok, task} <- ElixirHandler.validate_task(task),
           {:ok, env} <- ElixirHandler.validate_env(Map.get(args, "env")),
           {:ok, project_root} <- ElixirHandler.get_project_root(context) do
        timeout = get_timeout(args)

        run_mix_command(task, task_args, env, project_root, timeout, context, start_time)
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:mix_task, start_time, task, context, :error, 1)
          {:error, ElixirHandler.format_error(reason, task)}
      end
    end

    def execute(%{"task" => task}, _context) do
      {:error, "Invalid task: expected string, got #{inspect(task)}"}
    end

    def execute(_args, _context) do
      {:error, "Missing required parameter: task"}
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp get_timeout(args) do
      case Map.get(args, "timeout") do
        nil -> @default_timeout
        timeout when is_integer(timeout) and timeout > 0 -> min(timeout, @max_timeout)
        _ -> @default_timeout
      end
    end

    defp validate_args(args) when is_list(args) do
      if Enum.all?(args, &is_binary/1) do
        :ok
      else
        {:error, "All task arguments must be strings"}
      end
    end

    defp validate_args(_), do: {:error, "Arguments must be a list"}

    # Security validation for path traversal in arguments
    defp validate_args_security(args) do
      Enum.reduce_while(args, :ok, fn arg, _acc ->
        if contains_path_traversal?(arg) do
          {:halt, {:error, {:path_traversal_blocked, arg}}}
        else
          {:cont, :ok}
        end
      end)
    end

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

    defp run_mix_command(task, task_args, env, project_root, timeout, context, start_time) do
      cmd_args = [task | task_args]

      opts = [
        cd: project_root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", env}]
      ]

      try do
        task_ref =
          Task.async(fn ->
            System.cmd("mix", cmd_args, opts)
          end)

        case Task.yield(task_ref, timeout) || Task.shutdown(task_ref, :brutal_kill) do
          {:ok, {output, exit_code}} ->
            truncated_output = truncate_output(output)
            ElixirHandler.emit_elixir_telemetry(:mix_task, start_time, task, context, :ok, exit_code)

            result = %{
              "output" => truncated_output,
              "exit_code" => exit_code
            }

            # Use Jason.encode/1 instead of encode!/1 for consistent error handling
            case Jason.encode(result) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
            end

          nil ->
            ElixirHandler.emit_elixir_telemetry(:mix_task, start_time, task, context, :timeout, 1)
            {:error, ElixirHandler.format_error(:timeout, task)}
        end
      rescue
        e ->
          ElixirHandler.emit_elixir_telemetry(:mix_task, start_time, task, context, :error, 1)
          {:error, "Mix task error: #{Exception.message(e)}"}
      end
    end

    defp truncate_output(output) when byte_size(output) > @max_output_size do
      truncated = binary_part(output, 0, @max_output_size)
      truncated <> "\n... [output truncated at 1MB]"
    end

    defp truncate_output(output), do: output
  end

  # ============================================================================
  # RunExunit Handler
  # ============================================================================

  defmodule RunExunit do
    @moduledoc """
    Handler for the run_exunit tool.

    Runs ExUnit tests with comprehensive filtering and configuration options.
    Provides granular control over test execution including file/line targeting,
    tag filtering, and failure limits.

    Uses session-aware project root via `HandlerHelpers.get_project_root/1`.

    ## Security Features

    - Path validation within project boundary (uses HandlerHelpers.validate_path/2)
    - Path must be within test/ directory (or nil for all tests)
    - Path traversal detection in test paths
    - Environment restriction (always uses test env)
    - Timeout enforcement (default 120s, max 5min)
    - Output truncation (max 1MB)

    ## Output Parsing

    Parses ExUnit output for:
    - Test summary (tests, failures, excluded)
    - Failure details with file/line locations
    - Timing information
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler
    alias JidoCode.Tools.HandlerHelpers

    @default_timeout 120_000
    @max_timeout 300_000
    @max_output_size 1_048_576

    @doc """
    Executes ExUnit tests with filtering options.

    ## Arguments

    - `"path"` - Test file or directory (optional)
    - `"line"` - Line number for targeted test (optional, requires path)
    - `"tag"` - Run only tests with tag (optional)
    - `"exclude_tag"` - Exclude tests with tag (optional)
    - `"max_failures"` - Stop after N failures (optional)
    - `"seed"` - Random seed for ordering (optional)
    - `"timeout"` - Timeout in milliseconds (optional)

    ## Context

    - `:session_id` - Session ID for project root lookup (preferred)
    - `:project_root` - Direct project root path (legacy)

    ## Returns

    - `{:ok, json}` - JSON with output, exit_code, and test summary
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(args, context) do
      start_time = System.monotonic_time(:microsecond)
      path = Map.get(args, "path")
      trace = Map.get(args, "trace", false)

      with :ok <- validate_path_security(path),
           {:ok, project_root} <- ElixirHandler.get_project_root(context),
           :ok <- validate_path_in_project(path, context),
           :ok <- validate_path_in_test_dir(path, project_root) do
        timeout = get_timeout(args)
        cmd_args = build_test_args(args, trace)

        run_test_command(cmd_args, project_root, timeout, context, start_time)
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:run_exunit, start_time, "test", context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp get_timeout(args) do
      case Map.get(args, "timeout") do
        nil -> @default_timeout
        timeout when is_integer(timeout) and timeout > 0 -> min(timeout, @max_timeout)
        _ -> @default_timeout
      end
    end

    # Security validation for path traversal patterns
    defp validate_path_security(nil), do: :ok

    defp validate_path_security(path) when is_binary(path) do
      if contains_path_traversal?(path) do
        {:error, {:path_traversal_blocked, path}}
      else
        :ok
      end
    end

    defp validate_path_security(_), do: {:error, :invalid_path}

    # Validate path is within project boundary using HandlerHelpers
    defp validate_path_in_project(nil, _context), do: :ok

    defp validate_path_in_project(path, context) when is_binary(path) do
      case HandlerHelpers.validate_path(path, context) do
        {:ok, _resolved_path} -> :ok
        {:error, :path_escapes_boundary} -> {:error, :path_escapes_boundary}
        {:error, reason} -> {:error, reason}
      end
    end

    # Validate path is within test/ directory
    defp validate_path_in_test_dir(nil, _project_root), do: :ok

    defp validate_path_in_test_dir(path, project_root) when is_binary(path) do
      # Normalize the path
      normalized = Path.expand(path, project_root)
      test_dir = Path.join(project_root, "test")

      if String.starts_with?(normalized, test_dir <> "/") or normalized == test_dir do
        :ok
      else
        {:error, :path_not_in_test_dir}
      end
    end

    defp contains_path_traversal?(path) do
      lower = String.downcase(path)

      String.contains?(path, "../") or
        String.contains?(lower, "%2e%2e%2f") or
        String.contains?(lower, "%2e%2e/") or
        String.contains?(lower, "..%2f") or
        String.contains?(lower, "%2e%2e%5c") or
        String.contains?(lower, "..%5c")
    end

    defp build_test_args(args, trace) do
      base_args = ["test"]

      base_args
      |> add_trace_arg(trace)
      |> add_path_arg(args)
      |> add_line_arg(args)
      |> add_tag_arg(args)
      |> add_exclude_tag_arg(args)
      |> add_max_failures_arg(args)
      |> add_seed_arg(args)
    end

    defp add_trace_arg(cmd_args, true), do: cmd_args ++ ["--trace"]
    defp add_trace_arg(cmd_args, _), do: cmd_args

    defp add_path_arg(cmd_args, %{"path" => path}) when is_binary(path) and path != "" do
      cmd_args ++ [path]
    end

    defp add_path_arg(cmd_args, _), do: cmd_args

    defp add_line_arg(cmd_args, %{"line" => line, "path" => path})
         when is_integer(line) and is_binary(path) and path != "" do
      # Replace path with path:line format
      List.update_at(cmd_args, -1, fn p -> "#{p}:#{line}" end)
    end

    defp add_line_arg(cmd_args, _), do: cmd_args

    defp add_tag_arg(cmd_args, %{"tag" => tag}) when is_binary(tag) and tag != "" do
      cmd_args ++ ["--only", tag]
    end

    defp add_tag_arg(cmd_args, _), do: cmd_args

    defp add_exclude_tag_arg(cmd_args, %{"exclude_tag" => tag}) when is_binary(tag) and tag != "" do
      cmd_args ++ ["--exclude", tag]
    end

    defp add_exclude_tag_arg(cmd_args, _), do: cmd_args

    defp add_max_failures_arg(cmd_args, %{"max_failures" => n}) when is_integer(n) and n > 0 do
      cmd_args ++ ["--max-failures", Integer.to_string(n)]
    end

    defp add_max_failures_arg(cmd_args, _), do: cmd_args

    defp add_seed_arg(cmd_args, %{"seed" => seed}) when is_integer(seed) do
      cmd_args ++ ["--seed", Integer.to_string(seed)]
    end

    defp add_seed_arg(cmd_args, _), do: cmd_args

    defp run_test_command(cmd_args, project_root, timeout, context, start_time) do
      opts = [
        cd: project_root,
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      ]

      try do
        task_ref =
          Task.async(fn ->
            System.cmd("mix", cmd_args, opts)
          end)

        case Task.yield(task_ref, timeout) || Task.shutdown(task_ref, :brutal_kill) do
          {:ok, {output, exit_code}} ->
            truncated_output = truncate_output(output)
            ElixirHandler.emit_elixir_telemetry(:run_exunit, start_time, "test", context, :ok, exit_code)

            result = %{
              "output" => truncated_output,
              "exit_code" => exit_code,
              "summary" => parse_test_summary(output),
              "failures" => parse_test_failures(output),
              "timing" => parse_timing(output)
            }

            case Jason.encode(result) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
            end

          nil ->
            ElixirHandler.emit_elixir_telemetry(:run_exunit, start_time, "test", context, :timeout, 1)
            {:error, format_error(:timeout)}
        end
      rescue
        e ->
          ElixirHandler.emit_elixir_telemetry(:run_exunit, start_time, "test", context, :error, 1)
          {:error, "Test execution error: #{Exception.message(e)}"}
      end
    end

    defp truncate_output(output) when byte_size(output) > @max_output_size do
      truncated = binary_part(output, 0, @max_output_size)
      truncated <> "\n... [output truncated at 1MB]"
    end

    defp truncate_output(output), do: output

    # Parse ExUnit summary from output (e.g., "10 tests, 0 failures")
    defp parse_test_summary(output) do
      case Regex.run(~r/(\d+) tests?, (\d+) failures?(?:, (\d+) excluded)?/, output) do
        [_, tests, failures] ->
          %{"tests" => String.to_integer(tests), "failures" => String.to_integer(failures)}

        [_, tests, failures, excluded] ->
          %{
            "tests" => String.to_integer(tests),
            "failures" => String.to_integer(failures),
            "excluded" => String.to_integer(excluded)
          }

        _ ->
          nil
      end
    end

    # Parse test failures with file/line information
    # ExUnit failure format:
    #   1) test name (ModuleName)
    #      test/path/to/test.exs:42
    #      ** (error) ...
    defp parse_test_failures(output) do
      # Pattern to match failure blocks
      failure_pattern = ~r/\n\s+(\d+)\)\s+test\s+(.+?)\s+\(([^)]+)\)\n\s+(\S+\.exs?:\d+)/

      Regex.scan(failure_pattern, output)
      |> Enum.map(fn [_, _num, test_name, module, location] ->
        [file, line] = String.split(location, ":")

        %{
          "test" => String.trim(test_name),
          "module" => module,
          "file" => file,
          "line" => String.to_integer(line)
        }
      end)
    end

    # Parse timing information from ExUnit output
    # Format: "Finished in 1.2 seconds (0.5s async, 0.7s sync)"
    defp parse_timing(output) do
      case Regex.run(~r/Finished in ([\d.]+) seconds?(?:\s+\(([\d.]+)s async, ([\d.]+)s sync\))?/, output) do
        [_, total] ->
          %{"total_seconds" => parse_float(total)}

        [_, total, async, sync] ->
          %{
            "total_seconds" => parse_float(total),
            "async_seconds" => parse_float(async),
            "sync_seconds" => parse_float(sync)
          }

        _ ->
          nil
      end
    end

    defp parse_float(str) do
      case Float.parse(str) do
        {float, _} -> float
        :error -> 0.0
      end
    end

    defp format_error(:timeout), do: "Test execution timed out"
    defp format_error(:invalid_path), do: "Invalid path: expected string"
    defp format_error(:path_not_in_test_dir), do: "Path must be within the test/ directory"
    defp format_error(:path_escapes_boundary), do: "Path escapes project boundary"
    defp format_error({:path_traversal_blocked, path}), do: "Path traversal not allowed: #{path}"
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: "Error: #{inspect(reason)}"
  end

  # ============================================================================
  # ProcessState Handler
  # ============================================================================

  defmodule ProcessState do
    @moduledoc """
    Handler for the get_process_state tool.

    Inspects the state of GenServer and other OTP processes with security controls.
    Only project processes can be inspected - system and internal processes are blocked.

    ## Security Features

    - Only registered names allowed (raw PIDs blocked)
    - System-critical processes blocked (kernel, stdlib, init)
    - JidoCode internal processes blocked
    - Sensitive fields redacted (passwords, tokens, keys)
    - Timeout enforcement (default 5s)

    ## Output

    Returns JSON with:
    - `state` - Process state formatted with inspect
    - `process_info` - Basic process information
    - `type` - Process type (genserver, agent, gen_statem, other)
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler
    alias JidoCode.Tools.Handlers.Elixir.Constants
    alias JidoCode.Tools.HandlerHelpers

    @default_timeout 5_000
    @max_timeout 30_000

    # Use shared blocked prefixes from Constants module
    @blocked_prefixes Constants.blocked_prefixes()

    # Use shared sensitive fields from Constants module
    @sensitive_fields Constants.sensitive_fields()

    @doc """
    Inspects the state of a process.

    ## Arguments

    - `"process"` - Registered name of the process (required)
    - `"timeout"` - Timeout in milliseconds (optional, default: 5000)

    ## Returns

    - `{:ok, json}` - JSON with state and process_info
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"process" => process_name} = args, context) when is_binary(process_name) do
      start_time = System.monotonic_time(:microsecond)
      timeout = HandlerHelpers.get_timeout(args, @default_timeout, @max_timeout)

      with :ok <- validate_process_name(process_name),
           :ok <- validate_not_blocked(process_name),
           {:ok, pid} <- lookup_process(process_name) do
        get_and_format_state(pid, process_name, timeout, context, start_time)
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:process_state, start_time, process_name, context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    def execute(%{"process" => process_name}, _context) do
      {:error, "Invalid process name: expected string, got #{inspect(process_name)}"}
    end

    def execute(_args, _context) do
      {:error, "Missing required parameter: process"}
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    # Validate process name format - only allow registered names, not raw PIDs
    defp validate_process_name(name) do
      cond do
        # Block raw PID strings like "#PID<0.123.0>" or "<0.123.0>"
        String.contains?(name, "<") and String.contains?(name, ".") ->
          {:error, :raw_pid_not_allowed}

        # Block empty or whitespace-only names
        String.trim(name) == "" ->
          {:error, :invalid_process_name}

        # Valid registered name
        true ->
          :ok
      end
    end

    # Check if process is in blocked list
    defp validate_not_blocked(name) do
      if Enum.any?(@blocked_prefixes, &String.starts_with?(name, &1)) do
        {:error, :process_blocked}
      else
        :ok
      end
    end

    # Look up process by registered name
    defp lookup_process(name) do
      # Try to convert to atom (for registered names)
      atom_name = try_to_atom(name)

      case atom_name do
        nil ->
          {:error, :process_not_found}

        atom when is_atom(atom) ->
          case GenServer.whereis(atom) do
            nil -> {:error, :process_not_found}
            pid when is_pid(pid) -> {:ok, pid}
          end
      end
    end

    defp try_to_atom(name) do
      # First try as an existing atom
      try do
        String.to_existing_atom(name)
      rescue
        ArgumentError ->
          # Try with Elixir. prefix for module names
          try do
            String.to_existing_atom("Elixir." <> name)
          rescue
            ArgumentError -> nil
          end
      end
    end

    defp get_and_format_state(pid, process_name, timeout, context, start_time) do
      process_info = get_process_info(pid)
      process_type = detect_process_type(pid)

      state_result =
        try do
          case :sys.get_state(pid, timeout) do
            state -> {:ok, state}
          end
        catch
          :exit, {:timeout, _} -> {:error, :timeout}
          :exit, {:noproc, _} -> {:error, :process_dead}
          :exit, reason -> {:error, {:sys_error, reason}}
        end

      case state_result do
        {:ok, state} ->
          formatted_state = format_state(state)
          sanitized_state = sanitize_output(formatted_state)

          result = %{
            "state" => sanitized_state,
            "process_info" => process_info,
            "type" => process_type
          }

          ElixirHandler.emit_elixir_telemetry(:process_state, start_time, process_name, context, :ok, 0)

          case Jason.encode(result) do
            {:ok, json} -> {:ok, json}
            {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
          end

        {:error, :timeout} ->
          # For timeout, still return process_info
          result = %{
            "state" => nil,
            "process_info" => process_info,
            "type" => process_type,
            "error" => "Timeout getting state"
          }

          ElixirHandler.emit_elixir_telemetry(:process_state, start_time, process_name, context, :timeout, 1)

          case Jason.encode(result) do
            {:ok, json} -> {:ok, json}
            {:error, _} -> {:error, "Timeout getting process state"}
          end

        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:process_state, start_time, process_name, context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    defp get_process_info(pid) do
      info = Process.info(pid, [:registered_name, :status, :message_queue_len, :memory, :reductions])

      case info do
        nil ->
          %{"status" => "dead"}

        info_list ->
          %{
            "registered_name" => format_registered_name(info_list[:registered_name]),
            "status" => to_string(info_list[:status]),
            "message_queue_len" => info_list[:message_queue_len],
            "memory" => info_list[:memory],
            "reductions" => info_list[:reductions]
          }
      end
    end

    defp format_registered_name([]), do: nil
    defp format_registered_name(name) when is_atom(name), do: to_string(name)
    defp format_registered_name(_), do: nil

    defp detect_process_type(pid) do
      # Try to detect OTP behavior type
      try do
        case :sys.get_status(pid, 100) do
          {:status, _, {:module, module}, _} ->
            cond do
              function_exported?(module, :handle_call, 3) -> "genserver"
              function_exported?(module, :handle_event, 4) -> "gen_statem"
              true -> "otp_process"
            end

          _ ->
            "other"
        end
      catch
        :exit, _ -> "other"
      end
    end

    defp format_state(state) do
      inspect(state, pretty: true, limit: 50, printable_limit: 4096)
    end

    # Sanitize output to redact sensitive fields
    # Handles multiple formats: quoted strings, atoms, unquoted values, charlists, binaries
    defp sanitize_output(output) when is_binary(output) do
      Enum.reduce(@sensitive_fields, output, fn field, acc ->
        # Comprehensive patterns for different Elixir inspect output formats
        patterns = [
          # Double-quoted strings: password => "secret" or password: "secret"
          {~r/(#{field})\s*[=:>]+\s*"[^"]*"/i, "\\1 => \"[REDACTED]\""},
          # Single-quoted strings (charlists): password => 'secret'
          {~r/(#{field})\s*[=:>]+\s*'[^']*'/i, "\\1 => '[REDACTED]'"},
          # Atom prefix format: :password => "secret"
          {~r/(:\s*#{field})\s*[=:>]+\s*"[^"]*"/i, "\\1 => \"[REDACTED]\""},
          # Atom values: password => :secret_value
          {~r/(#{field})\s*[=:>]+\s*:[a-zA-Z_][a-zA-Z0-9_]*/i, "\\1 => :[REDACTED]"},
          # Integer values: password => 12345
          {~r/(#{field})\s*[=:>]+\s*\d+/i, "\\1 => [REDACTED]"},
          # Charlist syntax: password => ~c"secret"
          {~r/(#{field})\s*[=:>]+\s*~c"[^"]*"/i, "\\1 => ~c\"[REDACTED]\""},
          # Binary syntax: password => <<"secret">>
          {~r/(#{field})\s*[=:>]+\s*<<[^>]*>>/i, "\\1 => <<[REDACTED]>>"},
          # Unquoted barewords (identifiers): password => secret_value
          {~r/(#{field})\s*[=:>]+\s*([a-zA-Z_][a-zA-Z0-9_]*)\b(?!\s*[=:>\(\[])/i, "\\1 => [REDACTED]"}
        ]

        Enum.reduce(patterns, acc, fn {pattern, replacement}, inner_acc ->
          Regex.replace(pattern, inner_acc, replacement)
        end)
      end)
    end

    defp format_error(:raw_pid_not_allowed), do: "Raw PIDs are not allowed. Use registered process names."
    defp format_error(:invalid_process_name), do: "Invalid process name"
    defp format_error(:process_blocked), do: "Access to this process is blocked for security"
    defp format_error(:process_not_found), do: "Process not found or not registered"
    defp format_error(:process_dead), do: "Process is no longer running"
    defp format_error(:timeout), do: "Timeout getting process state"
    defp format_error({:sys_error, reason}), do: "Error getting state: #{inspect(reason)}"
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: "Error: #{inspect(reason)}"
  end

  # ============================================================================
  # SupervisorTree Handler
  # ============================================================================

  defmodule SupervisorTree do
    @moduledoc """
    Handler for the inspect_supervisor tool.

    Inspects supervisor tree structure with security controls.
    Only project supervisors can be inspected - system supervisors are blocked.

    ## Security Features

    - Only registered names allowed (raw PIDs blocked)
    - System supervisors blocked (kernel, stdlib, init)
    - JidoCode internal supervisors blocked
    - Depth limited to prevent excessive recursion

    ## Output

    Returns JSON with:
    - `tree` - Formatted tree structure as string
    - `children` - List of child specs with details
    - `supervisor_info` - Supervisor metadata
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler
    alias JidoCode.Tools.Handlers.Elixir.Constants
    alias JidoCode.Tools.HandlerHelpers

    @default_depth 2
    @max_depth 5
    @max_children_per_level 50

    # Use shared blocked prefixes from Constants module
    @blocked_prefixes Constants.blocked_prefixes()

    @doc """
    Inspects the structure of a supervisor tree.

    ## Arguments

    - `"supervisor"` - Registered name of the supervisor (required)
    - `"depth"` - Maximum depth to traverse (optional, default: 2, max: 5)

    ## Returns

    - `{:ok, json}` - JSON with tree structure and children list
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"supervisor" => supervisor_name} = args, context) when is_binary(supervisor_name) do
      start_time = System.monotonic_time(:microsecond)
      depth = get_depth(args)

      with :ok <- validate_supervisor_name(supervisor_name),
           :ok <- validate_not_blocked(supervisor_name),
           {:ok, pid} <- lookup_supervisor(supervisor_name) do
        inspect_and_format_tree(pid, supervisor_name, depth, context, start_time)
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:supervisor_tree, start_time, supervisor_name, context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    def execute(%{"supervisor" => supervisor_name}, _context) do
      {:error, "Invalid supervisor name: expected string, got #{inspect(supervisor_name)}"}
    end

    def execute(_args, _context) do
      {:error, "Missing required parameter: supervisor"}
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    defp get_depth(args) do
      case Map.get(args, "depth") do
        nil -> @default_depth
        depth when is_integer(depth) and depth > 0 -> min(depth, @max_depth)
        _ -> @default_depth
      end
    end

    # Validate supervisor name format - only allow registered names, not raw PIDs
    defp validate_supervisor_name(name) do
      cond do
        # Block raw PID strings like "#PID<0.123.0>" or "<0.123.0>"
        String.contains?(name, "<") and String.contains?(name, ".") ->
          {:error, :raw_pid_not_allowed}

        # Block empty or whitespace-only names
        String.trim(name) == "" ->
          {:error, :invalid_supervisor_name}

        # Valid registered name
        true ->
          :ok
      end
    end

    # Check if supervisor is in blocked list
    defp validate_not_blocked(name) do
      if Enum.any?(@blocked_prefixes, &String.starts_with?(name, &1)) do
        {:error, :supervisor_blocked}
      else
        :ok
      end
    end

    # Look up supervisor by registered name
    defp lookup_supervisor(name) do
      atom_name = try_to_atom(name)

      case atom_name do
        nil ->
          {:error, :supervisor_not_found}

        atom when is_atom(atom) ->
          case GenServer.whereis(atom) do
            nil -> {:error, :supervisor_not_found}
            pid when is_pid(pid) -> {:ok, pid}
          end
      end
    end

    defp try_to_atom(name) do
      try do
        String.to_existing_atom(name)
      rescue
        ArgumentError ->
          try do
            String.to_existing_atom("Elixir." <> name)
          rescue
            ArgumentError -> nil
          end
      end
    end

    defp inspect_and_format_tree(pid, supervisor_name, depth, context, start_time) do
      supervisor_info = get_supervisor_info(pid, supervisor_name)

      children_result =
        try do
          children = Supervisor.which_children(pid)
          {:ok, children}
        catch
          :exit, {:noproc, _} -> {:error, :supervisor_dead}
          :exit, reason -> {:error, {:supervisor_error, reason}}
        end

      case children_result do
        {:ok, children} ->
          # Limit children count
          limited_children = Enum.take(children, @max_children_per_level)
          truncated = length(children) > @max_children_per_level

          # Build tree structure
          tree_data = build_tree(limited_children, depth - 1)
          tree_string = format_tree_string(supervisor_name, tree_data, truncated)

          result = %{
            "tree" => tree_string,
            "children" => format_children_list(tree_data),
            "supervisor_info" => supervisor_info,
            "children_count" => length(children),
            "truncated" => truncated
          }

          ElixirHandler.emit_elixir_telemetry(:supervisor_tree, start_time, supervisor_name, context, :ok, 0)

          case Jason.encode(result) do
            {:ok, json} -> {:ok, json}
            {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
          end

        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:supervisor_tree, start_time, supervisor_name, context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    defp get_supervisor_info(pid, name) do
      info = Process.info(pid, [:status, :message_queue_len, :memory, :reductions])

      case info do
        nil ->
          %{"status" => "dead", "name" => name}

        info_list ->
          %{
            "name" => name,
            "status" => to_string(info_list[:status]),
            "message_queue_len" => info_list[:message_queue_len],
            "memory" => info_list[:memory],
            "reductions" => info_list[:reductions]
          }
      end
    end

    defp build_tree(children, remaining_depth) do
      Enum.map(children, fn {id, child_pid, type, modules} ->
        child_info = %{
          id: format_id(id),
          type: to_string(type),
          modules: format_modules(modules),
          pid: format_pid(child_pid),
          status: get_child_status(child_pid)
        }

        # Recursively inspect supervisor children if depth allows
        if remaining_depth > 0 and type == :supervisor and is_pid(child_pid) do
          sub_children = get_safe_children(child_pid)
          limited_sub = Enum.take(sub_children, @max_children_per_level)
          sub_tree = build_tree(limited_sub, remaining_depth - 1)
          Map.put(child_info, :children, sub_tree)
        else
          child_info
        end
      end)
    end

    defp get_safe_children(pid) do
      try do
        Supervisor.which_children(pid)
      catch
        :exit, _ -> []
      end
    end

    defp format_id(id) when is_atom(id), do: to_string(id)
    defp format_id(id), do: inspect(id)

    defp format_modules(:dynamic), do: ["dynamic"]
    defp format_modules(modules) when is_list(modules), do: Enum.map(modules, &to_string/1)
    defp format_modules(_), do: []

    defp format_pid(pid) when is_pid(pid), do: inspect(pid)
    defp format_pid(:undefined), do: "undefined"
    defp format_pid(:restarting), do: "restarting"
    defp format_pid(other), do: inspect(other)

    defp get_child_status(pid) when is_pid(pid) do
      if Process.alive?(pid), do: "running", else: "dead"
    end

    defp get_child_status(:undefined), do: "not_started"
    defp get_child_status(:restarting), do: "restarting"
    defp get_child_status(_), do: "unknown"

    defp format_tree_string(root_name, children, truncated) do
      lines = [root_name | format_tree_lines(children, "")]
      tree = Enum.join(lines, "\n")

      if truncated do
        tree <> "\n... (children truncated at #{@max_children_per_level})"
      else
        tree
      end
    end

    defp format_tree_lines([], _prefix), do: []

    defp format_tree_lines(children, prefix) do
      children
      |> Enum.with_index()
      |> Enum.flat_map(fn {child, index} ->
        is_last = index == length(children) - 1
        connector = if is_last, do: "└── ", else: "├── "
        child_prefix = if is_last, do: "    ", else: "│   "

        type_indicator = if child.type == "supervisor", do: "[S]", else: "[W]"
        status_indicator = status_symbol(child.status)
        child_line = "#{prefix}#{connector}#{type_indicator} #{child.id} #{status_indicator}"

        sub_lines =
          case Map.get(child, :children) do
            nil -> []
            sub_children -> format_tree_lines(sub_children, prefix <> child_prefix)
          end

        [child_line | sub_lines]
      end)
    end

    defp status_symbol("running"), do: "●"
    defp status_symbol("dead"), do: "○"
    defp status_symbol("restarting"), do: "↻"
    defp status_symbol("not_started"), do: "◌"
    defp status_symbol(_), do: "?"

    defp format_children_list(tree_data) do
      Enum.map(tree_data, fn child ->
        base = %{
          "id" => child.id,
          "type" => child.type,
          "modules" => child.modules,
          "pid" => child.pid,
          "status" => child.status
        }

        case Map.get(child, :children) do
          nil -> base
          sub_children -> Map.put(base, "children", format_children_list(sub_children))
        end
      end)
    end

    defp format_error(:raw_pid_not_allowed), do: "Raw PIDs are not allowed. Use registered supervisor names."
    defp format_error(:invalid_supervisor_name), do: "Invalid supervisor name"
    defp format_error(:supervisor_blocked), do: "Access to this supervisor is blocked for security"
    defp format_error(:supervisor_not_found), do: "Supervisor not found or not registered"
    defp format_error(:supervisor_dead), do: "Supervisor is no longer running"
    defp format_error({:supervisor_error, reason}), do: "Error inspecting supervisor: #{inspect(reason)}"
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: "Error: #{inspect(reason)}"
  end

  # ============================================================================
  # EtsInspect Handler
  # ============================================================================

  defmodule EtsInspect do
    @moduledoc """
    Handler for the ets_inspect tool.

    Inspects ETS tables with multiple operations: list available tables,
    get table info, lookup by key, or sample entries. Only project-owned
    tables can be inspected - system tables are blocked.

    ## Security Features

    - System ETS tables are blocked (code, ac_tab, file_io_servers, etc.)
    - Only project-owned tables can be inspected (owner not in blocked list)
    - Protected/private tables block lookup/sample from non-owner processes
    - Output limited to prevent memory issues

    ## Operations

    - `list` - Get all project-owned tables with basic info
    - `info` - Get detailed table information
    - `lookup` - Lookup entries by key
    - `sample` - Get first N entries from table
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler
    alias JidoCode.Tools.Handlers.Elixir.Constants
    alias JidoCode.Tools.HandlerHelpers

    @default_limit 10
    @max_limit 100
    @max_entry_size 10_000

    # System ETS tables that should never be inspected
    @blocked_tables [
      :code,
      :code_names,
      :ac_tab,
      :file_io_servers,
      :shell_records,
      :global_names,
      :global_names_ext,
      :global_locks,
      :global_pid_names,
      :global_pid_ids,
      :inet_db,
      :inet_hosts_byname,
      :inet_hosts_byaddr,
      :inet_hosts_file_byname,
      :inet_hosts_file_byaddr,
      :inet_cache,
      :ssl_otp_session_cache,
      :ssl_otp_pem_cache,
      :ets_coverage_data,
      :cover_internal_data_table,
      :cover_internal_clause_table,
      :cover_binary_code_table
    ]

    # Use shared blocked prefixes from Constants module
    @blocked_owner_prefixes Constants.blocked_prefixes()

    # Use shared sensitive fields from Constants module for redaction
    @sensitive_fields Constants.sensitive_fields()

    @doc """
    Inspects ETS tables with various operations.

    ## Arguments

    - `"operation"` - Operation to perform: "list", "info", "lookup", "sample" (required)
    - `"table"` - Table name to inspect (required for info/lookup/sample)
    - `"key"` - Key for lookup operation (as string)
    - `"limit"` - Max entries for sample (default: 10, max: 100)

    ## Returns

    - `{:ok, json}` - JSON with operation results
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"operation" => operation} = args, context) when is_binary(operation) do
      start_time = System.monotonic_time(:microsecond)

      result =
        case operation do
          "list" -> execute_list(context, start_time)
          "info" -> execute_info(args, context, start_time)
          "lookup" -> execute_lookup(args, context, start_time)
          "sample" -> execute_sample(args, context, start_time)
          _ -> {:error, "Invalid operation: #{operation}. Must be one of: list, info, lookup, sample"}
        end

      result
    end

    def execute(%{"operation" => operation}, _context) do
      {:error, "Invalid operation: expected string, got #{inspect(operation)}"}
    end

    def execute(_args, _context) do
      {:error, "Missing required parameter: operation"}
    end

    # ============================================================================
    # List Operation
    # ============================================================================

    defp execute_list(context, start_time) do
      tables = :ets.all()

      project_tables =
        tables
        |> Enum.filter(&is_project_table?/1)
        |> Enum.map(&get_table_summary/1)
        |> Enum.reject(&is_nil/1)

      result = %{
        "operation" => "list",
        "tables" => project_tables,
        "count" => length(project_tables)
      }

      ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "list", context, :ok, 0)

      case Jason.encode(result) do
        {:ok, json} -> {:ok, json}
        {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
      end
    end

    # ============================================================================
    # Info Operation
    # ============================================================================

    defp execute_info(%{"table" => table_name} = _args, context, start_time) when is_binary(table_name) do
      with {:ok, table_ref} <- parse_table_name(table_name),
           :ok <- validate_table_accessible(table_ref) do
        case :ets.info(table_ref) do
          :undefined ->
            ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "info", context, :error, 1)
            {:error, "Table not found: #{table_name}"}

          info_list ->
            info_map = format_table_info(info_list)

            result = %{
              "operation" => "info",
              "table" => table_name,
              "info" => info_map
            }

            ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "info", context, :ok, 0)

            case Jason.encode(result) do
              {:ok, json} -> {:ok, json}
              {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
            end
        end
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "info", context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    defp execute_info(_args, context, start_time) do
      ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "info", context, :error, 1)
      {:error, "Missing required parameter: table (for info operation)"}
    end

    # ============================================================================
    # Lookup Operation
    # ============================================================================

    defp execute_lookup(%{"table" => table_name, "key" => key_string} = _args, context, start_time)
         when is_binary(table_name) and is_binary(key_string) do
      with {:ok, table_ref} <- parse_table_name(table_name),
           :ok <- validate_table_accessible(table_ref),
           :ok <- validate_table_readable(table_ref),
           {:ok, key} <- parse_key(key_string) do
        entries =
          try do
            :ets.lookup(table_ref, key)
          rescue
            ArgumentError -> []
          end

        formatted_entries = Enum.map(entries, &format_entry/1)

        result = %{
          "operation" => "lookup",
          "table" => table_name,
          "key" => key_string,
          "entries" => formatted_entries,
          "count" => length(formatted_entries)
        }

        ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "lookup", context, :ok, 0)

        case Jason.encode(result) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
        end
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "lookup", context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    defp execute_lookup(%{"table" => _table_name}, context, start_time) do
      ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "lookup", context, :error, 1)
      {:error, "Missing required parameter: key (for lookup operation)"}
    end

    defp execute_lookup(_args, context, start_time) do
      ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "lookup", context, :error, 1)
      {:error, "Missing required parameters: table, key (for lookup operation)"}
    end

    # ============================================================================
    # Sample Operation
    # ============================================================================

    defp execute_sample(%{"table" => table_name} = args, context, start_time) when is_binary(table_name) do
      limit = get_limit(args)

      with {:ok, table_ref} <- parse_table_name(table_name),
           :ok <- validate_table_accessible(table_ref),
           :ok <- validate_table_readable(table_ref) do
        entries = sample_entries(table_ref, limit)
        formatted_entries = Enum.map(entries, &format_entry/1)

        total_size =
          try do
            :ets.info(table_ref, :size)
          rescue
            _ -> nil
          end

        result = %{
          "operation" => "sample",
          "table" => table_name,
          "entries" => formatted_entries,
          "count" => length(formatted_entries),
          "total_size" => total_size,
          "truncated" => total_size != nil and total_size > limit
        }

        ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "sample", context, :ok, 0)

        case Jason.encode(result) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
        end
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "sample", context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    defp execute_sample(_args, context, start_time) do
      ElixirHandler.emit_elixir_telemetry(:ets_inspect, start_time, "sample", context, :error, 1)
      {:error, "Missing required parameter: table (for sample operation)"}
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    @spec get_limit(map()) :: pos_integer()
    defp get_limit(args) do
      HandlerHelpers.get_bounded_integer(args, "limit", @default_limit, @max_limit)
    end

    # Parse table name string to ETS table reference
    @spec parse_table_name(String.t()) :: {:ok, atom()} | {:error, atom()}
    defp parse_table_name(name) when is_binary(name) do
      # Try as existing atom first (most ETS tables use atoms)
      try do
        atom = String.to_existing_atom(name)
        {:ok, atom}
      rescue
        ArgumentError ->
          # Try as reference ID (for unnamed tables, format: "#Ref<...>")
          if String.starts_with?(name, "#Ref<") do
            {:error, :reference_tables_not_supported}
          else
            {:error, :table_not_found}
          end
      end
    end

    # Check if table is in blocked list or owned by blocked process
    @spec validate_table_accessible(atom()) :: :ok | {:error, :table_blocked}
    defp validate_table_accessible(table_ref) do
      cond do
        table_ref in @blocked_tables ->
          {:error, :table_blocked}

        is_owner_blocked?(table_ref) ->
          {:error, :table_blocked}

        true ->
          :ok
      end
    end

    # Check if table is readable (public access)
    @spec validate_table_readable(atom()) :: :ok | {:error, atom()}
    defp validate_table_readable(table_ref) do
      case :ets.info(table_ref, :protection) do
        :public ->
          :ok

        :protected ->
          # Protected tables can only be read by owner - check if we own it
          owner = :ets.info(table_ref, :owner)
          if owner == self() do
            :ok
          else
            {:error, :table_protected_not_owner}
          end

        :private ->
          {:error, :table_private}

        :undefined ->
          {:error, :table_not_found}
      end
    end

    @spec is_project_table?(term()) :: boolean()
    defp is_project_table?(table_ref) do
      # Only allow named tables (atoms), not reference-based tables
      is_atom(table_ref) and
        not (table_ref in @blocked_tables) and
        not is_owner_blocked?(table_ref)
    end

    @spec is_owner_blocked?(atom()) :: boolean()
    defp is_owner_blocked?(table_ref) do
      owner = :ets.info(table_ref, :owner)

      case owner do
        :undefined ->
          true

        pid when is_pid(pid) ->
          case Process.info(pid, :registered_name) do
            {:registered_name, []} ->
              # No registered name - check if system process by checking application
              is_system_pid?(pid)

            {:registered_name, name} when is_atom(name) ->
              name_str = to_string(name)
              Enum.any?(@blocked_owner_prefixes, &String.starts_with?(name_str, &1))

            nil ->
              # Process is dead
              true
          end
      end
    end

    @spec is_system_pid?(pid()) :: boolean()
    defp is_system_pid?(pid) do
      # Check if process belongs to kernel or stdlib application
      case :erlang.process_info(pid, :initial_call) do
        {:initial_call, {module, _, _}} ->
          # Block if it's a known system module
          module in [:init, :code_server, :application_controller, :error_logger, :user, :logger]

        _ ->
          # If we can't determine, block it (safe default - better to block unknown than expose)
          true
      end
    end

    @spec get_table_summary(atom()) :: map() | nil
    defp get_table_summary(table_ref) do
      case :ets.info(table_ref) do
        :undefined ->
          nil

        info ->
          %{
            "name" => to_string(table_ref),
            "type" => to_string(Keyword.get(info, :type, :unknown)),
            "size" => Keyword.get(info, :size, 0),
            "memory" => Keyword.get(info, :memory, 0),
            "protection" => to_string(Keyword.get(info, :protection, :unknown))
          }
      end
    end

    @spec format_table_info(keyword()) :: map()
    defp format_table_info(info_list) do
      info_list
      |> Enum.map(fn
        {:owner, pid} when is_pid(pid) -> {"owner", inspect(pid)}
        {:heir, :none} -> {"heir", "none"}
        {:heir, pid} when is_pid(pid) -> {"heir", inspect(pid)}
        {:name, name} -> {"name", to_string(name)}
        {:named_table, val} -> {"named_table", val}
        {:type, type} -> {"type", to_string(type)}
        {:keypos, pos} -> {"keypos", pos}
        {:protection, prot} -> {"protection", to_string(prot)}
        {:size, size} -> {"size", size}
        {:memory, mem} -> {"memory", mem}
        {:compressed, comp} -> {"compressed", comp}
        {:write_concurrency, wc} -> {"write_concurrency", wc}
        {:read_concurrency, rc} -> {"read_concurrency", rc}
        {:decentralized_counters, dc} -> {"decentralized_counters", dc}
        {key, val} -> {to_string(key), inspect(val)}
      end)
      |> Map.new()
    end

    # Parse key from string representation
    @spec parse_key(String.t()) :: {:ok, term()} | {:error, :atom_not_found}
    defp parse_key(key_string) do
      trimmed = String.trim(key_string)

      cond do
        # Atom: :foo or :foo_bar (only existing atoms to prevent atom table exhaustion)
        String.starts_with?(trimmed, ":") ->
          atom_name = String.slice(trimmed, 1..-1//1)

          try do
            {:ok, String.to_existing_atom(atom_name)}
          rescue
            ArgumentError -> {:error, :atom_not_found}
          end

        # Integer
        Regex.match?(~r/^-?\d+$/, trimmed) ->
          {:ok, String.to_integer(trimmed)}

        # Float
        Regex.match?(~r/^-?\d+\.\d+$/, trimmed) ->
          {:ok, String.to_float(trimmed)}

        # Quoted string: "foo" or 'foo'
        (String.starts_with?(trimmed, "\"") and String.ends_with?(trimmed, "\"")) or
            (String.starts_with?(trimmed, "'") and String.ends_with?(trimmed, "'")) ->
          {:ok, String.slice(trimmed, 1..-2//1)}

        # Boolean
        trimmed in ["true", "false"] ->
          {:ok, trimmed == "true"}

        # Otherwise treat as string key
        true ->
          {:ok, trimmed}
      end
    end

    # Sample N entries from table using first/next traversal with memory limit
    @spec sample_entries(atom(), pos_integer()) :: [term()]
    defp sample_entries(table_ref, limit) do
      try do
        first_key = :ets.first(table_ref)
        # Track both count and total size to prevent memory issues
        collect_entries(table_ref, first_key, limit, [], 0)
      rescue
        ArgumentError -> []
      end
    end

    @spec collect_entries(atom(), term(), non_neg_integer(), [term()], non_neg_integer()) :: [term()]
    defp collect_entries(_table_ref, :"$end_of_table", _remaining, acc, _total_size), do: Enum.reverse(acc)
    defp collect_entries(_table_ref, _key, 0, acc, _total_size), do: Enum.reverse(acc)
    # Stop if we've collected too much data (memory limit)
    defp collect_entries(_table_ref, _key, _remaining, acc, total_size) when total_size > @max_entry_size do
      Enum.reverse(acc)
    end

    defp collect_entries(table_ref, key, remaining, acc, total_size) do
      entries = :ets.lookup(table_ref, key)
      # Estimate entry size using :erts_debug.size (word count)
      entry_size = Enum.reduce(entries, 0, fn entry, size -> size + :erts_debug.size(entry) end)
      new_total_size = total_size + entry_size
      new_acc = entries ++ acc
      new_remaining = remaining - length(entries)

      if new_remaining <= 0 or new_total_size > @max_entry_size do
        # We've collected enough or hit memory limit
        Enum.reverse(new_acc)
      else
        next_key = :ets.next(table_ref, key)
        collect_entries(table_ref, next_key, new_remaining, new_acc, new_total_size)
      end
    end

    @spec format_entry(term()) :: String.t()
    defp format_entry(entry) do
      entry
      |> inspect(pretty: true, limit: 50, printable_limit: 4096)
      |> sanitize_output()
    end

    # Sanitize output to redact sensitive fields (same pattern as ProcessState)
    @spec sanitize_output(String.t()) :: String.t()
    defp sanitize_output(output) when is_binary(output) do
      Enum.reduce(@sensitive_fields, output, fn field, acc ->
        patterns = [
          # Double-quoted strings: password => "secret" or password: "secret"
          {~r/(#{field})\s*[=:>]+\s*"[^"]*"/i, "\\1 => \"[REDACTED]\""},
          # Single-quoted strings (charlists): password => 'secret'
          {~r/(#{field})\s*[=:>]+\s*'[^']*'/i, "\\1 => '[REDACTED]'"},
          # Atom prefix format: :password => "secret"
          {~r/(:\s*#{field})\s*[=:>]+\s*"[^"]*"/i, "\\1 => \"[REDACTED]\""},
          # Atom values: password => :secret_value
          {~r/(#{field})\s*[=:>]+\s*:[a-zA-Z_][a-zA-Z0-9_]*/i, "\\1 => :[REDACTED]"},
          # Integer values: password => 12345
          {~r/(#{field})\s*[=:>]+\s*\d+/i, "\\1 => [REDACTED]"},
          # Charlist syntax: password => ~c"secret"
          {~r/(#{field})\s*[=:>]+\s*~c"[^"]*"/i, "\\1 => ~c\"[REDACTED]\""},
          # Binary syntax: password => <<"secret">>
          {~r/(#{field})\s*[=:>]+\s*<<[^>]*>>/i, "\\1 => <<[REDACTED]>>"},
          # Unquoted barewords (identifiers): password => secret_value
          {~r/(#{field})\s*[=:>]+\s*([a-zA-Z_][a-zA-Z0-9_]*)\b(?!\s*[=:>\(\[])/i, "\\1 => [REDACTED]"}
        ]

        Enum.reduce(patterns, acc, fn {pattern, replacement}, inner_acc ->
          Regex.replace(pattern, inner_acc, replacement)
        end)
      end)
    end

    @spec format_error(atom() | String.t()) :: String.t()
    defp format_error(:table_not_found), do: "Table not found"
    defp format_error(:table_blocked), do: "Access to this table is blocked for security"
    defp format_error(:table_private), do: "Table is private and cannot be read"
    defp format_error(:table_protected_not_owner), do: "Table is protected and can only be read by its owner process"
    defp format_error(:reference_tables_not_supported), do: "Reference-based tables are not supported"
    defp format_error(:invalid_key), do: "Invalid key format"
    defp format_error(:atom_not_found), do: "Atom key does not exist (only existing atoms are allowed)"
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: "Error: #{inspect(reason)}"
  end

  # ============================================================================
  # FetchDocs Handler
  # ============================================================================

  defmodule FetchDocs do
    @moduledoc """
    Handler for the fetch_elixir_docs tool.

    Retrieves documentation for Elixir modules and functions using `Code.fetch_docs/1`
    and type specifications using `Code.Typespec.fetch_specs/1`.

    ## Security Features

    - Uses `String.to_existing_atom/1` to prevent atom table exhaustion
    - Only existing (loaded) modules can be queried
    - Non-existent modules return an error

    ## Output Format

    Returns JSON with:
    - `moduledoc` - Module-level documentation
    - `docs` - Function documentation (filtered if function/arity specified)
    - `specs` - Type specifications for functions
    """

    alias JidoCode.Tools.Handlers.Elixir, as: ElixirHandler

    @doc """
    Fetches documentation for an Elixir module or function.

    ## Arguments

    - `"module"` - Module name (required, e.g., "Enum", "String")
    - `"function"` - Function name to filter (optional)
    - `"arity"` - Function arity to filter (optional, requires function)

    ## Returns

    - `{:ok, json}` - JSON with moduledoc, docs, and specs
    - `{:error, reason}` - Error message
    """
    @spec execute(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
    def execute(%{"module" => module_name} = args, context) when is_binary(module_name) do
      start_time = System.monotonic_time(:microsecond)

      with {:ok, module} <- parse_module_name(module_name),
           {:ok, docs_chunk} <- fetch_docs(module) do
        function_filter = Map.get(args, "function")
        arity_filter = Map.get(args, "arity")

        moduledoc = extract_moduledoc(docs_chunk)
        function_docs = extract_function_docs(docs_chunk, function_filter, arity_filter)
        specs = fetch_specs(module, function_filter, arity_filter)

        result = %{
          "module" => module_name,
          "moduledoc" => moduledoc,
          "docs" => function_docs,
          "specs" => specs
        }

        ElixirHandler.emit_elixir_telemetry(:fetch_docs, start_time, module_name, context, :ok, 0)

        case Jason.encode(result) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, "Failed to encode result: #{inspect(reason)}"}
        end
      else
        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:fetch_docs, start_time, module_name, context, :error, 1)
          {:error, format_error(reason)}
      end
    end

    def execute(%{"module" => module}, _context) do
      {:error, "Invalid module: expected string, got #{inspect(module)}"}
    end

    def execute(_args, _context) do
      {:error, "Missing required parameter: module"}
    end

    # ============================================================================
    # Private Helpers
    # ============================================================================

    # Parse module name string to module atom using existing atoms only
    @spec parse_module_name(String.t()) :: {:ok, module()} | {:error, atom()}
    defp parse_module_name(name) when is_binary(name) do
      # Handle "Elixir." prefix automatically
      normalized_name =
        if String.starts_with?(name, "Elixir.") do
          name
        else
          "Elixir." <> name
        end

      try do
        atom = String.to_existing_atom(normalized_name)

        # Verify the module is loaded
        if Code.ensure_loaded?(atom) do
          {:ok, atom}
        else
          {:error, :module_not_loaded}
        end
      rescue
        ArgumentError ->
          {:error, :module_not_found}
      end
    end

    # Fetch documentation chunk for a module
    @spec fetch_docs(module()) :: {:ok, tuple()} | {:error, atom()}
    defp fetch_docs(module) do
      case Code.fetch_docs(module) do
        {:docs_v1, _, _, _, _, _, _} = docs ->
          {:ok, docs}

        {:error, :chunk_not_found} ->
          {:error, :no_docs}

        {:error, :module_not_found} ->
          {:error, :module_not_found}

        {:error, reason} ->
          {:error, reason}
      end
    end

    # Extract module-level documentation
    @spec extract_moduledoc(tuple()) :: String.t() | nil
    defp extract_moduledoc({:docs_v1, _, _, _, moduledoc, _, _}) do
      case moduledoc do
        %{"en" => doc} when is_binary(doc) -> doc
        :hidden -> nil
        :none -> nil
        _ -> nil
      end
    end

    # Extract function documentation, optionally filtered by function name and arity
    @spec extract_function_docs(tuple(), String.t() | nil, integer() | nil) :: [map()]
    defp extract_function_docs({:docs_v1, _, _, _, _, _, docs}, function_filter, arity_filter) do
      docs
      |> Enum.filter(fn
        {{kind, _name, _arity}, _, _, _, _} when kind in [:function, :macro] -> true
        _ -> false
      end)
      |> Enum.filter(fn {{_kind, name, arity}, _, _, _, _} ->
        matches_filter?(name, arity, function_filter, arity_filter)
      end)
      |> Enum.map(fn {{kind, name, arity}, _line, signature, doc, metadata} ->
        %{
          "name" => Atom.to_string(name),
          "arity" => arity,
          "kind" => Atom.to_string(kind),
          "signature" => format_signature(signature),
          "doc" => extract_doc_text(doc),
          "deprecated" => Map.get(metadata, :deprecated)
        }
      end)
    end

    # Check if a function matches the filter criteria
    @spec matches_filter?(atom(), integer(), String.t() | nil, integer() | nil) :: boolean()
    defp matches_filter?(_name, _arity, nil, nil), do: true

    defp matches_filter?(name, _arity, function_filter, nil) when is_binary(function_filter) do
      Atom.to_string(name) == function_filter
    end

    defp matches_filter?(name, arity, function_filter, arity_filter)
         when is_binary(function_filter) and is_integer(arity_filter) do
      Atom.to_string(name) == function_filter and arity == arity_filter
    end

    defp matches_filter?(_name, _arity, _function_filter, _arity_filter), do: true

    # Format function signature for display
    @spec format_signature([binary()]) :: String.t() | nil
    defp format_signature(signature) when is_list(signature) do
      case signature do
        [] -> nil
        [head | _] -> head
      end
    end

    defp format_signature(_), do: nil

    # Extract documentation text from doc chunk
    @spec extract_doc_text(map() | atom()) :: String.t() | nil
    defp extract_doc_text(%{"en" => doc}) when is_binary(doc), do: doc
    defp extract_doc_text(:hidden), do: nil
    defp extract_doc_text(:none), do: nil
    defp extract_doc_text(_), do: nil

    # Fetch type specifications for a module, optionally filtered
    @spec fetch_specs(module(), String.t() | nil, integer() | nil) :: [map()]
    defp fetch_specs(module, function_filter, arity_filter) do
      case Code.Typespec.fetch_specs(module) do
        {:ok, specs} ->
          specs
          |> Enum.filter(fn {{name, arity}, _spec} ->
            matches_spec_filter?(name, arity, function_filter, arity_filter)
          end)
          |> Enum.map(fn {{name, arity}, spec_list} ->
            formatted_specs =
              Enum.map(spec_list, fn spec ->
                Code.Typespec.spec_to_quoted(name, spec)
                |> Macro.to_string()
              end)

            %{
              "name" => Atom.to_string(name),
              "arity" => arity,
              "specs" => formatted_specs
            }
          end)

        :error ->
          []
      end
    end

    # Check if a spec matches the filter criteria
    @spec matches_spec_filter?(atom(), integer(), String.t() | nil, integer() | nil) :: boolean()
    defp matches_spec_filter?(_name, _arity, nil, nil), do: true

    defp matches_spec_filter?(name, _arity, function_filter, nil) when is_binary(function_filter) do
      Atom.to_string(name) == function_filter
    end

    defp matches_spec_filter?(name, arity, function_filter, arity_filter)
         when is_binary(function_filter) and is_integer(arity_filter) do
      Atom.to_string(name) == function_filter and arity == arity_filter
    end

    defp matches_spec_filter?(_name, _arity, _function_filter, _arity_filter), do: true

    # Format error messages
    @spec format_error(atom() | String.t()) :: String.t()
    defp format_error(:module_not_found), do: "Module not found (only existing modules can be queried)"
    defp format_error(:module_not_loaded), do: "Module exists but is not loaded"
    defp format_error(:no_docs), do: "Module has no embedded documentation"
    defp format_error(reason) when is_binary(reason), do: reason
    defp format_error(reason), do: "Error: #{inspect(reason)}"
  end
end
