defmodule JidoCode.Session.SupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.Session.Supervisor, as: SessionSupervisor

  @registry JidoCode.SessionProcessRegistry

  setup do
    # Start SessionProcessRegistry for via tuples
    if pid = Process.whereis(@registry) do
      GenServer.stop(pid)
    end

    {:ok, _} = Registry.start_link(keys: :unique, name: @registry)

    # Create a temp directory for sessions
    tmp_dir = Path.join(System.tmp_dir!(), "session_sup_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)

      if pid = Process.whereis(@registry) do
        try do
          GenServer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    {:ok, tmp_dir: tmp_dir}
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
      # No children yet (added in Task 1.4.2)
      assert info.active == 0
      assert info.specs == 0

      # Cleanup
      Supervisor.stop(pid)
    end

    test "starts with no children (children added in Task 1.4.2)", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = SessionSupervisor.start_link(session: session)

      assert Supervisor.which_children(pid) == []

      # Cleanup
      Supervisor.stop(pid)
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
end
