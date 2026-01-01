defmodule JidoCode.Memory.LongTerm.TripleStoreAdapterTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.LongTerm.TripleStoreAdapter
  alias JidoCode.Memory.LongTerm.Vocab.Jido, as: Vocab

  # Create a fresh ETS store for each test
  setup do
    table = :ets.new(:test_store, [:set, :public])

    on_exit(fn ->
      try do
        :ets.delete(table)
      rescue
        ArgumentError -> :ok
      end
    end)

    %{store: table}
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
      assert retrieved.confidence == 0.75
      assert retrieved.source_type == :user
      assert retrieved.session_id == "session-456"
      assert retrieved.timestamp == timestamp
    end

    test "stores optional fields", %{store: store} do
      memory =
        create_memory(%{
          id: "optional-mem",
          agent_id: "agent-001",
          project_id: "project-xyz",
          rationale: "Important discovery",
          evidence_refs: ["ref-1", "ref-2"]
        })

      {:ok, _id} = TripleStoreAdapter.persist(memory, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "optional-mem")

      assert retrieved.agent_id == "agent-001"
      assert retrieved.project_id == "project-xyz"
      assert retrieved.rationale == "Important discovery"
      assert retrieved.evidence_refs == ["ref-1", "ref-2"]
    end

    test "initializes lifecycle tracking fields", %{store: store} do
      memory = create_memory(%{id: "lifecycle-mem"})

      {:ok, _id} = TripleStoreAdapter.persist(memory, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "lifecycle-mem")

      assert retrieved.superseded_by == nil
      assert retrieved.access_count == 0
      assert retrieved.last_accessed == nil
    end

    test "handles duplicate IDs by overwriting", %{store: store} do
      memory1 = create_memory(%{id: "dup-mem", content: "First version"})
      memory2 = create_memory(%{id: "dup-mem", content: "Second version"})

      {:ok, _id} = TripleStoreAdapter.persist(memory1, store)
      {:ok, _id} = TripleStoreAdapter.persist(memory2, store)

      {:ok, retrieved} = TripleStoreAdapter.query_by_id(store, "dup-mem")
      assert retrieved.content == "Second version"
    end

    test "returns error for invalid store" do
      memory = create_memory()

      assert {:error, :invalid_store} = TripleStoreAdapter.persist(memory, :invalid_table)
    end
  end

  # =============================================================================
  # build_triples/1 Tests
  # =============================================================================

  describe "build_triples/1" do
    test "generates type triple" do
      memory = create_memory(%{id: "triple-test", memory_type: :fact})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("triple-test")
      type_triple = {subject, Vocab.rdf_type(), Vocab.memory_type_to_class(:fact)}

      assert type_triple in triples
    end

    test "generates content triple" do
      memory = create_memory(%{id: "content-test", content: "Test content"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("content-test")
      content_triple = {subject, Vocab.summary(), {:literal, "Test content"}}

      assert content_triple in triples
    end

    test "generates confidence triple" do
      memory = create_memory(%{id: "conf-test", confidence: 0.9})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("conf-test")
      conf_triple = {subject, Vocab.has_confidence(), Vocab.confidence_to_individual(0.9)}

      assert conf_triple in triples
    end

    test "generates source type triple" do
      memory = create_memory(%{id: "source-test", source_type: :tool})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("source-test")
      source_triple = {subject, Vocab.has_source_type(), Vocab.source_type_to_individual(:tool)}

      assert source_triple in triples
    end

    test "generates session triple" do
      memory = create_memory(%{id: "session-test", session_id: "my-session"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("session-test")
      session_triple = {subject, Vocab.asserted_in(), Vocab.session_uri("my-session")}

      assert session_triple in triples
    end

    test "generates timestamp triple" do
      timestamp = ~U[2025-01-15 10:30:00Z]
      memory = create_memory(%{id: "time-test", created_at: timestamp})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("time-test")
      time_triple = {subject, Vocab.has_timestamp(), {:literal, "2025-01-15T10:30:00Z"}}

      assert time_triple in triples
    end

    test "generates agent triple when present" do
      memory = create_memory(%{id: "agent-test", agent_id: "agent-xyz"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("agent-test")
      agent_triple = {subject, Vocab.asserted_by(), Vocab.agent_uri("agent-xyz")}

      assert agent_triple in triples
    end

    test "generates project triple when present" do
      memory = create_memory(%{id: "project-test", project_id: "project-abc"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("project-test")
      project_triple = {subject, Vocab.applies_to_project(), Vocab.project_uri("project-abc")}

      assert project_triple in triples
    end

    test "generates rationale triple when present" do
      memory = create_memory(%{id: "rationale-test", rationale: "Because reasons"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("rationale-test")
      rationale_triple = {subject, Vocab.rationale(), {:literal, "Because reasons"}}

      assert rationale_triple in triples
    end

    test "generates evidence triples for each reference" do
      memory = create_memory(%{id: "evidence-test", evidence_refs: ["ev-1", "ev-2", "ev-3"]})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("evidence-test")

      assert {subject, Vocab.derived_from(), Vocab.evidence_uri("ev-1")} in triples
      assert {subject, Vocab.derived_from(), Vocab.evidence_uri("ev-2")} in triples
      assert {subject, Vocab.derived_from(), Vocab.evidence_uri("ev-3")} in triples
    end

    test "omits optional triples when nil" do
      memory = create_memory(%{id: "minimal-test"})

      triples = TripleStoreAdapter.build_triples(memory)

      subject = Vocab.memory_uri("minimal-test")

      refute Enum.any?(triples, fn {s, p, _o} ->
               s == subject and p == Vocab.asserted_by()
             end)

      refute Enum.any?(triples, fn {s, p, _o} ->
               s == subject and p == Vocab.applies_to_project()
             end)

      refute Enum.any?(triples, fn {s, p, _o} ->
               s == subject and p == Vocab.rationale()
             end)
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

    test "returns results sorted by timestamp descending", %{store: store} do
      base_time = ~U[2025-01-15 10:00:00Z]

      for i <- 1..3 do
        timestamp = DateTime.add(base_time, i * 3600, :second)

        {:ok, _} =
          TripleStoreAdapter.persist(
            create_memory(%{id: "fact-#{i}", memory_type: :fact, created_at: timestamp}),
            store
          )
      end

      {:ok, facts} = TripleStoreAdapter.query_by_type(store, "session-123", :fact)

      timestamps = Enum.map(facts, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, {:desc, DateTime})
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

    test "respects min_confidence option", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "high-conf", confidence: 0.9}), store)
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "low-conf", confidence: 0.3}), store)

      {:ok, high_conf_memories} = TripleStoreAdapter.query_all(store, "session-123", min_confidence: 0.7)

      assert length(high_conf_memories) == 1
      assert hd(high_conf_memories).id == "high-conf"
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

    test "combines multiple options", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(
          create_memory(%{id: "match", memory_type: :fact, confidence: 0.9}),
          store
        )

      {:ok, _} =
        TripleStoreAdapter.persist(
          create_memory(%{id: "low-conf", memory_type: :fact, confidence: 0.3}),
          store
        )

      {:ok, _} =
        TripleStoreAdapter.persist(
          create_memory(%{id: "wrong-type", memory_type: :assumption, confidence: 0.9}),
          store
        )

      {:ok, memories} =
        TripleStoreAdapter.query_all(store, "session-123", type: :fact, min_confidence: 0.7)

      assert length(memories) == 1
      assert hd(memories).id == "match"
    end
  end

  # =============================================================================
  # query_by_id/2 Tests
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
      :ok = TripleStoreAdapter.supersede(store, "session-123", "superseded-mem", nil)

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "superseded-mem")

      assert memory.id == "superseded-mem"
      assert memory.superseded_by == nil
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

    test "allows nil for new_memory_id", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "obsolete-mem"}), store)

      :ok = TripleStoreAdapter.supersede(store, "session-123", "obsolete-mem", nil)

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "obsolete-mem")
      # Still marked as superseded (excluded from queries) but no replacement
      assert memory.superseded_by == nil
    end

    test "returns :not_found for unknown memory", %{store: store} do
      assert {:error, :not_found} = TripleStoreAdapter.supersede(store, "session-123", "unknown", nil)
    end

    test "returns :session_mismatch for wrong session", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      assert {:error, :session_mismatch} =
               TripleStoreAdapter.supersede(store, "session-2", "mem", nil)
    end
  end

  # =============================================================================
  # delete/3 Tests
  # =============================================================================

  describe "delete/3" do
    test "removes memory from store", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "delete-me"}), store)

      :ok = TripleStoreAdapter.delete(store, "session-123", "delete-me")

      assert {:error, :not_found} = TripleStoreAdapter.query_by_id(store, "delete-me")
    end

    test "returns :ok for unknown memory", %{store: store} do
      assert :ok = TripleStoreAdapter.delete(store, "session-123", "unknown")
    end

    test "returns :session_mismatch for wrong session", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      assert {:error, :session_mismatch} = TripleStoreAdapter.delete(store, "session-2", "mem")
    end
  end

  # =============================================================================
  # record_access/3 Tests
  # =============================================================================

  describe "record_access/3" do
    test "increments access count", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "accessed-mem"}), store)

      :ok = TripleStoreAdapter.record_access(store, "session-123", "accessed-mem")
      :ok = TripleStoreAdapter.record_access(store, "session-123", "accessed-mem")
      :ok = TripleStoreAdapter.record_access(store, "session-123", "accessed-mem")

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "accessed-mem")
      assert memory.access_count == 3
    end

    test "updates last_accessed timestamp", %{store: store} do
      {:ok, _} = TripleStoreAdapter.persist(create_memory(%{id: "timestamp-mem"}), store)

      {:ok, before_access} = TripleStoreAdapter.query_by_id(store, "timestamp-mem")
      assert before_access.last_accessed == nil

      :ok = TripleStoreAdapter.record_access(store, "session-123", "timestamp-mem")

      {:ok, after_access} = TripleStoreAdapter.query_by_id(store, "timestamp-mem")
      assert after_access.last_accessed != nil
    end

    test "returns :ok for unknown memory", %{store: store} do
      assert :ok = TripleStoreAdapter.record_access(store, "session-123", "unknown")
    end

    test "ignores access for wrong session", %{store: store} do
      {:ok, _} =
        TripleStoreAdapter.persist(create_memory(%{id: "mem", session_id: "session-1"}), store)

      :ok = TripleStoreAdapter.record_access(store, "session-2", "mem")

      {:ok, memory} = TripleStoreAdapter.query_by_id(store, "mem")
      assert memory.access_count == 0
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
      iri = Vocab.memory_uri("test-123")

      assert TripleStoreAdapter.extract_id(iri) == "test-123"
    end

    test "returns input if not a valid memory IRI" do
      assert TripleStoreAdapter.extract_id("not-an-iri") == "not-an-iri"
      assert TripleStoreAdapter.extract_id("https://other.com/memory_123") == "https://other.com/memory_123"
    end
  end

  # =============================================================================
  # memory_iri/1 Tests
  # =============================================================================

  describe "memory_iri/1" do
    test "generates correct IRI for ID" do
      iri = TripleStoreAdapter.memory_iri("my-memory-id")

      expected = Vocab.namespace() <> "memory_my-memory-id"
      assert iri == expected
    end
  end

  # =============================================================================
  # Edge Cases and Error Handling
  # =============================================================================

  describe "error handling" do
    test "handles invalid store in query operations" do
      assert {:error, :not_found} = TripleStoreAdapter.query_by_id(:invalid_table, "mem-1")
    end
  end

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
end
