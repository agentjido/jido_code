defmodule JidoCode.MemoryTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Memory.LongTerm.StoreManager

  # Use a unique base path for each test to avoid conflicts
  setup do
    base_path = Path.join(System.tmp_dir!(), "memory_facade_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(base_path)

    # Start a StoreManager with a unique name for this test
    name = :"store_manager_#{:rand.uniform(1_000_000)}"
    {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

    # Store the original StoreManager name and replace it for tests
    # We need to use the test-specific manager
    session_id = "test-session-#{:rand.uniform(1_000_000)}"

    on_exit(fn ->
      if Process.alive?(pid) do
        StoreManager.close_all(name)
        GenServer.stop(pid)
      end

      File.rm_rf!(base_path)
    end)

    %{store_manager: name, session_id: session_id, base_path: base_path}
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp create_memory(session_id, overrides \\ %{}) do
    Map.merge(
      %{
        id: "mem-#{:rand.uniform(1_000_000)}",
        content: "Test memory content",
        memory_type: :fact,
        confidence: 0.85,
        source_type: :agent,
        session_id: session_id,
        created_at: DateTime.utc_now()
      },
      overrides
    )
  end

  # Helper to persist using the test store manager
  defp persist_with_manager(memory, session_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.persist(memory, store)
  end

  # Helper to query using the test store manager
  defp query_with_manager(session_id, store_manager, opts \\ []) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.query_all(store, session_id, opts)
  end

  # Helper to query by type using the test store manager
  defp query_by_type_with_manager(session_id, memory_type, store_manager, opts \\ []) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.query_by_type(store, session_id, memory_type, opts)
  end

  # Helper to get by id using the test store manager (with session ownership check)
  defp get_with_manager(session_id, memory_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.query_by_id(store, session_id, memory_id)
  end

  # Helper to supersede using the test store manager
  defp supersede_with_manager(session_id, old_id, new_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.supersede(store, session_id, old_id, new_id)
  end

  # Helper to count using the test store manager
  defp count_with_manager(session_id, store_manager, opts \\ []) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.count(store, session_id, opts)
  end

  # Helper to record access using the test store manager
  defp record_access_with_manager(session_id, memory_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    JidoCode.Memory.LongTerm.TripleStoreAdapter.record_access(store, session_id, memory_id)
  end

  # =============================================================================
  # persist/2 Tests
  # =============================================================================

  describe "persist/2" do
    test "stores memory via StoreManager and Adapter", %{session_id: session_id, store_manager: manager} do
      memory = create_memory(session_id, %{id: "persist-test-1"})

      {:ok, id} = persist_with_manager(memory, session_id, manager)

      assert id == "persist-test-1"

      # Verify it was stored
      {:ok, retrieved} = get_with_manager(session_id, "persist-test-1", manager)
      assert retrieved.content == "Test memory content"
    end

    test "creates store if not exists", %{session_id: session_id, store_manager: manager} do
      # Verify store doesn't exist yet
      refute StoreManager.open?(session_id, manager)

      memory = create_memory(session_id, %{id: "new-store-mem"})
      {:ok, _id} = persist_with_manager(memory, session_id, manager)

      # Verify store was created
      assert StoreManager.open?(session_id, manager)
    end

    test "stores all memory fields correctly", %{session_id: session_id, store_manager: manager} do
      timestamp = DateTime.utc_now()

      memory = %{
        id: "full-fields-mem",
        content: "Complete memory",
        memory_type: :discovery,
        confidence: 0.92,
        source_type: :tool,
        session_id: session_id,
        agent_id: "agent-123",
        project_id: "project-xyz",
        rationale: "Found during code analysis",
        evidence_refs: ["ref-1", "ref-2"],
        created_at: timestamp
      }

      {:ok, _id} = persist_with_manager(memory, session_id, manager)

      {:ok, retrieved} = get_with_manager(session_id, "full-fields-mem", manager)

      assert retrieved.content == "Complete memory"
      assert retrieved.memory_type == :discovery
      assert retrieved.confidence == 0.92
      assert retrieved.source_type == :tool
      assert retrieved.agent_id == "agent-123"
      assert retrieved.project_id == "project-xyz"
      assert retrieved.rationale == "Found during code analysis"
      assert retrieved.evidence_refs == ["ref-1", "ref-2"]
    end
  end

  # =============================================================================
  # query/2 Tests
  # =============================================================================

  describe "query/2" do
    test "returns memories for session", %{session_id: session_id, store_manager: manager} do
      for i <- 1..3 do
        memory = create_memory(session_id, %{id: "query-mem-#{i}"})
        {:ok, _} = persist_with_manager(memory, session_id, manager)
      end

      {:ok, memories} = query_with_manager(session_id, manager)

      assert length(memories) == 3
    end

    test "applies type filter", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "fact-1", memory_type: :fact}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "fact-2", memory_type: :fact}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "assumption-1", memory_type: :assumption}), session_id, manager)

      {:ok, facts} = query_with_manager(session_id, manager, type: :fact)

      assert length(facts) == 2
      assert Enum.all?(facts, &(&1.memory_type == :fact))
    end

    test "applies min_confidence filter", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "high-conf", confidence: 0.9}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "low-conf", confidence: 0.3}), session_id, manager)

      {:ok, confident} = query_with_manager(session_id, manager, min_confidence: 0.7)

      assert length(confident) == 1
      assert hd(confident).id == "high-conf"
    end

    test "applies limit option", %{session_id: session_id, store_manager: manager} do
      for i <- 1..10 do
        {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "limit-mem-#{i}"}), session_id, manager)
      end

      {:ok, limited} = query_with_manager(session_id, manager, limit: 5)

      assert length(limited) == 5
    end

    test "excludes superseded memories by default", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "active"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "superseded"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "superseded", "active", manager)

      {:ok, memories} = query_with_manager(session_id, manager)

      assert length(memories) == 1
      assert hd(memories).id == "active"
    end

    test "includes superseded with option", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "active"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "superseded"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "superseded", "active", manager)

      {:ok, memories} = query_with_manager(session_id, manager, include_superseded: true)

      assert length(memories) == 2
    end
  end

  # =============================================================================
  # query_by_type/3 Tests
  # =============================================================================

  describe "query_by_type/3" do
    test "filters by type", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "fact", memory_type: :fact}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "assumption", memory_type: :assumption}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "discovery", memory_type: :discovery}), session_id, manager)

      {:ok, facts} = query_by_type_with_manager(session_id, :fact, manager)

      assert length(facts) == 1
      assert hd(facts).memory_type == :fact
    end

    test "applies limit option", %{session_id: session_id, store_manager: manager} do
      for i <- 1..10 do
        {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "fact-#{i}", memory_type: :fact}), session_id, manager)
      end

      {:ok, limited} = query_by_type_with_manager(session_id, :fact, manager, limit: 3)

      assert length(limited) == 3
    end
  end

  # =============================================================================
  # get/2 Tests
  # =============================================================================

  describe "get/2" do
    test "retrieves single memory", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "get-test", content: "Specific memory"}), session_id, manager)

      {:ok, memory} = get_with_manager(session_id, "get-test", manager)

      assert memory.id == "get-test"
      assert memory.content == "Specific memory"
    end

    test "returns error for non-existent id", %{session_id: session_id, store_manager: manager} do
      # Ensure store exists
      {:ok, _} = StoreManager.get_or_create(session_id, manager)

      assert {:error, :not_found} = get_with_manager(session_id, "non-existent", manager)
    end
  end

  # =============================================================================
  # supersede/3 Tests
  # =============================================================================

  describe "supersede/3" do
    test "marks memory as superseded", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "old-mem"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "new-mem"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "old-mem", "new-mem", manager)

      {:ok, memory} = get_with_manager(session_id, "old-mem", manager)
      assert memory.superseded_by == "new-mem"
    end

    test "excludes superseded from normal queries", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "old"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "new"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "old", "new", manager)

      {:ok, memories} = query_with_manager(session_id, manager)

      ids = Enum.map(memories, & &1.id)
      assert "new" in ids
      refute "old" in ids
    end
  end

  # =============================================================================
  # forget/2 Tests
  # =============================================================================

  describe "forget/2" do
    test "marks memory as superseded without replacement", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "forget-me"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "forget-me", nil, manager)

      # Should be excluded from normal queries
      {:ok, memories} = query_with_manager(session_id, manager)
      assert Enum.empty?(memories)

      # But still retrievable by ID
      {:ok, memory} = get_with_manager(session_id, "forget-me", manager)
      assert memory.id == "forget-me"
    end
  end

  # =============================================================================
  # count/1 Tests
  # =============================================================================

  describe "count/1" do
    test "returns memory count", %{session_id: session_id, store_manager: manager} do
      for i <- 1..5 do
        {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "count-#{i}"}), session_id, manager)
      end

      {:ok, count} = count_with_manager(session_id, manager)

      assert count == 5
    end

    test "excludes superseded by default", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "active"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "superseded"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "superseded", "active", manager)

      {:ok, count} = count_with_manager(session_id, manager)

      assert count == 1
    end

    test "includes superseded with option", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "active"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "superseded"}), session_id, manager)

      :ok = supersede_with_manager(session_id, "superseded", "active", manager)

      {:ok, count} = count_with_manager(session_id, manager, include_superseded: true)

      assert count == 2
    end
  end

  # =============================================================================
  # record_access/2 Tests
  # =============================================================================

  describe "record_access/2" do
    test "updates access tracking", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "access-test"}), session_id, manager)

      # Verify initial state
      {:ok, before_access} = get_with_manager(session_id, "access-test", manager)
      assert before_access.access_count == 0
      assert before_access.last_accessed == nil

      # Record access
      :ok = record_access_with_manager(session_id, "access-test", manager)
      :ok = record_access_with_manager(session_id, "access-test", manager)

      {:ok, after_access} = get_with_manager(session_id, "access-test", manager)
      assert after_access.access_count == 2
      assert after_access.last_accessed != nil
    end
  end

  # =============================================================================
  # load_ontology/1 Tests
  # =============================================================================

  describe "load_ontology/1" do
    test "returns placeholder result" do
      # Currently a placeholder
      {:ok, count} = Memory.load_ontology("any-session")

      assert count == 0
    end
  end

  # =============================================================================
  # delete/2 Tests
  # =============================================================================

  describe "delete/2" do
    test "permanently removes memory from store", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "to-delete"}), session_id, manager)

      # Verify it exists
      {:ok, _} = get_with_manager(session_id, "to-delete", manager)

      # Delete it using the adapter directly (since we're using a test manager)
      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = JidoCode.Memory.LongTerm.TripleStoreAdapter.delete(store, session_id, "to-delete")

      # Verify it's gone
      assert {:error, :not_found} = get_with_manager(session_id, "to-delete", manager)
    end

    test "delete/2 removes memory from count", %{session_id: session_id, store_manager: manager} do
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "mem-1"}), session_id, manager)
      {:ok, _} = persist_with_manager(create_memory(session_id, %{id: "mem-2"}), session_id, manager)

      {:ok, count_before} = count_with_manager(session_id, manager)
      assert count_before == 2

      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = JidoCode.Memory.LongTerm.TripleStoreAdapter.delete(store, session_id, "mem-1")

      {:ok, count_after} = count_with_manager(session_id, manager)
      assert count_after == 1
    end

    test "delete/2 on non-existent memory returns ok", %{session_id: session_id, store_manager: manager} do
      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      # Should not error on deleting non-existent memory
      :ok = JidoCode.Memory.LongTerm.TripleStoreAdapter.delete(store, session_id, "non-existent")
    end
  end

  # =============================================================================
  # Session ID Validation Tests
  # =============================================================================

  describe "session ID validation" do
    test "rejects session IDs with path traversal characters", %{base_path: base_path} do
      name = :"store_manager_security_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      # These should all be rejected
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("../../../etc/passwd", name)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("session/../other", name)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("session/subdir", name)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("", name)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("session with spaces", name)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create("session.with.dots", name)
    end

    test "accepts valid session IDs", %{base_path: base_path} do
      name = :"store_manager_valid_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

      on_exit(fn ->
        if Process.alive?(pid) do
          StoreManager.close_all(name)
          GenServer.stop(pid)
        end
      end)

      # These should all be accepted
      assert {:ok, _} = StoreManager.get_or_create("session-123", name)
      assert {:ok, _} = StoreManager.get_or_create("my_session_456", name)
      assert {:ok, _} = StoreManager.get_or_create("SessionWithCaps", name)
      assert {:ok, _} = StoreManager.get_or_create("abc123", name)
    end

    test "rejects session IDs exceeding max length", %{base_path: base_path} do
      name = :"store_manager_length_#{:rand.uniform(1_000_000)}"
      {:ok, pid} = StoreManager.start_link(base_path: base_path, name: name)

      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid)
      end)

      # Create a session ID that's too long (> 128 chars)
      long_id = String.duplicate("a", 129)
      assert {:error, :invalid_session_id} = StoreManager.get_or_create(long_id, name)

      # 128 chars should be ok
      max_id = String.duplicate("a", 128)
      assert {:ok, _} = StoreManager.get_or_create(max_id, name)
    end
  end

  # =============================================================================
  # Input Validation Tests
  # =============================================================================

  describe "input validation" do
    test "persist/2 rejects invalid memory_type" do
      # Test the Types module directly
      refute JidoCode.Memory.Types.valid_memory_type?(:invalid_type)
      assert JidoCode.Memory.Types.valid_memory_type?(:fact)
    end

    test "persist/2 rejects invalid source_type" do
      refute JidoCode.Memory.Types.valid_source_type?(:invalid_source)
      assert JidoCode.Memory.Types.valid_source_type?(:agent)
    end

    test "Types.valid_session_id? validates correctly" do
      # Valid session IDs
      assert JidoCode.Memory.Types.valid_session_id?("session-123")
      assert JidoCode.Memory.Types.valid_session_id?("my_session")
      assert JidoCode.Memory.Types.valid_session_id?("ABC123")

      # Invalid session IDs
      refute JidoCode.Memory.Types.valid_session_id?("")
      refute JidoCode.Memory.Types.valid_session_id?("../path")
      refute JidoCode.Memory.Types.valid_session_id?("session/sub")
      refute JidoCode.Memory.Types.valid_session_id?("session with spaces")
      refute JidoCode.Memory.Types.valid_session_id?("session.dots")
      refute JidoCode.Memory.Types.valid_session_id?(nil)
      refute JidoCode.Memory.Types.valid_session_id?(123)
    end
  end

  # =============================================================================
  # Module API Tests (using the actual Memory module)
  # =============================================================================

  describe "Memory module API" do
    # These tests verify the Memory module's public API
    # They use the default StoreManager which should be started in the application

    test "module exports expected functions" do
      functions = Memory.__info__(:functions)

      assert {:persist, 2} in functions
      assert {:query, 1} in functions
      assert {:query, 2} in functions
      assert {:query_by_type, 2} in functions
      assert {:query_by_type, 3} in functions
      assert {:get, 2} in functions
      assert {:supersede, 2} in functions
      assert {:supersede, 3} in functions
      assert {:forget, 2} in functions
      assert {:delete, 2} in functions
      assert {:count, 1} in functions
      assert {:count, 2} in functions
      assert {:record_access, 2} in functions
      assert {:load_ontology, 1} in functions
      # New session management functions
      assert {:list_sessions, 0} in functions
      assert {:close_session, 1} in functions
    end
  end
end
