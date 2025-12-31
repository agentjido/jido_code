defmodule JidoCode.Integration.MemoryPhase2Test do
  @moduledoc """
  Phase 2 Integration Tests for Long-Term Memory Store.

  These tests verify the complete integration of the long-term memory system,
  including store lifecycle management, CRUD operations, ontology integration,
  and concurrent access patterns.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Memory.LongTerm.StoreManager
  alias JidoCode.Memory.LongTerm.TripleStoreAdapter
  alias JidoCode.Memory.LongTerm.Vocab.Jido, as: Vocab

  # Use unique paths and session IDs for each test
  setup do
    base_path = Path.join(System.tmp_dir!(), "memory_phase2_integration_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(base_path)

    # Create unique names for isolated testing
    rand = :rand.uniform(1_000_000)
    supervisor_name = :"memory_supervisor_integration_#{rand}"
    store_manager_name = :"store_manager_integration_#{rand}"

    # Start an isolated supervisor for testing
    {:ok, sup_pid} =
      JidoCode.Memory.Supervisor.start_link(
        name: supervisor_name,
        base_path: base_path,
        store_name: store_manager_name
      )

    session_id = "integration-session-#{rand}"

    on_exit(fn ->
      # Gracefully stop supervisor, catching any errors if already stopped
      try do
        if Process.alive?(sup_pid) do
          Supervisor.stop(sup_pid, :normal, 5000)
        end
      catch
        :exit, _ -> :ok
      end

      File.rm_rf!(base_path)
    end)

    %{
      base_path: base_path,
      supervisor: sup_pid,
      store_manager: store_manager_name,
      session_id: session_id
    }
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

  defp persist_memory(memory, session_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    TripleStoreAdapter.persist(memory, store)
  end

  defp query_memories(session_id, store_manager, opts \\ []) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    TripleStoreAdapter.query_all(store, session_id, opts)
  end

  defp get_memory(session_id, memory_id, store_manager) do
    {:ok, store} = StoreManager.get_or_create(session_id, store_manager)
    TripleStoreAdapter.query_by_id(store, session_id, memory_id)
  end

  # =============================================================================
  # 2.6.1 Store Lifecycle Integration Tests
  # =============================================================================

  describe "2.6.1 Store Lifecycle Integration" do
    test "StoreManager creates isolated ETS store per session", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create first session store
      {:ok, store1} = StoreManager.get_or_create(session_id, manager)
      assert store1 != nil

      # Create second session store
      session_id2 = "#{session_id}-2"
      {:ok, store2} = StoreManager.get_or_create(session_id2, manager)
      assert store2 != nil

      # Stores should be different
      assert store1 != store2

      # Both should be tracked
      assert StoreManager.open?(session_id, manager)
      assert StoreManager.open?(session_id2, manager)

      # Clean up
      StoreManager.close(session_id2, manager)
    end

    test "Store persists data across get_or_create calls", %{
      store_manager: manager,
      session_id: session_id
    } do
      # First call - create store and persist data
      {:ok, store1} = StoreManager.get_or_create(session_id, manager)
      memory = create_memory(session_id, %{id: "persist-test", content: "Persistent data"})
      {:ok, _} = TripleStoreAdapter.persist(memory, store1)

      # Second call - should get same store with data intact
      {:ok, store2} = StoreManager.get_or_create(session_id, manager)
      assert store1 == store2

      # Data should still be there
      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store2, session_id, "persist-test")
      assert retrieved.content == "Persistent data"
    end

    test "Multiple sessions have completely isolated data", %{
      store_manager: manager,
      session_id: session_id
    } do
      session_id2 = "#{session_id}-isolated"

      # Persist memory in session 1
      memory1 = create_memory(session_id, %{id: "session1-mem", content: "Session 1 data"})
      {:ok, _} = persist_memory(memory1, session_id, manager)

      # Persist memory in session 2
      memory2 = create_memory(session_id2, %{id: "session2-mem", content: "Session 2 data"})
      {:ok, _} = persist_memory(memory2, session_id2, manager)

      # Query session 1 - should only see session 1 data
      {:ok, memories1} = query_memories(session_id, manager)
      assert length(memories1) == 1
      assert hd(memories1).content == "Session 1 data"

      # Query session 2 - should only see session 2 data
      {:ok, memories2} = query_memories(session_id2, manager)
      assert length(memories2) == 1
      assert hd(memories2).content == "Session 2 data"

      # Session 1 cannot access session 2's memory by ID
      {:error, :not_found} = get_memory(session_id, "session2-mem", manager)

      # Clean up
      StoreManager.close(session_id2, manager)
    end

    test "Closing store allows clean shutdown", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create store and add data
      {:ok, _store} = StoreManager.get_or_create(session_id, manager)
      memory = create_memory(session_id)
      {:ok, _} = persist_memory(memory, session_id, manager)

      # Verify store is open
      assert StoreManager.open?(session_id, manager)

      # Close store
      :ok = StoreManager.close(session_id, manager)

      # Verify store is closed
      refute StoreManager.open?(session_id, manager)

      # Get should return not_found for closed store
      {:error, :not_found} = StoreManager.get(session_id, manager)
    end

    test "Store reopens correctly after close", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create store and add data
      {:ok, store1} = StoreManager.get_or_create(session_id, manager)
      memory = create_memory(session_id, %{id: "reopen-test", content: "Before close"})
      {:ok, _} = TripleStoreAdapter.persist(memory, store1)

      # Close store
      :ok = StoreManager.close(session_id, manager)
      refute StoreManager.open?(session_id, manager)

      # Reopen store
      {:ok, store2} = StoreManager.get_or_create(session_id, manager)
      assert StoreManager.open?(session_id, manager)

      # Note: ETS tables don't persist after close, so data is gone
      # This is expected behavior for in-memory stores
      # In future with RocksDB, data would persist
      {:ok, memories} = TripleStoreAdapter.query_all(store2, session_id, [])
      # ETS is ephemeral - data is lost on close (expected behavior)
      assert memories == []
    end
  end

  # =============================================================================
  # 2.6.2 Memory CRUD Integration Tests
  # =============================================================================

  describe "2.6.2 Memory CRUD Integration" do
    test "Full lifecycle - persist, query, update, supersede, query again", %{
      store_manager: manager,
      session_id: session_id
    } do
      # 1. Persist initial memory
      memory1 = create_memory(session_id, %{
        id: "lifecycle-v1",
        content: "Initial version",
        confidence: 0.7
      })
      {:ok, _} = persist_memory(memory1, session_id, manager)

      # 2. Query - should find it
      {:ok, memories} = query_memories(session_id, manager)
      assert length(memories) == 1
      assert hd(memories).content == "Initial version"

      # 3. Create updated version
      memory2 = create_memory(session_id, %{
        id: "lifecycle-v2",
        content: "Updated version",
        confidence: 0.9
      })
      {:ok, _} = persist_memory(memory2, session_id, manager)

      # 4. Supersede old with new
      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = TripleStoreAdapter.supersede(store, session_id, "lifecycle-v1", "lifecycle-v2")

      # 5. Query again - should only see new version
      {:ok, memories_after} = query_memories(session_id, manager)
      assert length(memories_after) == 1
      assert hd(memories_after).content == "Updated version"

      # 6. Query with include_superseded - should see both
      {:ok, all_memories} = query_memories(session_id, manager, include_superseded: true)
      assert length(all_memories) == 2
    end

    test "Multiple memory types stored and retrieved correctly", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create memories of different types
      memory_types = [:fact, :assumption, :hypothesis, :discovery, :risk, :decision, :convention, :lesson_learned]

      for type <- memory_types do
        memory = create_memory(session_id, %{
          id: "type-test-#{type}",
          content: "Memory of type #{type}",
          memory_type: type
        })
        {:ok, _} = persist_memory(memory, session_id, manager)
      end

      # Query all - should have all types
      {:ok, memories} = query_memories(session_id, manager)
      assert length(memories) == length(memory_types)

      # Query by each type
      {:ok, store} = StoreManager.get_or_create(session_id, manager)

      for type <- memory_types do
        {:ok, typed_memories} = TripleStoreAdapter.query_by_type(store, session_id, type, [])
        assert length(typed_memories) == 1
        assert hd(typed_memories).memory_type == type
      end
    end

    test "Confidence filtering works correctly across types", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create memories with varying confidence levels
      confidences = [0.95, 0.85, 0.75, 0.65, 0.55, 0.45, 0.35, 0.25]

      for {conf, idx} <- Enum.with_index(confidences) do
        memory = create_memory(session_id, %{
          id: "conf-test-#{idx}",
          confidence: conf
        })
        {:ok, _} = persist_memory(memory, session_id, manager)
      end

      # Query with min_confidence 0.8 - should get 2 (0.95, 0.85)
      {:ok, high_conf} = query_memories(session_id, manager, min_confidence: 0.8)
      assert length(high_conf) == 2
      assert Enum.all?(high_conf, &(&1.confidence >= 0.8))

      # Query with min_confidence 0.5 - should get 5
      {:ok, medium_conf} = query_memories(session_id, manager, min_confidence: 0.5)
      assert length(medium_conf) == 5
      assert Enum.all?(medium_conf, &(&1.confidence >= 0.5))

      # Query with no filter - should get all 8
      {:ok, all} = query_memories(session_id, manager)
      assert length(all) == 8
    end

    test "Memory with all optional fields persists and retrieves correctly", %{
      store_manager: manager,
      session_id: session_id
    } do
      timestamp = DateTime.utc_now()

      memory = %{
        id: "full-fields-test",
        content: "Memory with all fields",
        memory_type: :discovery,
        confidence: 0.92,
        source_type: :tool,
        session_id: session_id,
        agent_id: "agent-integration-test",
        project_id: "project-integration-test",
        rationale: "Found during integration testing",
        evidence_refs: ["ref-1", "ref-2", "ref-3"],
        created_at: timestamp
      }

      {:ok, _} = persist_memory(memory, session_id, manager)

      # Retrieve and verify all fields
      {:ok, retrieved} = get_memory(session_id, "full-fields-test", manager)

      assert retrieved.id == "full-fields-test"
      assert retrieved.content == "Memory with all fields"
      assert retrieved.memory_type == :discovery
      assert retrieved.confidence == 0.92
      assert retrieved.source_type == :tool
      assert retrieved.session_id == session_id
      assert retrieved.agent_id == "agent-integration-test"
      assert retrieved.project_id == "project-integration-test"
      assert retrieved.rationale == "Found during integration testing"
      assert retrieved.evidence_refs == ["ref-1", "ref-2", "ref-3"]
    end

    test "Superseded memories excluded from normal queries", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create two memories
      mem1 = create_memory(session_id, %{id: "supersede-old", content: "Old version"})
      mem2 = create_memory(session_id, %{id: "supersede-new", content: "New version"})

      {:ok, _} = persist_memory(mem1, session_id, manager)
      {:ok, _} = persist_memory(mem2, session_id, manager)

      # Before supersession - both visible
      {:ok, before} = query_memories(session_id, manager)
      assert length(before) == 2

      # Supersede old with new
      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = TripleStoreAdapter.supersede(store, session_id, "supersede-old", "supersede-new")

      # After supersession - only new visible
      {:ok, after_supersede} = query_memories(session_id, manager)
      assert length(after_supersede) == 1
      assert hd(after_supersede).id == "supersede-new"
    end

    test "Superseded memories included with include_superseded option", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Create and supersede memories
      mem1 = create_memory(session_id, %{id: "include-old"})
      mem2 = create_memory(session_id, %{id: "include-new"})

      {:ok, _} = persist_memory(mem1, session_id, manager)
      {:ok, _} = persist_memory(mem2, session_id, manager)

      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = TripleStoreAdapter.supersede(store, session_id, "include-old", "include-new")

      # Without option - 1 visible
      {:ok, normal} = query_memories(session_id, manager)
      assert length(normal) == 1

      # With include_superseded - both visible
      {:ok, with_superseded} = query_memories(session_id, manager, include_superseded: true)
      assert length(with_superseded) == 2

      # Verify the superseded one has superseded_by set
      old_mem = Enum.find(with_superseded, &(&1.id == "include-old"))
      assert old_mem.superseded_by == "include-new"
    end

    test "Access tracking updates correctly on queries", %{
      store_manager: manager,
      session_id: session_id
    } do
      memory = create_memory(session_id, %{id: "access-track-test"})
      {:ok, _} = persist_memory(memory, session_id, manager)

      # Get initial state
      {:ok, initial} = get_memory(session_id, "access-track-test", manager)
      assert initial.access_count == 0
      assert initial.last_accessed == nil

      # Record access
      {:ok, store} = StoreManager.get_or_create(session_id, manager)
      :ok = TripleStoreAdapter.record_access(store, session_id, "access-track-test")

      # Verify access count updated
      {:ok, after_one} = get_memory(session_id, "access-track-test", manager)
      assert after_one.access_count == 1
      assert after_one.last_accessed != nil

      # Record more accesses
      :ok = TripleStoreAdapter.record_access(store, session_id, "access-track-test")
      :ok = TripleStoreAdapter.record_access(store, session_id, "access-track-test")

      {:ok, after_three} = get_memory(session_id, "access-track-test", manager)
      assert after_three.access_count == 3
    end
  end

  # =============================================================================
  # 2.6.3 Ontology Integration Tests
  # =============================================================================

  describe "2.6.3 Ontology Integration" do
    test "Vocabulary IRIs use correct namespace" do
      # Verify namespace
      assert Vocab.namespace() == "https://jido.ai/ontology#"

      # Verify class IRIs are correctly formed
      assert Vocab.fact() == "https://jido.ai/ontology#Fact"
      assert Vocab.assumption() == "https://jido.ai/ontology#Assumption"
      assert Vocab.hypothesis() == "https://jido.ai/ontology#Hypothesis"
      assert Vocab.discovery() == "https://jido.ai/ontology#Discovery"
      assert Vocab.risk() == "https://jido.ai/ontology#Risk"
      assert Vocab.decision() == "https://jido.ai/ontology#Decision"
      assert Vocab.convention() == "https://jido.ai/ontology#Convention"
      assert Vocab.lesson_learned() == "https://jido.ai/ontology#LessonLearned"
    end

    test "Memory type to class mapping is bidirectional" do
      memory_types = [
        :fact,
        :assumption,
        :hypothesis,
        :discovery,
        :risk,
        :unknown,
        :decision,
        :convention,
        :lesson_learned
      ]

      for type <- memory_types do
        # Convert to class IRI
        class_iri = Vocab.memory_type_to_class(type)
        assert String.starts_with?(class_iri, Vocab.namespace())

        # Convert back to type
        converted_type = Vocab.class_to_memory_type(class_iri)
        assert converted_type == type
      end
    end

    test "Confidence level mapping works correctly" do
      # High confidence (>= 0.8)
      assert Vocab.confidence_to_individual(1.0) == Vocab.confidence_high()
      assert Vocab.confidence_to_individual(0.9) == Vocab.confidence_high()
      assert Vocab.confidence_to_individual(0.8) == Vocab.confidence_high()

      # Medium confidence (>= 0.5, < 0.8)
      assert Vocab.confidence_to_individual(0.79) == Vocab.confidence_medium()
      assert Vocab.confidence_to_individual(0.5) == Vocab.confidence_medium()

      # Low confidence (< 0.5)
      assert Vocab.confidence_to_individual(0.49) == Vocab.confidence_low()
      assert Vocab.confidence_to_individual(0.0) == Vocab.confidence_low()

      # Reverse mapping
      assert Vocab.individual_to_confidence(Vocab.confidence_high()) == 0.9
      assert Vocab.individual_to_confidence(Vocab.confidence_medium()) == 0.6
      assert Vocab.individual_to_confidence(Vocab.confidence_low()) == 0.3
    end

    test "Entity URI generators create valid IRIs" do
      # Memory URI
      memory_uri = Vocab.memory_uri("test-123")
      assert memory_uri == "https://jido.ai/ontology#memory_test-123"

      # Session URI
      session_uri = Vocab.session_uri("session-abc")
      assert session_uri == "https://jido.ai/ontology#session_session-abc"

      # Agent URI
      agent_uri = Vocab.agent_uri("agent-xyz")
      assert agent_uri == "https://jido.ai/ontology#agent_agent-xyz"

      # Project URI
      project_uri = Vocab.project_uri("project-456")
      assert project_uri == "https://jido.ai/ontology#project_project-456"
    end
  end

  # =============================================================================
  # 2.6.4 Concurrency Integration Tests
  # =============================================================================

  describe "2.6.4 Concurrency Integration" do
    test "Concurrent persist operations to same session", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Ensure store is created
      {:ok, _} = StoreManager.get_or_create(session_id, manager)

      # Launch concurrent persist operations
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            memory = create_memory(session_id, %{
              id: "concurrent-persist-#{i}",
              content: "Concurrent memory #{i}"
            })
            persist_memory(memory, session_id, manager)
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks, 10_000)

      # All should succeed
      assert Enum.all?(results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # Verify all memories were persisted
      {:ok, memories} = query_memories(session_id, manager)
      assert length(memories) == 20
    end

    test "Concurrent queries during persist operations", %{
      store_manager: manager,
      session_id: session_id
    } do
      # Pre-populate with some data
      for i <- 1..5 do
        memory = create_memory(session_id, %{id: "pre-populated-#{i}"})
        {:ok, _} = persist_memory(memory, session_id, manager)
      end

      # Launch mixed concurrent operations
      persist_tasks =
        for i <- 1..10 do
          Task.async(fn ->
            memory = create_memory(session_id, %{id: "concurrent-mixed-#{i}"})
            persist_memory(memory, session_id, manager)
          end)
        end

      query_tasks =
        for _ <- 1..10 do
          Task.async(fn ->
            query_memories(session_id, manager)
          end)
        end

      # Wait for all
      persist_results = Task.await_many(persist_tasks, 10_000)
      query_results = Task.await_many(query_tasks, 10_000)

      # All persists should succeed
      assert Enum.all?(persist_results, fn
        {:ok, _} -> true
        _ -> false
      end)

      # All queries should succeed
      assert Enum.all?(query_results, fn
        {:ok, _memories} -> true
        _ -> false
      end)

      # Final count should be 15 (5 pre-populated + 10 concurrent)
      {:ok, final_memories} = query_memories(session_id, manager)
      assert length(final_memories) == 15
    end

    test "Multiple sessions with concurrent operations", %{
      store_manager: manager,
      session_id: base_session_id
    } do
      # Create 5 sessions with concurrent operations
      session_ids = for i <- 1..5, do: "#{base_session_id}-multi-#{i}"

      # Launch tasks for each session
      tasks =
        for session_id <- session_ids do
          Task.async(fn ->
            # Each session does multiple operations
            for i <- 1..10 do
              memory = create_memory(session_id, %{
                id: "multi-session-#{session_id}-#{i}",
                content: "Memory #{i} in #{session_id}"
              })
              {:ok, _} = persist_memory(memory, session_id, manager)
            end

            # Query to verify
            {:ok, memories} = query_memories(session_id, manager)
            {session_id, length(memories)}
          end)
        end

      # Wait for all
      results = Task.await_many(tasks, 30_000)

      # Each session should have 10 memories
      for {session_id, count} <- results do
        assert count == 10, "Session #{session_id} should have 10 memories, got #{count}"
      end

      # Verify isolation - each session only sees its own data
      for session_id <- session_ids do
        {:ok, memories} = query_memories(session_id, manager)
        assert Enum.all?(memories, &String.contains?(&1.content, session_id))
      end

      # Clean up
      for session_id <- session_ids do
        StoreManager.close(session_id, manager)
      end
    end
  end

  # =============================================================================
  # Additional Integration Tests
  # =============================================================================

  describe "Memory Facade Integration" do
    test "Memory facade works with application-started supervisor" do
      # Use the default StoreManager started by the application
      session_id = "facade-integration-test-#{:rand.uniform(1_000_000)}"

      # Persist via facade
      memory = create_memory(session_id)
      {:ok, id} = Memory.persist(memory, session_id)
      assert id == memory.id

      # Query via facade
      {:ok, memories} = Memory.query(session_id)
      assert length(memories) == 1

      # Get via facade
      {:ok, retrieved} = Memory.get(session_id, id)
      assert retrieved.content == memory.content

      # Count via facade
      {:ok, count} = Memory.count(session_id)
      assert count == 1

      # Clean up
      Memory.close_session(session_id)
    end

    test "Session listing works correctly" do
      session_id1 = "list-test-#{:rand.uniform(1_000_000)}"
      session_id2 = "list-test-#{:rand.uniform(1_000_000)}"

      # Create sessions by persisting to them
      {:ok, _} = Memory.persist(create_memory(session_id1), session_id1)
      {:ok, _} = Memory.persist(create_memory(session_id2), session_id2)

      # List sessions
      sessions = Memory.list_sessions()
      assert session_id1 in sessions
      assert session_id2 in sessions

      # Clean up
      Memory.close_session(session_id1)
      Memory.close_session(session_id2)
    end
  end
end
