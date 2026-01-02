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

    @default_timeout 5_000
    @max_timeout 30_000

    # Blocked process prefixes for security
    # System processes and JidoCode internals should not be inspected
    @blocked_prefixes [
      "JidoCode.Tools",
      "JidoCode.Session",
      "JidoCode.Registry",
      "Elixir.JidoCode.Tools",
      "Elixir.JidoCode.Session",
      "Elixir.JidoCode.Registry",
      ":kernel",
      ":stdlib",
      ":init",
      ":code_server",
      ":user",
      ":application_controller",
      ":error_logger",
      ":logger"
    ]

    # Sensitive field names to redact
    @sensitive_fields [
      "password",
      "secret",
      "token",
      "api_key",
      "apikey",
      "private_key",
      "credentials",
      "auth",
      "bearer"
    ]

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
      timeout = get_timeout(args)

      with :ok <- validate_process_name(process_name),
           :ok <- validate_not_blocked(process_name),
           {:ok, pid} <- lookup_process(process_name) do
        get_and_format_state(pid, process_name, timeout, context, start_time)
      else
        {:error, reason} ->
          emit_telemetry(start_time, process_name, context, :error)
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

    defp get_timeout(args) do
      case Map.get(args, "timeout") do
        nil -> @default_timeout
        timeout when is_integer(timeout) and timeout > 0 -> min(timeout, @max_timeout)
        _ -> @default_timeout
      end
    end

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

          emit_telemetry(start_time, process_name, context, :ok)

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

          emit_telemetry(start_time, process_name, context, :timeout)

          case Jason.encode(result) do
            {:ok, json} -> {:ok, json}
            {:error, _} -> {:error, "Timeout getting process state"}
          end

        {:error, reason} ->
          emit_telemetry(start_time, process_name, context, :error)
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
    defp sanitize_output(output) when is_binary(output) do
      Enum.reduce(@sensitive_fields, output, fn field, acc ->
        # Pattern: field => "value" or field: "value"
        patterns = [
          ~r/#{field}\s*[=:>]+\s*"[^"]*"/i,
          ~r/#{field}\s*[=:>]+\s*'[^']*'/i,
          ~r/:#{field}\s*[=:>]+\s*"[^"]*"/i
        ]

        Enum.reduce(patterns, acc, fn pattern, inner_acc ->
          Regex.replace(pattern, inner_acc, "#{field} => \"[REDACTED]\"")
        end)
      end)
    end

    defp emit_telemetry(start_time, process_name, context, status) do
      duration = System.monotonic_time(:microsecond) - start_time

      :telemetry.execute(
        [:jido_code, :elixir, :process_state],
        %{duration: duration},
        %{
          process: process_name,
          status: status,
          session_id: Map.get(context, :session_id)
        }
      )
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
end
