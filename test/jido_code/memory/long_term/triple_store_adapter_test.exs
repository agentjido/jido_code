defmodule JidoCode.Memory.LongTerm.TripleStoreAdapterTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.LongTerm.TripleStoreAdapter
  alias JidoCode.Memory.LongTerm.SPARQLQueries

  @moduletag :triple_store

  # Create a fresh TripleStore for each test
  setup do
    # Create a unique temp directory for this test
    test_id = :erlang.unique_integer([:positive])
    base_path = Path.join(System.tmp_dir!(), "triple_store_adapter_test_#{test_id}")
    File.rm_rf!(base_path)
    File.mkdir_p!(base_path)

    {:ok, store} = TripleStore.open(base_path, create_if_missing: true)

    on_exit(fn ->
      try do
        TripleStore.close(store)
      catch
        _, _ -> :ok
      end

      File.rm_rf!(base_path)
    end)

    %{store: store, base_path: base_path}
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp create_memory(overrides \\ %{}) do
    Map.merge(
      %{
        id: "mem-#{:rand.uniform(1_000_000)}",
        content: "Test memory content",
        memory_type: :fact,
        confidence: 0.85,
        source_type: :agent,
        session_id: "session-123",
        created_at: DateTime.utc_now()
      },
      overrides
    )
  end

  # =============================================================================
  # persist/2 Tests
  # =============================================================================

  describe "persist/2" do
    test "persists a memory and returns the ID", %{store: store} do
      memory = create_memory(%{id: "test-mem-1"})

      assert {:ok, "test-mem-1"} = TripleStoreAdapter.persist(memory, store)
    end

    test "stores all required fields", %{store: store} do
      timestamp = DateTime.utc_now()

      memory = %{
        id: "full-mem",
        content: "Complete memory",
        memory_type: :assumption,
        confidence: 0.75,
        source_type: :user,
        session_id: "session-456",
        created_at: timestamp
      }

      {:ok, _id} = TripleStoreAdapter.persist(memory, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "full-mem")

      assert retrieved.id == "full-mem"
      assert retrieved.content == "Complete memory"
      assert retrieved.memory_type == :assumption
      # Confidence maps to levels: 0.75 -> :medium
      assert retrieved.confidence in [:high, :medium, :low]
      assert retrieved.source_type == :user
      assert retrieved.session_id == "session-456"
    end

    test "stores optional rationale field", %{store: store} do
      memory =
        create_memory(%{
          id: "optional-mem",
          rationale: "Important discovery"
        })

      {:ok, _id} = TripleStoreAdapter.persist(memory, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "optional-mem")

      assert retrieved.rationale == "Important discovery"
    end

    test "initializes lifecycle tracking fields", %{store: store} do
      memory = create_memory(%{id: "lifecycle-mem"})

      {:ok, _id} = TripleStoreAdapter.persist(memory, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "lifecycle-mem")

      assert retrieved.superseded_by == nil
      assert retrieved.access_count == 0
    end
  end

  # =============================================================================
  # query_by_type/4 Tests
  # =============================================================================

  describe "query_by_type/4" do
    test "returns memories matching type and session", %{store: store} do
      # Create memories of different types
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "fact-1", memory_type: :fact}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "fact-2", memory_type: :fact}), store)

      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "assumption-1", memory_type: :assumption}), store)

      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)

      assert length(facts) == 2
      assert Enum.all?(facts, &(&1.memory_type == :fact))
    end

    test "filters by session ID", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(
          create_memory(%{id: "s1-mem", session_id: "session-1", memory_type: :fact}),
          store
        )

      {:ok, _} =
        TripleStoreAdapter.persist(
          create_memory(%{id: "s2-mem", session_id: "session-2", memory_type: :fact}),
          store
        )

      {:ok, session1_facts} = TripleStoreAdapter.query_by_type(store, "session-1", :fact)

      assert length(session1_facts) == 1
      assert hd(session1_facts).id == "s1-mem"
    end

    test "excludes superseded memories by default", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "old-fact", memory_type: :fact}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "new-fact", memory_type: :fact}), store)

      # Supersede old memory
      :ok = TripleStoreAdapter.supersede(store, "session-123", "old-fact", "new-fact")

      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)

      # Should only return the non-superseded memory
      assert length(facts) == 1
      assert hd(facts).id == "new-fact"
    end

    test "respects limit option", %{store: store} do
      for i <- 1..10 do
        {:ok, _} =
          TripleStoreAdapter.persist(create_memory(%{id: "fact-#{i}", memory_type: :fact}), store)
      end

      {:ok, limited_facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact, limit: 3)

      assert length(limited_facts) == 3
    end

    test "returns empty list when no matches", %{store: store} do
      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)

      assert facts == []
    end
  end

  # =============================================================================
  # query_all/3 Tests
  # =============================================================================

  describe "query_all/3" do
    test "returns all memories for a session", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem-1", memory_type: :fact}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem-2", memory_type: :assumption}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem-3", memory_type: :discovery}), store)

      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123")

      assert length(memories) == 3
    end

    test "filters by session ID", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "s1-mem", session_id: "session-1"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "s2-mem", session_id: "session-2"}), store)

      {:ok, session1_memories} = TripleStoreAdapter.query_all(store, "session-1")

      assert length(session1_memories) == 1
      assert hd(session1_memories).id == "s1-mem"
    end

    test "respects include_superseded option", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "old-mem"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "new-mem"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "old-mem", "new-mem")

      {:ok, without_superseded} = TripleStoreAdapter.query_all(store, "session-123")
      {:ok, with_superseded} = TripleStoreAdapter.query_all(store, "session-123", include_superseded: true)

      assert length(without_superseded) == 1
      assert length(with_superseded) == 2
    end

    test "respects type option", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "fact", memory_type: :fact}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "assumption", memory_type: :assumption}), store)

      {:ok, facts_only} = TripleStoreAdapter.query_all(store, "session-123", type: :fact)

      assert length(facts_only) == 1
      assert hd(facts_only).memory_type == :fact
    end

    test "respects limit option", %{store: store} do
      for i <- 1..10 do
        {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem-#{i}"}), store)
      end

      {:ok, limited_memories} = TripleStoreAdapter.query_all(store, "session-123", limit: 5)

      assert length(limited_memories) == 5
    end
  end

  # =============================================================================
  # query_by_id/2 and query_by_id/3 Tests
  # =============================================================================

  describe "query_by_id/2" do
    test "returns memory when found", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "find-me"}), store)

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "find-me")

      assert memory.id == "find-me"
    end

    test "returns :not_found for unknown ID", %{store: store} do
      assert {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "unknown")
    end

    test "returns memory even if superseded", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "superseded-mem"}), store)
      :ok = TripleStoreAdapter.supersede(store, "session-123", "superseded-mem", "new-mem")

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "superseded-mem")

      assert memory.id == "superseded-mem"
      assert memory.superseded_by == "new-mem"
    end
  end

  describe "query_by_id/3" do
    test "returns memory when session matches", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "find-me", session_id: "session-123"}), store)

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "session-123", "find-me")

      assert memory.id == "find-me"
    end

    test "returns :not_found when session doesn't match", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      assert {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "session-2", "mem")
    end
  end

  # =============================================================================
  # supersede/4 Tests
  # =============================================================================

  describe "supersede/4" do
    test "marks memory as superseded", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "old-mem"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "old-mem", "new-mem")

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "old-mem")
      assert memory.superseded_by == "new-mem"
    end

    test "allows nil for new_memory_id (uses DeletedMarker)", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "obsolete-mem"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "obsolete-mem", nil)

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "obsolete-mem")
      # Should be marked with deleted marker
      assert memory.superseded_by == "deleted"
    end

    test "returns :not_found for unknown memory", %{store: store} do
      assert {:error, :not_found} = TripleStoreAdapter.supersede(store, "session-123", "unknown", nil)
    end

    test "returns :not_found for wrong session", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      assert {:error, :not_found} =
               TripleStoreAdapter.supersede(store, "session-2", "mem", nil)
    end
  end

  # =============================================================================
  # delete/3 Tests
  # =============================================================================

  describe "delete/3" do
    test "marks memory as deleted (soft delete)", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "delete-me"}), store)

      :ok = TripleStoreAdapter.delete(store, "session-123", "delete-me")

      # Memory still exists but is excluded from queries (soft delete)
      {:ok, memories} = TripleStoreAdapter.query_all(store, "session-123")
      assert Enum.empty?(memories)
    end

    test "returns :ok for unknown memory", %{store: store} do
      assert :ok = TripleStoreAdapter.delete(store, "session-123", "unknown")
    end
  end

  # =============================================================================
  # record_access/3 Tests
  # =============================================================================

  describe "record_access/3" do
    test "returns :ok for existing memory", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "accessed-mem"}), store)

      assert :ok = TripleStoreAdapter.record_access(store, "session-123", "accessed-mem")
    end

    test "returns :ok for unknown memory", %{store: store} do
      assert :ok = TripleStoreAdapter.record_access(store, "session-123", "unknown")
    end

    test "returns :ok for wrong session", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      # Should return :ok even for wrong session (no-op)
      assert :ok = TripleStoreAdapter.record_access(store, "session-2", "mem")
    end
  end

  # =============================================================================
  # count/3 Tests
  # =============================================================================

  describe "count/3" do
    test "returns count of memories for session", %{store: store} do
      for i <- 1..5 do
        {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "mem-#{i}"}), store)
      end

      {:ok, count} = TripleStoreAdapter.count(store, "session-123")

      assert count == 5
    end

    test "excludes superseded memories by default", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "active"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "superseded"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "superseded", "active")

      {:ok, count} = TripleStoreAdapter.count(store, "session-123")

      assert count == 1
    end

    test "includes superseded when option is set", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "active"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "superseded"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "superseded", "active")

      {:ok, count} = TripleStoreAdapter.count(store, "session-123", include_superseded: true)

      assert count == 2
    end

    test "returns 0 for empty store", %{store: store} do
      {:ok, count} = TripleStoreAdapter.count(store, "session-123")

      assert count == 0
    end

    test "filters by session ID", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "s1", session_id: "session-1"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "s2", session_id: "session-2"}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "s3", session_id: "session-2"}), store)

      {:ok, s1_count} = TripleStoreAdapter.count(store, "session-1")
      {:ok, s2_count} = TripleStoreAdapter.count(store, "session-2")

      assert s1_count == 1
      assert s2_count == 2
    end
  end

  # =============================================================================
  # extract_id/1 Tests
  # =============================================================================

  describe "extract_id/1" do
    test "extracts ID from memory IRI" do
      iri = "#{SPARQLQueries.namespace()}memory_test-123"

      assert TripleStoreAdapter.extract_id(iri) == "test-123"
    end

    test "returns input if not a valid memory IRI" do
      assert TripleStoreAdapter.extract_id("not-an-iri") == "not-an-iri"
    end
  end

  # =============================================================================
  # memory_iri/1 Tests
  # =============================================================================

  describe "memory_iri/1" do
    test "generates correct IRI for ID" do
      iri = TripleStoreAdapter.memory_iri("my-memory-id")

      expected = "#{SPARQLQueries.namespace()}memory_my-memory-id"
      assert iri == expected
    end
  end

  # =============================================================================
  # Memory Types Tests
  # =============================================================================

  describe "memory types" do
    test "persists and queries all memory types", %{store: store} do
      memory_types = [:fact, :assumption, :hypothesis, :discovery, :risk, :unknown, :decision, :convention, :lesson_learned]

      for type <- memory_types do
        memory = create_memory(%{id: "type-#{type}", memory_type: type})
        {:ok, _} = TripleStoreAdapter.persist(memory, store)

        {:ok, [retrieved]} = TripleStoreAdapter.query_by_type(store, "session-123", type)
        assert retrieved.memory_type == type
      end
    end
  end

  # =============================================================================
  # Source Types Tests
  # =============================================================================

  describe "source types" do
    test "persists and retrieves all source types", %{store: store} do
      source_types = [:user, :agent, :tool, :external_document]

      for source <- source_types do
        memory = create_memory(%{id: "source-#{source}", source_type: source})
        {:ok, _} = TripleStoreAdapter.persist(memory, store)

        {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "source-#{source}")
        assert retrieved.source_type == source
      end
    end
  end

  # =============================================================================
  # ID Validation Tests
  # =============================================================================

  describe "ID validation" do
    test "rejects invalid memory IDs in persist/2", %{store: store} do
      # Test empty string
      memory = create_memory(%{id: ""})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test special characters
      memory = create_memory(%{id: "mem@123"})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test spaces
      memory = create_memory(%{id: "mem 123"})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test SQL injection attempt
      memory = create_memory(%{id: "mem'; DROP TABLE--"})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test path traversal attempt
      memory = create_memory(%{id: "../../../etc/passwd"})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test overly long ID (>128 chars)
      long_id = String.duplicate("a", 129)
      memory = create_memory(%{id: long_id})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)

      # Test nil ID
      memory = create_memory(%{id: nil})
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.persist(memory, store)
    end

    test "accepts valid memory IDs", %{store: store} do
      # Test alphanumeric
      memory = create_memory(%{id: "mem123"})
      assert {:ok, "mem123"} = TripleStoreAdapter.persist(memory, store)

      # Test with hyphens
      memory = create_memory(%{id: "mem-123-test"})
      assert {:ok, "mem-123-test"} = TripleStoreAdapter.persist(memory, store)

      # Test with underscores
      memory = create_memory(%{id: "mem_123_test"})
      assert {:ok, "mem_123_test"} = TripleStoreAdapter.persist(memory, store)

      # Test mixed
      memory = create_memory(%{id: "Mem-123_Test"})
      assert {:ok, "Mem-123_Test"} = TripleStoreAdapter.persist(memory, store)

      # Test max length (128 chars)
      max_id = String.duplicate("a", 128)
      memory = create_memory(%{id: max_id})
      assert {:ok, ^max_id} = TripleStoreAdapter.persist(memory, store)
    end

    test "rejects invalid session IDs in persist/2", %{store: store} do
      # Test empty session ID
      memory = create_memory(%{session_id: ""})
      assert {:error, :invalid_session_id} = TripleStoreAdapter.persist(memory, store)

      # Test special characters
      memory = create_memory(%{session_id: "sess@123"})
      assert {:error, :invalid_session_id} = TripleStoreAdapter.persist(memory, store)

      # Test path traversal attempt
      memory = create_memory(%{session_id: "../other-session"})
      assert {:error, :invalid_session_id} = TripleStoreAdapter.persist(memory, store)
    end

    test "rejects invalid memory IDs in query_by_id/2", %{store: store} do
      # First insert a valid memory
      memory = create_memory(%{id: "valid-mem"})
      {:ok, _} = TripleStoreAdapter.persist(memory, store)

      # Test invalid ID is rejected
      assert {:error, :invalid_memory_id} = TripleStoreAdapter.query_by_id(store, "'; DROP TABLE--")

      # Test valid ID works
      assert {:ok, _} = TripleStoreAdapter.query_by_id(store, "valid-mem")
    end

    test "rejects invalid session IDs in query_by_type/4", %{store: store} do
      assert {:error, :invalid_session_id} =
               TripleStoreAdapter.query_by_type(store, "../escape", :fact)
    end

    test "rejects invalid session IDs in query_all/3", %{store: store} do
      assert {:error, :invalid_session_id} =
               TripleStoreAdapter.query_all(store, "sess'; DROP--")
    end

    test "rejects invalid IDs in supersede/4", %{store: store} do
      # Insert a memory first
      memory = create_memory(%{id: "old-mem"})
      {:ok, _} = TripleStoreAdapter.persist(memory, store)

      # Test invalid old_memory_id
      assert {:error, :invalid_memory_id} =
               TripleStoreAdapter.supersede(store, "session-123", "bad;id", "new-mem")

      # Test invalid new_memory_id
      assert {:error, :invalid_memory_id} =
               TripleStoreAdapter.supersede(store, "session-123", "old-mem", "new@mem")
    end

    test "rejects invalid IDs in delete/3", %{store: store} do
      assert {:error, :invalid_memory_id} =
               TripleStoreAdapter.delete(store, "session-123", "mem;id")
    end

    test "rejects invalid IDs in query_related/5", %{store: store} do
      assert {:error, :invalid_session_id} =
               TripleStoreAdapter.query_related(store, "sess@id", "mem-123", :refines)

      assert {:error, :invalid_memory_id} =
               TripleStoreAdapter.query_related(store, "session-123", "mem;id", :refines)
    end

    test "rejects invalid session IDs in get_stats/2", %{store: store} do
      assert {:error, :invalid_session_id} =
               TripleStoreAdapter.get_stats(store, "sess'; DROP--")
    end

    test "rejects invalid session IDs in count/3", %{store: store} do
      assert {:error, :invalid_session_id} =
               TripleStoreAdapter.count(store, "../escape")
    end
  end
end
