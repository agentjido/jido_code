defmodule JidoCode.Session.SupervisorTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.Supervisor, as: SessionSupervisor

  @registry JidoCode.SessionProcessRegistry

  setup do
    setup_session_registry("session_sup_test")
  end

  describe "start_link/1" do
    test "starts supervisor successfully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = SessionSupervisor.start_link(session: session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      Supervisor.stop(pid)
    end

    test "registers in SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = SessionSupervisor.start_link(session: session)

      # Should be findable via Registry
      assert [{^pid, _}] = Registry.lookup(@registry, {:session, session.id})

      # Cleanup
      Supervisor.stop(pid)
    end

    test "can be found by session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, expected_pid} = SessionSupervisor.start_link(session: session)

      # Lookup via Registry
      [{pid, _}] = Registry.lookup(@registry, {:session, session.id})
      assert pid == expected_pid

      # Cleanup
      Supervisor.stop(expected_pid)
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        SessionSupervisor.start_link([])
      end
    end

    test "fails for duplicate session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid1} = SessionSupervisor.start_link(session: session)

      # Second start with same session should fail
      assert {:error, {:already_started, ^pid1}} = SessionSupervisor.start_link(session: session)

      # Cleanup
      Supervisor.stop(pid1)
    end
  end

  describe "child_spec/1" do
    test "returns correct specification", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      spec = SessionSupervisor.child_spec(session: session)

      assert spec.id == {:session_supervisor, session.id}
      assert spec.start == {SessionSupervisor, :start_link, [[session: session]]}
      assert spec.type == :supervisor
      assert spec.restart == :temporary
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        SessionSupervisor.child_spec([])
      end
    end
  end

  describe "init/1" do
    test "initializes with :one_for_all strategy", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Start to get actual init behavior
      {:ok, pid} = SessionSupervisor.start_link(session: session)

      # Check supervisor info
      info = Supervisor.count_children(pid)
      assert is_map(info)
      # Now has 2 children: Manager and State
      assert info.active == 2
      assert info.specs == 2
      assert info.workers == 2

      # Cleanup
      Supervisor.stop(pid)
    end

    test "starts Manager and State children", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = SessionSupervisor.start_link(session: session)

      children = Supervisor.which_children(pid)
      assert length(children) == 2

      # Check child IDs
      child_ids = Enum.map(children, fn {id, _, _, _} -> id end)
      assert {:session_manager, session.id} in child_ids
      assert {:session_state, session.id} in child_ids

      # Cleanup
      Supervisor.stop(pid)
    end

    test "children are registered in SessionProcessRegistry", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = SessionSupervisor.start_link(session: session)

      # Manager should be findable
      assert [{manager_pid, _}] = Registry.lookup(@registry, {:manager, session.id})
      assert is_pid(manager_pid)
      assert Process.alive?(manager_pid)

      # State should be findable
      assert [{state_pid, _}] = Registry.lookup(@registry, {:state, session.id})
      assert is_pid(state_pid)
      assert Process.alive?(state_pid)

      # They should be different processes
      assert manager_pid != state_pid
    end

    test "children have access to session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = SessionSupervisor.start_link(session: session)

      # Get Manager and verify it has session
      [{manager_pid, _}] = Registry.lookup(@registry, {:manager, session.id})
      assert {:ok, manager_session} = JidoCode.Session.Manager.get_session(manager_pid)
      assert manager_session.id == session.id

      # Get State and verify it has session
      [{state_pid, _}] = Registry.lookup(@registry, {:state, session.id})
      assert {:ok, state_session} = JidoCode.Session.State.get_session(state_pid)
      assert state_session.id == session.id
    end
  end

  describe "integration with SessionSupervisor" do
    setup %{tmp_dir: tmp_dir} do
      # Also start SessionSupervisor and SessionRegistry for integration test
      if pid = Process.whereis(JidoCode.SessionSupervisor) do
        Supervisor.stop(pid)
      end

      {:ok, sup_pid} = JidoCode.SessionSupervisor.start_link([])

      JidoCode.SessionRegistry.create_table()
      JidoCode.SessionRegistry.clear()

      on_exit(fn ->
        JidoCode.SessionRegistry.clear()

        if Process.alive?(sup_pid) do
          try do
            Supervisor.stop(sup_pid)
          catch
            :exit, _ -> :ok
          end
        end
      end)

      {:ok, sup_pid: sup_pid, tmp_dir: tmp_dir}
    end

    test "works with SessionSupervisor.start_session/1", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Use real Session.Supervisor instead of stub
      assert {:ok, pid} = JidoCode.SessionSupervisor.start_session(session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Should be registered
      assert [{^pid, _}] = Registry.lookup(@registry, {:session, session.id})
    end

    test "works with SessionSupervisor.stop_session/1", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = JidoCode.SessionSupervisor.start_session(session)
      assert Process.alive?(pid)

      assert :ok = JidoCode.SessionSupervisor.stop_session(session.id)

      # Wait for process to terminate
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 100
    end

    test "works with SessionSupervisor.find_session_pid/1", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, expected_pid} = JidoCode.SessionSupervisor.start_session(session)

      assert {:ok, ^expected_pid} = JidoCode.SessionSupervisor.find_session_pid(session.id)
    end

    test "works with SessionSupervisor.session_running?/1", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, _pid} = JidoCode.SessionSupervisor.start_session(session)

      assert JidoCode.SessionSupervisor.session_running?(session.id) == true

      :ok = JidoCode.SessionSupervisor.stop_session(session.id)

      assert JidoCode.SessionSupervisor.session_running?(session.id) == false
    end

    test "works with SessionSupervisor.create_session/1", %{tmp_dir: tmp_dir} do
      assert {:ok, session} = JidoCode.SessionSupervisor.create_session(project_path: tmp_dir)

      assert %Session{} = session
      assert JidoCode.SessionSupervisor.session_running?(session.id) == true
    end
  end

  # ============================================================================
  # Session Process Access Tests (Task 1.4.3)
  # ============================================================================

  describe "get_manager/1" do
    test "returns Manager pid for running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      assert {:ok, pid} = SessionSupervisor.get_manager(session.id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns same pid as direct Registry lookup", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      {:ok, pid} = SessionSupervisor.get_manager(session.id)
      [{registry_pid, _}] = Registry.lookup(@registry, {:manager, session.id})

      assert pid == registry_pid
    end

    test "returns error for unknown session" do
      assert {:error, :not_found} = SessionSupervisor.get_manager("unknown-session-id")
    end

    test "returns error after session stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      assert {:ok, _pid} = SessionSupervisor.get_manager(session.id)

      Supervisor.stop(sup_pid)

      # Wait for cleanup
      ref = Process.monitor(sup_pid)
      assert_receive {:DOWN, ^ref, :process, ^sup_pid, _}, 100

      assert {:error, :not_found} = SessionSupervisor.get_manager(session.id)
    end
  end

  describe "get_state/1" do
    test "returns State pid for running session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      assert {:ok, pid} = SessionSupervisor.get_state(session.id)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "returns same pid as direct Registry lookup", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      {:ok, pid} = SessionSupervisor.get_state(session.id)
      [{registry_pid, _}] = Registry.lookup(@registry, {:state, session.id})

      assert pid == registry_pid
    end

    test "returns error for unknown session" do
      assert {:error, :not_found} = SessionSupervisor.get_state("unknown-session-id")
    end

    test "returns error after session stopped", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      assert {:ok, _pid} = SessionSupervisor.get_state(session.id)

      Supervisor.stop(sup_pid)

      # Wait for cleanup
      ref = Process.monitor(sup_pid)
      assert_receive {:DOWN, ^ref, :process, ^sup_pid, _}, 100

      assert {:error, :not_found} = SessionSupervisor.get_state(session.id)
    end
  end

  describe "get_agent/1" do
    test "returns :not_implemented (stub for Phase 3)", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      assert {:error, :not_implemented} = SessionSupervisor.get_agent(session.id)
    end

    test "returns :not_implemented for unknown session too" do
      # Even unknown sessions return :not_implemented since the feature isn't built
      assert {:error, :not_implemented} = SessionSupervisor.get_agent("unknown-session-id")
    end
  end

  describe "get_manager/1 and get_state/1 return different pids" do
    test "Manager and State are different processes", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, _sup_pid} = SessionSupervisor.start_link(session: session)

      {:ok, manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, state_pid} = SessionSupervisor.get_state(session.id)

      assert manager_pid != state_pid
    end
  end

  # ============================================================================
  # Crash Recovery Tests (:one_for_all strategy)
  # ============================================================================

  describe ":one_for_all crash recovery" do
    test "Manager crash restarts State due to :one_for_all", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      # Get initial pids
      {:ok, manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, state_pid} = SessionSupervisor.get_state(session.id)

      # Kill Manager process
      Process.exit(manager_pid, :kill)

      # Wait for restart (supervisor will restart children)
      Process.sleep(50)

      # Both should have new pids (due to :one_for_all)
      {:ok, new_manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, new_state_pid} = SessionSupervisor.get_state(session.id)

      # Manager restarted
      assert new_manager_pid != manager_pid
      # State also restarted due to :one_for_all
      assert new_state_pid != state_pid

      # Both are alive
      assert Process.alive?(new_manager_pid)
      assert Process.alive?(new_state_pid)

      # Cleanup
      Supervisor.stop(sup_pid)
    end

    test "State crash restarts Manager due to :one_for_all", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      # Get initial pids
      {:ok, manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, state_pid} = SessionSupervisor.get_state(session.id)

      # Kill State process
      Process.exit(state_pid, :kill)

      # Wait for restart
      Process.sleep(50)

      # Both should have new pids (due to :one_for_all)
      {:ok, new_manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, new_state_pid} = SessionSupervisor.get_state(session.id)

      # State restarted
      assert new_state_pid != state_pid
      # Manager also restarted due to :one_for_all
      assert new_manager_pid != manager_pid

      # Both are alive
      assert Process.alive?(new_manager_pid)
      assert Process.alive?(new_state_pid)

      # Cleanup
      Supervisor.stop(sup_pid)
    end

    test "Registry entries remain consistent after crash restart", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      # Kill Manager to trigger restart
      {:ok, manager_pid} = SessionSupervisor.get_manager(session.id)
      Process.exit(manager_pid, :kill)

      # Wait for restart
      Process.sleep(50)

      # Registry lookups should return the new pids
      {:ok, new_manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, new_state_pid} = SessionSupervisor.get_state(session.id)

      # Direct Registry lookup should match helper function results
      [{registry_manager, _}] = Registry.lookup(@registry, {:manager, session.id})
      [{registry_state, _}] = Registry.lookup(@registry, {:state, session.id})

      assert new_manager_pid == registry_manager
      assert new_state_pid == registry_state

      # Cleanup
      Supervisor.stop(sup_pid)
    end

    test "children still have session after restart", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, sup_pid} = SessionSupervisor.start_link(session: session)

      # Kill Manager to trigger restart
      {:ok, manager_pid} = SessionSupervisor.get_manager(session.id)
      Process.exit(manager_pid, :kill)

      # Wait for restart
      Process.sleep(50)

      # Get new pids
      {:ok, new_manager_pid} = SessionSupervisor.get_manager(session.id)
      {:ok, new_state_pid} = SessionSupervisor.get_state(session.id)

      # Both should still have the session
      assert {:ok, manager_session} = JidoCode.Session.Manager.get_session(new_manager_pid)
      assert {:ok, state_session} = JidoCode.Session.State.get_session(new_state_pid)

      assert manager_session.id == session.id
      assert state_session.id == session.id

      # Cleanup
      Supervisor.stop(sup_pid)
    end
  end
end
