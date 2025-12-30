defmodule JidoCode.Memory.SupervisorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.Supervisor, as: MemorySupervisor
  alias JidoCode.Memory.LongTerm.StoreManager

  # Use unique paths for each test to avoid conflicts
  setup do
    base_path = Path.join(System.tmp_dir!(), "memory_supervisor_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(base_path)

    on_exit(fn ->
      File.rm_rf!(base_path)
    end)

    %{base_path: base_path}
  end

  # Helper to generate unique names for isolated testing
  defp unique_names do
    rand = :rand.uniform(1_000_000)
    %{
      supervisor: :"memory_supervisor_#{rand}",
      store_manager: :"store_manager_#{rand}"
    }
  end

  # =============================================================================
  # Supervisor Startup Tests
  # =============================================================================

  describe "start_link/1" do
    test "starts supervisor with custom name", %{base_path: base_path} do
      names = unique_names()

      # Pass both supervisor name and StoreManager name to avoid conflicts
      {:ok, pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      assert Process.alive?(pid)

      # Clean up
      Supervisor.stop(pid)
    end

    test "starts with StoreManager as child", %{base_path: base_path} do
      names = unique_names()

      {:ok, pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      # Check that StoreManager is running as a child
      children = Supervisor.which_children(pid)
      assert length(children) == 1

      [{child_id, child_pid, child_type, child_modules}] = children
      assert child_id == StoreManager
      assert is_pid(child_pid)
      assert child_type == :worker
      assert child_modules == [StoreManager]

      # Clean up
      Supervisor.stop(pid)
    end

    test "passes options to StoreManager", %{base_path: base_path} do
      names = unique_names()

      {:ok, sup_pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      # Get the StoreManager child pid
      [{StoreManager, store_pid, :worker, _}] = Supervisor.which_children(sup_pid)

      # Verify StoreManager received the base_path option
      actual_base_path = StoreManager.base_path(store_pid)
      assert actual_base_path == Path.expand(base_path)

      # Clean up
      Supervisor.stop(sup_pid)
    end
  end

  # =============================================================================
  # StoreManager Child Tests
  # =============================================================================

  describe "StoreManager child" do
    test "StoreManager is functional after supervisor starts", %{base_path: base_path} do
      names = unique_names()

      {:ok, sup_pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      # Get the StoreManager child pid
      [{StoreManager, store_pid, :worker, _}] = Supervisor.which_children(sup_pid)

      # Test StoreManager functionality
      session_id = "test-session-#{:rand.uniform(1_000_000)}"
      {:ok, store} = StoreManager.get_or_create(session_id, store_pid)
      # Store is an ETS table reference (atom for named tables)
      assert store != nil

      # Verify it's tracked
      assert StoreManager.open?(session_id, store_pid)

      # Clean up
      StoreManager.close_all(store_pid)
      Supervisor.stop(sup_pid)
    end

    test "StoreManager restarts on crash", %{base_path: base_path} do
      names = unique_names()

      {:ok, sup_pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      # Get the original StoreManager pid
      [{StoreManager, original_pid, :worker, _}] = Supervisor.which_children(sup_pid)
      original_ref = Process.monitor(original_pid)

      # Kill the StoreManager
      Process.exit(original_pid, :kill)

      # Wait for it to be killed
      assert_receive {:DOWN, ^original_ref, :process, ^original_pid, :killed}, 1000

      # Give supervisor time to restart the child
      Process.sleep(100)

      # Verify a new StoreManager is running
      [{StoreManager, new_pid, :worker, _}] = Supervisor.which_children(sup_pid)
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)

      # Verify the new StoreManager is functional
      session_id = "post-restart-session-#{:rand.uniform(1_000_000)}"
      {:ok, _store} = StoreManager.get_or_create(session_id, new_pid)
      assert StoreManager.open?(session_id, new_pid)

      # Clean up
      StoreManager.close_all(new_pid)
      Supervisor.stop(sup_pid)
    end
  end

  # =============================================================================
  # Supervisor Behavior Tests
  # =============================================================================

  describe "supervisor behavior" do
    test "supervisor handles StoreManager failure gracefully", %{base_path: base_path} do
      names = unique_names()

      {:ok, sup_pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      sup_ref = Process.monitor(sup_pid)

      # Kill StoreManager multiple times to test restart behavior
      for _ <- 1..3 do
        # Get current StoreManager pid
        [{StoreManager, store_pid, :worker, _}] = Supervisor.which_children(sup_pid)

        ref = Process.monitor(store_pid)
        Process.exit(store_pid, :kill)

        # Wait for it to die (either killed or noproc if already dead)
        receive do
          {:DOWN, ^ref, :process, ^store_pid, _reason} -> :ok
        after
          1000 -> flunk("StoreManager did not die within timeout")
        end

        # Give supervisor time to restart
        Process.sleep(50)
      end

      # Supervisor should still be running
      refute_receive {:DOWN, ^sup_ref, :process, ^sup_pid, _}, 100
      assert Process.alive?(sup_pid)

      # Verify a StoreManager is still running
      [{StoreManager, final_pid, :worker, _}] = Supervisor.which_children(sup_pid)
      assert Process.alive?(final_pid)

      # Clean up
      Supervisor.stop(sup_pid)
    end

    test "supervisor stops cleanly", %{base_path: base_path} do
      names = unique_names()

      {:ok, sup_pid} =
        MemorySupervisor.start_link(
          name: names.supervisor,
          base_path: base_path,
          store_name: names.store_manager
        )

      # Get StoreManager pid
      [{StoreManager, store_pid, :worker, _}] = Supervisor.which_children(sup_pid)

      # Create some stores to ensure cleanup
      session_id = "cleanup-test-#{:rand.uniform(1_000_000)}"
      {:ok, _} = StoreManager.get_or_create(session_id, store_pid)

      # Monitor both processes
      sup_ref = Process.monitor(sup_pid)
      store_ref = Process.monitor(store_pid)

      # Stop supervisor
      :ok = Supervisor.stop(sup_pid)

      # Both should be down
      assert_receive {:DOWN, ^sup_ref, :process, ^sup_pid, _}, 1000
      assert_receive {:DOWN, ^store_ref, :process, ^store_pid, _}, 1000
    end
  end

  # =============================================================================
  # Application Integration Tests
  # =============================================================================

  describe "application integration" do
    test "supervisor is started in application supervision tree" do
      # The application should already be started by the test framework
      # Check that our supervisor is in the tree
      children = Supervisor.which_children(JidoCode.Supervisor)

      # Find Memory.Supervisor in the children
      memory_sup = Enum.find(children, fn
        {JidoCode.Memory.Supervisor, _pid, :supervisor, _modules} -> true
        _ -> false
      end)

      assert memory_sup != nil, "Memory.Supervisor should be in application supervision tree"

      {JidoCode.Memory.Supervisor, sup_pid, :supervisor, _} = memory_sup
      assert is_pid(sup_pid)
      assert Process.alive?(sup_pid)
    end

    test "StoreManager is accessible via default name after application start" do
      # After application starts, StoreManager should be available via default name
      # Create a session using the default StoreManager
      session_id = "app-integration-test-#{:rand.uniform(1_000_000)}"

      {:ok, store} = StoreManager.get_or_create(session_id)
      # Store is an ETS table (named table returns atom)
      assert store != nil

      # Clean up
      :ok = StoreManager.close(session_id)
    end
  end
end
