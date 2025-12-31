defmodule JidoCode.Memory.LongTerm.StoreManagerTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.LongTerm.StoreManager

  # Use a unique base path for each test to avoid conflicts
  setup do
    base_path = Path.join(System.tmp_dir!(), "store_manager_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(base_path)

    # Start a StoreManager with a unique name for this test
    name = :"store_manager_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

    on_exit(fn ->
      # Clean up
      if Process.alive?(pid) do
        StoreManager.close_all(name)
        GenServer.stop(pid)
      end

      File.rm_rf!(base_path)
    end)

    %{server: name, base_path: base_path, pid: pid}
  end

  # ============================================================================
  # start_link/1 Tests
  # ============================================================================

  describe "start_link/1" do
    test "starts GenServer with default base_path" do
      name = :"store_manager_default_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = StoreManager.start_link(name: name)

      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end

    test "accepts custom base_path option", %{base_path: base_path} do
      name = :"store_manager_custom_#{:rand.uniform(1_000_000)}"
      custom_path = Path.join(base_path, "custom")

      {:ok, pid} = StoreManager.start_link(base_path: custom_path, name: name)

      assert Process.alive?(pid)
      assert StoreManager.base_path(name) == custom_path

      GenServer.stop(pid)
    end

    test "accepts custom config options", %{base_path: base_path} do
      name = :"store_manager_config_#{:rand.uniform(1_000_000)}"

      {:ok, pid} =
        StoreManager.start_link(
          base_path: base_path,
          name: name,
          config: %{create_if_missing: false}
        )

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "creates base directory if missing" do
      name = :"store_manager_mkdir_#{:rand.uniform(1_000_000)}"
      new_path = Path.join(System.tmp_dir!(), "new_store_dir_#{:rand.uniform(1_000_000)}")

      refute File.exists?(new_path)

      {:ok, pid} = StoreManager.start_link(base_path: new_path, name: name)

      assert File.exists?(new_path)
      assert File.dir?(new_path)

      GenServer.stop(pid)
      File.rm_rf!(new_path)
    end
  end

  # ============================================================================
  # get_or_create/1 Tests
  # ============================================================================

  describe "get_or_create/1" do
    test "creates new store for unknown session", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      refute StoreManager.open?(session_id, server)

      {:ok, store} = StoreManager.get_or_create(session_id, server)

      assert store != nil
      assert StoreManager.open?(session_id, server)
    end

    test "returns existing store for known session", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, store1} = StoreManager.get_or_create(session_id, server)
      {:ok, store2} = StoreManager.get_or_create(session_id, server)

      assert store1 == store2
    end

    test "creates store directory if missing", %{server: server, base_path: base_path} do
      session_id = "session-#{:rand.uniform(1_000_000)}"
      expected_path = StoreManager.store_path(base_path, session_id)

      refute File.exists?(expected_path)

      {:ok, _store} = StoreManager.get_or_create(session_id, server)

      assert File.exists?(expected_path)
      assert File.dir?(expected_path)
    end

    test "returns ETS table that can be used for storage", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, store} = StoreManager.get_or_create(session_id, server)

      # Verify we can use the ETS table
      :ets.insert(store, {"key1", "value1"})
      assert [{"key1", "value1"}] = :ets.lookup(store, "key1")
    end
  end

  # ============================================================================
  # get/1 Tests
  # ============================================================================

  describe "get/1" do
    test "returns store for known session", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, created_store} = StoreManager.get_or_create(session_id, server)
      {:ok, retrieved_store} = StoreManager.get(session_id, server)

      assert created_store == retrieved_store
    end

    test "returns {:error, :not_found} for unknown session", %{server: server} do
      session_id = "unknown-session-#{:rand.uniform(1_000_000)}"

      assert {:error, :not_found} = StoreManager.get(session_id, server)
    end

    test "does not auto-create store", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:error, :not_found} = StoreManager.get(session_id, server)

      refute StoreManager.open?(session_id, server)
    end
  end

  # ============================================================================
  # close/1 Tests
  # ============================================================================

  describe "close/1" do
    test "closes and removes store from state", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, _store} = StoreManager.get_or_create(session_id, server)
      assert StoreManager.open?(session_id, server)

      :ok = StoreManager.close(session_id, server)

      refute StoreManager.open?(session_id, server)
      assert {:error, :not_found} = StoreManager.get(session_id, server)
    end

    test "handles already-closed session gracefully", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      # Close a session that was never opened
      assert :ok = StoreManager.close(session_id, server)

      # Close a session that was already closed
      {:ok, _store} = StoreManager.get_or_create(session_id, server)
      :ok = StoreManager.close(session_id, server)
      assert :ok = StoreManager.close(session_id, server)
    end

    test "deletes ETS table", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, store} = StoreManager.get_or_create(session_id, server)

      # Verify table exists
      assert :ets.info(store) != :undefined

      :ok = StoreManager.close(session_id, server)

      # Verify table is deleted
      assert :ets.info(store) == :undefined
    end
  end

  # ============================================================================
  # close_all/0 Tests
  # ============================================================================

  describe "close_all/0" do
    test "closes all open stores", %{server: server} do
      session_ids =
        for i <- 1..5 do
          session_id = "session-#{i}-#{:rand.uniform(1_000_000)}"
          {:ok, _store} = StoreManager.get_or_create(session_id, server)
          session_id
        end

      assert length(StoreManager.list_open(server)) == 5

      :ok = StoreManager.close_all(server)

      assert StoreManager.list_open(server) == []

      for session_id <- session_ids do
        refute StoreManager.open?(session_id, server)
      end
    end

    test "handles empty stores map", %{server: server} do
      assert StoreManager.list_open(server) == []
      assert :ok = StoreManager.close_all(server)
    end
  end

  # ============================================================================
  # list_open/0 Tests
  # ============================================================================

  describe "list_open/0" do
    test "returns list of open session ids", %{server: server} do
      session1 = "session-1-#{:rand.uniform(1_000_000)}"
      session2 = "session-2-#{:rand.uniform(1_000_000)}"
      session3 = "session-3-#{:rand.uniform(1_000_000)}"

      {:ok, _} = StoreManager.get_or_create(session1, server)
      {:ok, _} = StoreManager.get_or_create(session2, server)
      {:ok, _} = StoreManager.get_or_create(session3, server)

      open_sessions = StoreManager.list_open(server)

      assert length(open_sessions) == 3
      assert session1 in open_sessions
      assert session2 in open_sessions
      assert session3 in open_sessions
    end

    test "returns empty list when no stores are open", %{server: server} do
      assert StoreManager.list_open(server) == []
    end

    test "updates after close", %{server: server} do
      session1 = "session-1-#{:rand.uniform(1_000_000)}"
      session2 = "session-2-#{:rand.uniform(1_000_000)}"

      {:ok, _} = StoreManager.get_or_create(session1, server)
      {:ok, _} = StoreManager.get_or_create(session2, server)

      assert length(StoreManager.list_open(server)) == 2

      StoreManager.close(session1, server)

      open_sessions = StoreManager.list_open(server)
      assert length(open_sessions) == 1
      assert session2 in open_sessions
      refute session1 in open_sessions
    end
  end

  # ============================================================================
  # open?/1 Tests
  # ============================================================================

  describe "open?/1" do
    test "returns true for open session", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, _} = StoreManager.get_or_create(session_id, server)

      assert StoreManager.open?(session_id, server)
    end

    test "returns false for unknown session", %{server: server} do
      refute StoreManager.open?("unknown-session", server)
    end

    test "returns false after close", %{server: server} do
      session_id = "session-#{:rand.uniform(1_000_000)}"

      {:ok, _} = StoreManager.get_or_create(session_id, server)
      assert StoreManager.open?(session_id, server)

      StoreManager.close(session_id, server)
      refute StoreManager.open?(session_id, server)
    end
  end

  # ============================================================================
  # base_path/0 Tests
  # ============================================================================

  describe "base_path/0" do
    test "returns configured base path", %{server: server, base_path: base_path} do
      assert StoreManager.base_path(server) == base_path
    end
  end

  # ============================================================================
  # store_path/2 Tests
  # ============================================================================

  describe "store_path/2" do
    test "generates correct session-specific path" do
      base = "/home/user/.jido_code/memory_stores"
      session_id = "abc123"

      expected = "/home/user/.jido_code/memory_stores/session_abc123"
      assert StoreManager.store_path(base, session_id) == expected
    end

    test "handles special characters in session id" do
      base = "/tmp/stores"
      session_id = "session-with-dashes-123"

      expected = "/tmp/stores/session_session-with-dashes-123"
      assert StoreManager.store_path(base, session_id) == expected
    end
  end

  # ============================================================================
  # Store Isolation Tests
  # ============================================================================

  describe "store isolation" do
    test "stores are isolated per session", %{server: server} do
      session1 = "session-1-#{:rand.uniform(1_000_000)}"
      session2 = "session-2-#{:rand.uniform(1_000_000)}"

      {:ok, store1} = StoreManager.get_or_create(session1, server)
      {:ok, store2} = StoreManager.get_or_create(session2, server)

      # Insert different data into each store
      :ets.insert(store1, {"key", "value1"})
      :ets.insert(store2, {"key", "value2"})

      # Verify data is isolated
      assert [{"key", "value1"}] = :ets.lookup(store1, "key")
      assert [{"key", "value2"}] = :ets.lookup(store2, "key")
    end

    test "store paths are isolated per session", %{server: server, base_path: base_path} do
      session1 = "session-1-#{:rand.uniform(1_000_000)}"
      session2 = "session-2-#{:rand.uniform(1_000_000)}"

      {:ok, _} = StoreManager.get_or_create(session1, server)
      {:ok, _} = StoreManager.get_or_create(session2, server)

      path1 = StoreManager.store_path(base_path, session1)
      path2 = StoreManager.store_path(base_path, session2)

      assert path1 != path2
      assert File.exists?(path1)
      assert File.exists?(path2)
    end
  end

  # ============================================================================
  # Concurrent Access Tests
  # ============================================================================

  describe "concurrent access" do
    test "concurrent get_or_create calls for same session return same store", %{server: server} do
      session_id = "session-concurrent-#{:rand.uniform(1_000_000)}"

      # Spawn multiple processes trying to get_or_create the same session
      tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            StoreManager.get_or_create(session_id, server)
          end)
        end

      results = Task.await_many(tasks)

      # All should succeed
      stores = Enum.map(results, fn {:ok, store} -> store end)

      # All should return the same store reference
      assert Enum.all?(stores, fn store -> store == hd(stores) end)
    end

    test "concurrent operations on different sessions work correctly", %{server: server} do
      # Create tasks for different sessions
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            session_id = "session-#{i}-#{:rand.uniform(1_000_000)}"
            {:ok, store} = StoreManager.get_or_create(session_id, server)
            :ets.insert(store, {"data", i})
            {session_id, store}
          end)
        end

      results = Task.await_many(tasks)

      # Verify all sessions were created
      assert length(results) == 10

      # Verify all stores have correct data
      for {_session_id, store} <- results do
        assert :ets.info(store) != :undefined
      end
    end
  end

  # ============================================================================
  # terminate/2 Tests
  # ============================================================================

  describe "terminate/2" do
    test "closes all stores on shutdown" do
      name = :"store_manager_terminate_#{:rand.uniform(1_000_000)}"
      base_path = Path.join(System.tmp_dir!(), "terminate_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(base_path)

      {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

      # Create some stores
      {:ok, store1} = StoreManager.get_or_create("session-1", name)
      {:ok, store2} = StoreManager.get_or_create("session-2", name)

      # Verify stores exist
      assert :ets.info(store1) != :undefined
      assert :ets.info(store2) != :undefined

      # Stop the GenServer (triggers terminate)
      GenServer.stop(pid)

      # Verify stores are closed
      assert :ets.info(store1) == :undefined
      assert :ets.info(store2) == :undefined

      File.rm_rf!(base_path)
    end
  end
end
