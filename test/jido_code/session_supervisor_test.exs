defmodule JidoCode.SessionSupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.SessionSupervisor

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
end
