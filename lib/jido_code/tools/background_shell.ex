defmodule JidoCode.Tools.BackgroundShell do
  @moduledoc """
  Manages background shell processes for long-running commands.

  This module provides a registry and process management for background shell
  commands. Each background shell is a supervised Task that captures output
  into an ETS-backed accumulator.

  ## Architecture

  ```
  ┌─────────────────────────────────────────────────────────────┐
  │  BackgroundShell (GenServer)                                 │
  │  - ETS table for shell registry                              │
  │  - Maps shell_id -> process info and output                  │
  └─────────────────────────────────────────────────────────────┘
                              │
                              ▼
  ┌─────────────────────────────────────────────────────────────┐
  │  Task.Supervisor (JidoCode.TaskSupervisor)                   │
  │  - Supervises background command Tasks                       │
  │  - Handles crash isolation                                   │
  └─────────────────────────────────────────────────────────────┘
  ```

  ## Usage

      # Start a background command
      {:ok, shell_id} = BackgroundShell.start_command("mix test", session_id, "/path/to/project")

      # Get output (non-blocking)
      {:ok, info} = BackgroundShell.get_output(shell_id)
      # => %{output: "...", status: :running, exit_code: nil}

      # Get output (blocking)
      {:ok, info} = BackgroundShell.get_output(shell_id, block: true, timeout: 30_000)

      # Kill a running process
      :ok = BackgroundShell.kill(shell_id)

      # List all shells for a session
      shells = BackgroundShell.list(session_id)

  ## Security

  Commands are validated through the Shell handler's command allowlist before
  execution. Shell interpreters (bash, sh, etc.) are blocked.
  """

  use GenServer

  require Logger

  alias JidoCode.Tools.Handlers.Shell

  @type shell_id :: String.t()
  @type shell_status :: :running | :completed | :failed | :killed
  @type shell_info :: %{
          shell_id: shell_id(),
          session_id: String.t(),
          command: String.t(),
          args: [String.t()],
          description: String.t() | nil,
          status: shell_status(),
          exit_code: integer() | nil,
          started_at: DateTime.t(),
          ended_at: DateTime.t() | nil,
          pid: pid() | nil
        }

  @table_name :jido_code_background_shells
  @max_output_size 30_000
  @default_timeout 30_000

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the BackgroundShell GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a background command.

  ## Parameters

  - `command` - The command to execute (must be in allowlist)
  - `args` - Command arguments (default: [])
  - `session_id` - Session ID for tracking
  - `project_root` - Working directory for the command
  - `opts` - Options:
    - `:description` - Optional description for tracking

  ## Returns

  - `{:ok, shell_id}` - Shell ID for tracking
  - `{:error, reason}` - Error message

  ## Examples

      {:ok, shell_id} = BackgroundShell.start_command("mix", ["test"], session_id, project_root)
      {:ok, shell_id} = BackgroundShell.start_command("npm", ["run", "dev"], session_id, project_root,
                                                       description: "Development server")
  """
  @spec start_command(String.t(), [String.t()], String.t(), String.t(), keyword()) ::
          {:ok, shell_id()} | {:error, String.t()}
  def start_command(command, args \\ [], session_id, project_root, opts \\ []) do
    with {:ok, _valid} <- Shell.validate_command(command) do
      GenServer.call(__MODULE__, {:start_command, command, args, session_id, project_root, opts})
    else
      {:error, :command_not_allowed} ->
        {:error, "Command not allowed: #{command}"}

      {:error, :shell_interpreter_blocked} ->
        {:error, "Shell interpreters are blocked: #{command}"}
    end
  end

  @doc """
  Gets the output and status of a background shell.

  ## Options

  - `:block` - If true, wait for completion (default: false)
  - `:timeout` - Max wait time in ms when blocking (default: 30000)

  ## Returns

  - `{:ok, info}` - Shell info with output, status, exit_code
  - `{:error, :not_found}` - Shell ID not found
  """
  @spec get_output(shell_id(), keyword()) ::
          {:ok, %{output: String.t(), status: shell_status(), exit_code: integer() | nil}}
          | {:error, :not_found | :timeout}
  def get_output(shell_id, opts \\ []) do
    block = Keyword.get(opts, :block, false)
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    if block do
      get_output_blocking(shell_id, timeout)
    else
      get_output_nonblocking(shell_id)
    end
  end

  defp get_output_nonblocking(shell_id) do
    case :ets.lookup(@table_name, shell_id) do
      [{^shell_id, info}] ->
        output = get_accumulated_output(shell_id)

        {:ok,
         %{
           output: output,
           status: info.status,
           exit_code: info.exit_code
         }}

      [] ->
        {:error, :not_found}
    end
  end

  defp get_output_blocking(shell_id, timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout

    do_blocking_wait(shell_id, deadline)
  end

  defp do_blocking_wait(shell_id, deadline) do
    remaining = deadline - System.monotonic_time(:millisecond)

    if remaining <= 0 do
      {:error, :timeout}
    else
      case :ets.lookup(@table_name, shell_id) do
        [{^shell_id, info}] when info.status in [:completed, :failed, :killed] ->
          output = get_accumulated_output(shell_id)

          {:ok,
           %{
             output: output,
             status: info.status,
             exit_code: info.exit_code
           }}

        [{^shell_id, _info}] ->
          # Still running, wait a bit
          Process.sleep(min(100, remaining))
          do_blocking_wait(shell_id, deadline)

        [] ->
          {:error, :not_found}
      end
    end
  end

  @doc """
  Kills a running background shell.

  ## Returns

  - `:ok` - Successfully killed
  - `{:error, :not_found}` - Shell ID not found
  - `{:error, :already_finished}` - Shell already completed
  """
  @spec kill(shell_id()) :: :ok | {:error, :not_found | :already_finished}
  def kill(shell_id) do
    GenServer.call(__MODULE__, {:kill, shell_id})
  end

  @doc """
  Lists all background shells for a session.

  ## Returns

  List of shell info maps.
  """
  @spec list(String.t()) :: [shell_info()]
  def list(session_id) do
    :ets.foldl(
      fn {_id, info}, acc ->
        if info.session_id == session_id do
          [Map.put(info, :output, get_accumulated_output(info.shell_id)) | acc]
        else
          acc
        end
      end,
      [],
      @table_name
    )
  end

  @doc """
  Clears all finished shells for a session.

  Running shells are not affected.
  """
  @spec clear_finished(String.t()) :: :ok
  def clear_finished(session_id) do
    GenServer.call(__MODULE__, {:clear_finished, session_id})
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Create ETS tables (or use existing ones if restarting)
    ensure_ets_table(@table_name)
    ensure_ets_table(:jido_code_shell_output)

    {:ok, %{}}
  end

  defp ensure_ets_table(name) do
    case :ets.whereis(name) do
      :undefined ->
        :ets.new(name, [:named_table, :public, :set])
      _ref ->
        :ok
    end
  end

  @impl true
  def handle_call({:start_command, command, args, session_id, project_root, opts}, _from, state) do
    shell_id = generate_shell_id()
    description = Keyword.get(opts, :description)

    # Initialize output accumulator
    :ets.insert(:jido_code_shell_output, {shell_id, ""})

    # Start the task
    task =
      Task.Supervisor.async_nolink(JidoCode.TaskSupervisor, fn ->
        execute_command(shell_id, command, args, project_root)
      end)

    # Register the shell
    info = %{
      shell_id: shell_id,
      session_id: session_id,
      command: command,
      args: args,
      description: description,
      status: :running,
      exit_code: nil,
      started_at: DateTime.utc_now(),
      ended_at: nil,
      pid: task.pid
    }

    :ets.insert(@table_name, {shell_id, info})

    # Monitor the task
    Process.monitor(task.pid)

    # Emit telemetry
    :telemetry.execute(
      [:jido_code, :shell, :background_start],
      %{},
      %{shell_id: shell_id, command: command, session_id: session_id}
    )

    Logger.debug("Started background shell #{shell_id}: #{command} #{Enum.join(args, " ")}")

    {:reply, {:ok, shell_id}, Map.put(state, task.pid, shell_id)}
  end

  @impl true
  def handle_call({:kill, shell_id}, _from, state) do
    case :ets.lookup(@table_name, shell_id) do
      [{^shell_id, info}] when info.status == :running ->
        # Kill the process
        if info.pid && Process.alive?(info.pid) do
          Process.exit(info.pid, :kill)
        end

        # Update status
        updated_info = %{info | status: :killed, ended_at: DateTime.utc_now()}
        :ets.insert(@table_name, {shell_id, updated_info})

        # Emit telemetry
        :telemetry.execute(
          [:jido_code, :shell, :background_kill],
          %{},
          %{shell_id: shell_id, session_id: info.session_id}
        )

        Logger.debug("Killed background shell #{shell_id}")

        {:reply, :ok, state}

      [{^shell_id, _info}] ->
        {:reply, {:error, :already_finished}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:clear_finished, session_id}, _from, state) do
    # Get all finished shells for this session
    to_delete =
      :ets.foldl(
        fn {id, info}, acc ->
          if info.session_id == session_id && info.status in [:completed, :failed, :killed] do
            [id | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    # Delete them
    Enum.each(to_delete, fn id ->
      :ets.delete(@table_name, id)
      :ets.delete(:jido_code_shell_output, id)
    end)

    {:reply, :ok, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case Map.pop(state, pid) do
      {nil, state} ->
        {:noreply, state}

      {shell_id, state} ->
        update_shell_status(shell_id, reason)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({ref, {:ok, _exit_code}}, state) when is_reference(ref) do
    # Task completed successfully
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({ref, {:error, _reason}}, state) when is_reference(ref) do
    # Task failed
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp generate_shell_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end

  defp execute_command(shell_id, command, args, project_root) do
    port =
      Port.open({:spawn_executable, System.find_executable(command)}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, args},
        {:cd, project_root},
        {:env, []}
      ])

    collect_output(shell_id, port)
  end

  defp collect_output(shell_id, port) do
    receive do
      {^port, {:data, data}} ->
        append_output(shell_id, data)
        collect_output(shell_id, port)

      {^port, {:exit_status, exit_code}} ->
        {:ok, exit_code}
    end
  end

  defp append_output(shell_id, new_data) do
    case :ets.lookup(:jido_code_shell_output, shell_id) do
      [{^shell_id, current}] ->
        updated = truncate_output(current <> new_data)
        :ets.insert(:jido_code_shell_output, {shell_id, updated})

      [] ->
        :ets.insert(:jido_code_shell_output, {shell_id, truncate_output(new_data)})
    end
  end

  defp get_accumulated_output(shell_id) do
    case :ets.lookup(:jido_code_shell_output, shell_id) do
      [{^shell_id, output}] -> output
      [] -> ""
    end
  end

  defp truncate_output(output) when byte_size(output) > @max_output_size do
    # Keep the last @max_output_size bytes
    start = byte_size(output) - @max_output_size
    "[Output truncated...]\n" <> binary_part(output, start, @max_output_size)
  end

  defp truncate_output(output), do: output

  defp update_shell_status(shell_id, reason) do
    case :ets.lookup(@table_name, shell_id) do
      [{^shell_id, info}] when info.status == :running ->
        {status, exit_code} =
          case reason do
            :normal -> {:completed, 0}
            {:shutdown, {:ok, code}} -> {:completed, code}
            _ -> {:failed, 1}
          end

        updated_info = %{
          info
          | status: status,
            exit_code: exit_code,
            ended_at: DateTime.utc_now(),
            pid: nil
        }

        :ets.insert(@table_name, {shell_id, updated_info})

        # Emit telemetry
        :telemetry.execute(
          [:jido_code, :shell, :background_complete],
          %{exit_code: exit_code},
          %{shell_id: shell_id, status: status, session_id: info.session_id}
        )

        Logger.debug("Background shell #{shell_id} completed with status #{status}")

      _ ->
        :ok
    end
  end
end
