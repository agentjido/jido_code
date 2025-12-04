defmodule JidoCode.Test.SessionTestHelpers do
  @moduledoc """
  Shared test setup helpers for session-related tests.

  Extracts common setup code to reduce duplication across test files.

  ## Available Setup Functions

  - `setup_session_registry/1` - Lightweight setup for unit tests (Registry + tmp_dir)
  - `setup_session_supervisor/1` - Full setup with SessionSupervisor for integration tests
  """

  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor

  @registry JidoCode.SessionProcessRegistry

  # ============================================================================
  # Lightweight Setup (for unit tests)
  # ============================================================================

  @doc """
  Sets up the session registry test environment for unit tests.

  This is a lightweight setup that only starts the SessionProcessRegistry
  and creates a temporary directory. Use this for testing individual
  session modules (Manager, State, Session.Supervisor) in isolation.

  Returns a map with:
  - `:tmp_dir` - Path to temporary directory for test files

  ## Usage

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_registry()
      end

  Or with a custom suffix:

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_registry("manager_test")
      end
  """
  @spec setup_session_registry(String.t()) :: {:ok, map()}
  def setup_session_registry(suffix \\ "test") do
    # Stop existing registry if running
    if pid = Process.whereis(@registry) do
      GenServer.stop(pid)
    end

    {:ok, _} = Registry.start_link(keys: :unique, name: @registry)

    # Create a temp directory for sessions
    tmp_dir = Path.join(System.tmp_dir!(), "session_#{suffix}_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    ExUnit.Callbacks.on_exit(fn ->
      cleanup_session_registry(tmp_dir)
    end)

    {:ok, %{tmp_dir: tmp_dir}}
  end

  @doc """
  Cleans up session registry test resources.

  Called automatically via on_exit when using setup_session_registry/1.
  """
  @spec cleanup_session_registry(String.t()) :: :ok
  def cleanup_session_registry(tmp_dir) do
    File.rm_rf!(tmp_dir)

    if pid = Process.whereis(@registry) do
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  # ============================================================================
  # Full Setup (for integration tests)
  # ============================================================================

  @doc """
  Sets up the session supervisor test environment.

  Starts SessionProcessRegistry, SessionSupervisor, creates SessionRegistry table,
  and creates a temporary directory for test projects.

  Returns a map with:
  - `:sup_pid` - The SessionSupervisor pid
  - `:tmp_dir` - Path to temporary directory for test files

  ## Usage

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_supervisor()
      end

  Or with a custom suffix for the temp directory:

      setup do
        JidoCode.Test.SessionTestHelpers.setup_session_supervisor("my_test")
      end
  """
  @spec setup_session_supervisor(String.t()) :: {:ok, map()}
  def setup_session_supervisor(suffix \\ "test") do
    # Stop SessionSupervisor if already running
    if pid = Process.whereis(SessionSupervisor) do
      Supervisor.stop(pid)
    end

    # Start SessionProcessRegistry for via tuples
    if pid = Process.whereis(JidoCode.SessionProcessRegistry) do
      GenServer.stop(pid)
    end

    {:ok, _} = Registry.start_link(keys: :unique, name: JidoCode.SessionProcessRegistry)

    # Start SessionSupervisor
    {:ok, sup_pid} = SessionSupervisor.start_link([])

    # Ensure SessionRegistry table exists and is empty
    SessionRegistry.create_table()
    SessionRegistry.clear()

    # Create a temp directory for sessions
    tmp_dir = Path.join(System.tmp_dir!(), "session_#{suffix}_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    ExUnit.Callbacks.on_exit(fn ->
      cleanup_session_supervisor(sup_pid, tmp_dir)
    end)

    {:ok, %{sup_pid: sup_pid, tmp_dir: tmp_dir}}
  end

  @doc """
  Cleans up session supervisor test resources.

  Called automatically via on_exit when using setup_session_supervisor/1,
  but can be called manually if needed.
  """
  @spec cleanup_session_supervisor(pid(), String.t()) :: :ok
  def cleanup_session_supervisor(sup_pid, tmp_dir) do
    SessionRegistry.clear()
    File.rm_rf!(tmp_dir)

    if Process.alive?(sup_pid) do
      try do
        Supervisor.stop(sup_pid)
      catch
        :exit, _ -> :ok
      end
    end

    if pid = Process.whereis(JidoCode.SessionProcessRegistry) do
      try do
        GenServer.stop(pid)
      catch
        :exit, _ -> :ok
      end
    end

    :ok
  end

  @doc """
  Waits for a process to terminate using process monitoring.

  This is preferred over `:timer.sleep/1` as it's deterministic and
  doesn't cause flaky tests on slow CI systems.

  ## Parameters

  - `pid` - The process to wait for
  - `timeout` - Maximum time to wait in milliseconds (default: 100)

  ## Returns

  - `:ok` - Process terminated
  - `:timeout` - Process didn't terminate within timeout

  ## Examples

      {:ok, pid} = start_some_process()
      Process.exit(pid, :normal)
      :ok = wait_for_process_death(pid)
  """
  @spec wait_for_process_death(pid(), non_neg_integer()) :: :ok | :timeout
  def wait_for_process_death(pid, timeout \\ 100) do
    ref = Process.monitor(pid)

    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      timeout ->
        Process.demonitor(ref, [:flush])
        :timeout
    end
  end

  @doc """
  Waits for a Registry entry to be removed.

  Polls the Registry until the key is no longer present or timeout is reached.
  This is useful when testing process cleanup, as Registry entries may persist
  briefly after process termination.

  ## Parameters

  - `registry` - The Registry module name
  - `key` - The Registry key to check
  - `timeout` - Maximum time to wait in milliseconds (default: 100)

  ## Returns

  - `:ok` - Entry was removed
  - `:timeout` - Entry still exists after timeout

  ## Examples

      :ok = wait_for_registry_cleanup(MyRegistry, {:session, session_id})
  """
  @spec wait_for_registry_cleanup(atom(), term(), non_neg_integer()) :: :ok | :timeout
  def wait_for_registry_cleanup(registry, key, timeout \\ 100) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_registry(registry, key, deadline)
  end

  defp poll_registry(registry, key, deadline) do
    case Registry.lookup(registry, key) do
      [] ->
        :ok

      _ ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(5)
          poll_registry(registry, key, deadline)
        else
          :timeout
        end
    end
  end
end
