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

  @blocked_tasks ~w(
    release archive.install escript.build
    local.hex local.rebar hex.publish
    deps.update do
    ecto.drop ecto.reset
    phx.gen.secret
  )

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

  ## Returns

  - `{:ok, task}` - Task is allowed
  - `{:error, :task_blocked}` - Task is explicitly blocked
  - `{:error, :task_not_allowed}` - Task is not in allowlist
  """
  @spec validate_task(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def validate_task(task) do
    cond do
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
  @spec format_error(atom() | String.t(), String.t()) :: String.t()
  def format_error(:task_not_allowed, task), do: "Mix task not allowed: #{task}"
  def format_error(:task_blocked, task), do: "Mix task is blocked: #{task}"
  def format_error(:env_blocked, _task), do: "Environment 'prod' is blocked for safety"
  def format_error(:timeout, task), do: "Mix task timed out: #{task}"
  def format_error(:enoent, _task), do: "Mix command not found"
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

    ## Implementation Status

    This handler is a stub. Full implementation is in Section 5.1.2.
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

      with {:ok, task} <- ElixirHandler.validate_task(task),
           {:ok, env} <- ElixirHandler.validate_env(Map.get(args, "env")),
           {:ok, project_root} <- ElixirHandler.get_project_root(context) do
        task_args = Map.get(args, "args", [])
        timeout = get_timeout(args)

        execute_mix_task(task, task_args, env, project_root, timeout, context, start_time)
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

    defp execute_mix_task(task, task_args, env, project_root, timeout, context, start_time) do
      # Validate all args are strings
      case validate_args(task_args) do
        :ok ->
          run_mix_command(task, task_args, env, project_root, timeout, context, start_time)

        {:error, reason} ->
          ElixirHandler.emit_elixir_telemetry(:mix_task, start_time, task, context, :error, 1)
          {:error, reason}
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

            {:ok, Jason.encode!(result)}

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
end
