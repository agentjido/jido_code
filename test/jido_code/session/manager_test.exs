defmodule JidoCode.Session.ManagerTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.Manager

  @registry JidoCode.SessionProcessRegistry

  setup do
    setup_session_registry("manager_test")
  end

  describe "start_link/1" do
    test "starts manager successfully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = Manager.start_link(session: session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "registers in SessionProcessRegistry with :manager key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      # Should be findable via Registry with :manager key
      assert [{^pid, _}] = Registry.lookup(@registry, {:manager, session.id})

      # Cleanup
      GenServer.stop(pid)
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        Manager.start_link([])
      end
    end

    test "fails for duplicate session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid1} = Manager.start_link(session: session)

      # Second start with same session should fail
      assert {:error, {:already_started, ^pid1}} = Manager.start_link(session: session)

      # Cleanup
      GenServer.stop(pid1)
    end
  end

  describe "child_spec/1" do
    test "returns correct specification", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      spec = Manager.child_spec(session: session)

      assert spec.id == {:session_manager, session.id}
      assert spec.start == {Manager, :start_link, [[session: session]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "get_session/1" do
    test "returns the session struct", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = Manager.start_link(session: session)

      assert {:ok, returned_session} = Manager.get_session(pid)
      assert returned_session.id == session.id
      assert returned_session.project_path == session.project_path

      # Cleanup
      GenServer.stop(pid)
    end
  end
end
