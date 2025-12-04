defmodule JidoCode.SessionSupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionSupervisorStub

  describe "start_link/1" do
    test "starts the supervisor successfully" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      assert {:ok, pid} = SessionSupervisor.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      Supervisor.stop(pid)
    end

    test "registers the supervisor with module name" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, pid} = SessionSupervisor.start_link([])

      assert Process.whereis(SessionSupervisor) == pid

      # Cleanup
      Supervisor.stop(pid)
    end

    test "returns error when already started" do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, _pid} = SessionSupervisor.start_link([])

      # Attempting to start again should fail
      assert {:error, {:already_started, _}} = SessionSupervisor.start_link([])

      # Cleanup
      Supervisor.stop(Process.whereis(SessionSupervisor))
    end
  end

  describe "init/1" do
    test "initializes with :one_for_one strategy" do
      # The init callback returns the supervisor spec
      assert {:ok, spec} = SessionSupervisor.init([])

      # DynamicSupervisor.init returns a tuple with flags
      assert is_map(spec)
      assert spec.strategy == :one_for_one
    end

    test "ignores options" do
      # Options are accepted but not used currently
      assert {:ok, _spec} = SessionSupervisor.init(some: :option)
    end
  end

  describe "supervisor behavior" do
    setup do
      # Stop if already running from application
      if pid = Process.whereis(SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, pid} = SessionSupervisor.start_link([])

      on_exit(fn ->
        # Only stop if the process is still alive and registered
        if Process.alive?(pid) do
          try do
            Supervisor.stop(pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, pid: pid}
    end

    test "is a DynamicSupervisor", %{pid: pid} do
      # Check the supervisor info
      info = DynamicSupervisor.count_children(pid)
      assert is_map(info)
      assert Map.has_key?(info, :active)
      assert Map.has_key?(info, :specs)
      assert Map.has_key?(info, :supervisors)
      assert Map.has_key?(info, :workers)
    end

    test "starts with no children", %{pid: pid} do
      info = DynamicSupervisor.count_children(pid)
      assert info.active == 0
    end

    test "can list children (empty initially)", %{pid: pid} do
      children = DynamicSupervisor.which_children(pid)
      assert children == []
    end
  end

  describe "child_spec/1" do
    test "returns correct child specification" do
      spec = SessionSupervisor.child_spec([])

      assert spec.id == SessionSupervisor
      assert spec.start == {SessionSupervisor, :start_link, [[]]}
      assert spec.type == :supervisor
    end
  end

  # ============================================================================
  # Session Lifecycle Tests (Task 1.3.2)
  # ============================================================================

  describe "start_session/1" do
    setup do
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
      tmp_dir = Path.join(System.tmp_dir!(), "session_sup_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
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
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "starts a session and returns pid", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "registers session in SessionRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Session should be in registry
      assert {:ok, registered} = SessionRegistry.lookup(session.id)
      assert registered.id == session.id
      assert registered.project_path == tmp_dir
    end

    test "registers session process in SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Process should be findable via Registry
      assert [{^pid, _}] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})
    end

    test "fails with :session_limit_reached when limit exceeded", %{tmp_dir: tmp_dir} do
      # Set low limit for testing
      original = Application.get_env(:jido_code, :max_sessions)
      Application.put_env(:jido_code, :max_sessions, 2)

      on_exit(fn ->
        if original do
          Application.put_env(:jido_code, :max_sessions, original)
        else
          Application.delete_env(:jido_code, :max_sessions)
        end
      end)

      # Create 2 sessions to hit limit
      dir1 = Path.join(tmp_dir, "project1")
      dir2 = Path.join(tmp_dir, "project2")
      dir3 = Path.join(tmp_dir, "project3")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)
      File.mkdir_p!(dir3)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)
      {:ok, s3} = Session.new(project_path: dir3)

      {:ok, _} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, _} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      # Third should fail
      assert {:error, :session_limit_reached} = SessionSupervisor.start_session(s3, supervisor_module: SessionSupervisorStub)
    end

    test "fails with :session_exists for duplicate ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      # Same session again should fail
      assert {:error, :session_exists} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)
    end

    test "fails with :project_already_open for duplicate path", %{tmp_dir: tmp_dir} do
      {:ok, session1} = Session.new(project_path: tmp_dir)
      {:ok, session2} = Session.new(project_path: tmp_dir)

      {:ok, _} = SessionSupervisor.start_session(session1, supervisor_module: SessionSupervisorStub)

      # Different session, same path should fail
      assert {:error, :project_already_open} = SessionSupervisor.start_session(session2, supervisor_module: SessionSupervisorStub)
    end

    test "increments DynamicSupervisor child count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0

      {:ok, _} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1
    end
  end

  describe "stop_session/1" do
    setup do
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
      tmp_dir = Path.join(System.tmp_dir!(), "session_sup_stop_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
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
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "stops a running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert Process.alive?(pid)

      assert :ok = SessionSupervisor.stop_session(session.id)

      # Give it a moment to terminate
      :timer.sleep(10)
      refute Process.alive?(pid)
    end

    test "unregisters session from SessionRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert {:ok, _} = SessionRegistry.lookup(session.id)

      :ok = SessionSupervisor.stop_session(session.id)

      assert {:error, :not_found} = SessionRegistry.lookup(session.id)
    end

    test "removes process from SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert [{_, _}] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})

      :ok = SessionSupervisor.stop_session(session.id)

      # Give it a moment to terminate
      :timer.sleep(10)
      assert [] = Registry.lookup(JidoCode.SessionProcessRegistry, {:session, session.id})
    end

    test "decrements DynamicSupervisor child count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1

      :ok = SessionSupervisor.stop_session(session.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0
    end

    test "returns :error for non-existent session" do
      assert {:error, :not_found} = SessionSupervisor.stop_session("non-existent-id")
    end

    test "can stop multiple sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, _} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, _} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 2
      assert SessionRegistry.count() == 2

      :ok = SessionSupervisor.stop_session(s1.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 1
      assert SessionRegistry.count() == 1

      :ok = SessionSupervisor.stop_session(s2.id)

      assert DynamicSupervisor.count_children(SessionSupervisor).active == 0
      assert SessionRegistry.count() == 0
    end
  end

  # ============================================================================
  # Session Process Lookup Tests (Task 1.3.3)
  # ============================================================================

  describe "find_session_pid/1" do
    setup do
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
      tmp_dir = Path.join(System.tmp_dir!(), "session_find_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
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
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "finds registered session pid", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, expected_pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert {:ok, pid} = SessionSupervisor.find_session_pid(session.id)
      assert pid == expected_pid
    end

    test "returns error for unknown session" do
      assert {:error, :not_found} = SessionSupervisor.find_session_pid("unknown-session-id")
    end

    test "returns error after session is stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      :ok = SessionSupervisor.stop_session(session.id)

      assert {:error, :not_found} = SessionSupervisor.find_session_pid(session.id)
    end
  end

  describe "list_session_pids/0" do
    setup do
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
      tmp_dir = Path.join(System.tmp_dir!(), "session_list_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
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
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "returns empty list when no sessions running" do
      assert SessionSupervisor.list_session_pids() == []
    end

    test "returns pids for running sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, pid1} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, pid2} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      pids = SessionSupervisor.list_session_pids()

      assert length(pids) == 2
      assert pid1 in pids
      assert pid2 in pids
    end

    test "reflects stopped sessions", %{tmp_dir: tmp_dir} do
      dir1 = Path.join(tmp_dir, "proj1")
      dir2 = Path.join(tmp_dir, "proj2")
      File.mkdir_p!(dir1)
      File.mkdir_p!(dir2)

      {:ok, s1} = Session.new(project_path: dir1)
      {:ok, s2} = Session.new(project_path: dir2)

      {:ok, _pid1} = SessionSupervisor.start_session(s1, supervisor_module: SessionSupervisorStub)
      {:ok, pid2} = SessionSupervisor.start_session(s2, supervisor_module: SessionSupervisorStub)

      assert length(SessionSupervisor.list_session_pids()) == 2

      :ok = SessionSupervisor.stop_session(s1.id)

      pids = SessionSupervisor.list_session_pids()
      assert length(pids) == 1
      assert pid2 in pids
    end
  end

  describe "session_running?/1" do
    setup do
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
      tmp_dir = Path.join(System.tmp_dir!(), "session_running_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
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
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "returns true for running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert SessionSupervisor.session_running?(session.id) == true
    end

    test "returns false for unknown session" do
      assert SessionSupervisor.session_running?("unknown-session-id") == false
    end

    test "returns false after session is stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _pid} = SessionSupervisor.start_session(session, supervisor_module: SessionSupervisorStub)

      assert SessionSupervisor.session_running?(session.id) == true

      :ok = SessionSupervisor.stop_session(session.id)

      assert SessionSupervisor.session_running?(session.id) == false
    end
  end
end
