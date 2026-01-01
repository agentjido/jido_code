defmodule JidoCode.Tools.Security.IsolatedExecutor do
  @moduledoc """
  Process isolation for handler execution.

  This module executes handlers in isolated processes with resource limits
  to prevent runaway handlers from affecting the main application.

  ## Features

  - **Process Isolation**: Each handler runs in a separate process
  - **Memory Limits**: Configurable max heap size per execution
  - **Timeout Enforcement**: Graceful shutdown with configurable timeout
  - **Crash Isolation**: Handler crashes don't affect main app

  ## Usage

      case IsolatedExecutor.execute_isolated(handler, args, context, opts) do
        {:ok, result} -> handle_result(result)
        {:error, :timeout} -> handle_timeout()
        {:error, {:killed, :max_heap_size}} -> handle_memory_limit()
        {:error, {:crashed, reason}} -> handle_crash(reason)
      end

  ## Options

  - `:timeout` - Execution timeout in milliseconds (default: 30_000)
  - `:max_heap_size` - Maximum heap size in words (default: 1_000_000 ~= 8MB on 64-bit)
  - `:supervisor` - Task.Supervisor to use (default: JidoCode.TaskSupervisor)

  ## Telemetry

  Emits `[:jido_code, :security, :isolation]` with:
  - `:duration` - Execution duration in microseconds
  - `:handler` - Handler module name
  - `:result` - `:ok`, `:timeout`, `:killed`, or `:crashed`
  - `:reason` - Additional context for failures
  """

  require Logger

  @default_timeout 30_000
  @default_max_heap_size 1_000_000
  @default_supervisor JidoCode.TaskSupervisor

  @typedoc """
  Options for isolated execution.
  """
  @type option ::
          {:timeout, pos_integer()}
          | {:max_heap_size, pos_integer()}
          | {:supervisor, atom()}

  @typedoc """
  Result of isolated execution.
  """
  @type result ::
          {:ok, term()}
          | {:error, :timeout}
          | {:error, {:killed, :max_heap_size}}
          | {:error, {:crashed, term()}}

  @doc """
  Executes a handler in an isolated process with resource limits.

  ## Parameters

  - `handler` - Module implementing `execute/2`
  - `args` - Arguments to pass to the handler
  - `context` - Execution context
  - `opts` - Options (see module docs)

  ## Returns

  - `{:ok, result}` - Handler completed successfully
  - `{:error, :timeout}` - Handler exceeded timeout
  - `{:error, {:killed, :max_heap_size}}` - Handler exceeded memory limit
  - `{:error, {:crashed, reason}}` - Handler crashed

  ## Examples

      iex> IsolatedExecutor.execute_isolated(MyHandler, %{"path" => "file.txt"}, %{}, timeout: 5000)
      {:ok, "file contents"}

      iex> IsolatedExecutor.execute_isolated(SlowHandler, %{}, %{}, timeout: 100)
      {:error, :timeout}
  """
  @spec execute_isolated(module(), map(), map(), [option()]) :: result()
  def execute_isolated(handler, args, context, opts \\ []) do
    start_time = System.monotonic_time(:microsecond)
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    max_heap_size = Keyword.get(opts, :max_heap_size, @default_max_heap_size)
    supervisor = Keyword.get(opts, :supervisor, @default_supervisor)

    # Create a reference for tracking this specific execution
    ref = make_ref()
    caller = self()

    # Start the task under supervision
    task =
      Task.Supervisor.async_nolink(
        supervisor,
        fn ->
          # Set memory limit on the spawned process
          Process.flag(:max_heap_size, %{size: max_heap_size, kill: true, error_logger: true})

          # Execute the handler
          try do
            result = handler.execute(args, context)
            send(caller, {:isolated_result, ref, result})
          rescue
            e ->
              send(caller, {:isolated_crash, ref, {:exception, e, __STACKTRACE__}})
          catch
            kind, reason ->
              send(caller, {:isolated_crash, ref, {kind, reason}})
          end
        end,
        shutdown: :brutal_kill
      )

    # Wait for result with timeout
    result = await_result(ref, task, timeout)

    # Emit telemetry
    emit_telemetry(handler, result, start_time)

    result
  end

  @doc """
  Checks if a Task.Supervisor is available for isolated execution.

  Returns `true` if the supervisor exists and is running.
  """
  @spec supervisor_available?(atom()) :: boolean()
  def supervisor_available?(supervisor \\ @default_supervisor) do
    case Process.whereis(supervisor) do
      nil -> false
      pid -> Process.alive?(pid)
    end
  end

  @doc """
  Returns the default configuration for isolated execution.
  """
  @spec defaults() :: %{timeout: pos_integer(), max_heap_size: pos_integer(), supervisor: atom()}
  def defaults do
    %{
      timeout: @default_timeout,
      max_heap_size: @default_max_heap_size,
      supervisor: @default_supervisor
    }
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  defp await_result(ref, task, timeout) do
    receive do
      {:isolated_result, ^ref, result} ->
        # Clean up the task reference
        Task.shutdown(task, :brutal_kill)
        result

      {:isolated_crash, ^ref, reason} ->
        Task.shutdown(task, :brutal_kill)
        {:error, {:crashed, reason}}

      {:DOWN, _task_ref, :process, _pid, :killed} ->
        # Process was killed, likely due to max_heap_size
        {:error, {:killed, :max_heap_size}}

      {:DOWN, _task_ref, :process, _pid, reason} ->
        {:error, {:crashed, reason}}
    after
      timeout ->
        # Timeout - shutdown the task
        Task.shutdown(task, :brutal_kill)
        {:error, :timeout}
    end
  end

  defp emit_telemetry(handler, result, start_time) do
    duration = System.monotonic_time(:microsecond) - start_time

    {status, reason} =
      case result do
        {:ok, _} -> {:ok, nil}
        {:error, :timeout} -> {:timeout, nil}
        {:error, {:killed, reason}} -> {:killed, reason}
        {:error, {:crashed, reason}} -> {:crashed, reason}
        # Handler returned an error (not a crash) - this is still a successful execution
        {:error, _handler_error} -> {:ok, nil}
      end

    :telemetry.execute(
      [:jido_code, :security, :isolation],
      %{duration: duration},
      %{
        handler: handler,
        result: status,
        reason: reason
      }
    )
  end
end
