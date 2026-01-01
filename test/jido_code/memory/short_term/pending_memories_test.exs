defmodule JidoCode.Memory.ShortTerm.PendingMemoriesTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.ShortTerm.PendingMemories

  # Helper to create a valid item map
  defp make_item(overrides \\ %{}) do
    Map.merge(
      %{
        content: "Test content",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: [],
        rationale: nil,
        importance_score: 0.5,
        created_at: DateTime.utc_now(),
        access_count: 0
      },
      overrides
    )
  end

  describe "new/0" do
    test "creates empty pending memories with default max_items" do
      pending = PendingMemories.new()

      assert pending.max_items == 500
      assert pending.items == %{}
      assert pending.agent_decisions == []
    end
  end

  describe "new/1" do
    test "accepts custom max_items value" do
      pending = PendingMemories.new(100)

      assert pending.max_items == 100
      assert pending.items == %{}
    end

    test "creates pending memories with various max_items values" do
      assert PendingMemories.new(50).max_items == 50
      assert PendingMemories.new(1000).max_items == 1000
    end
  end

  describe "add_implicit/2" do
    test "adds item to items map" do
      pending = PendingMemories.new()
      item = make_item(%{id: "test-1"})

      pending = PendingMemories.add_implicit(pending, item)

      assert map_size(pending.items) == 1
      assert pending.items["test-1"].content == "Test content"
    end

    test "generates unique id if not provided" do
      pending = PendingMemories.new()
      item = make_item() |> Map.delete(:id)

      pending = PendingMemories.add_implicit(pending, item)

      assert map_size(pending.items) == 1
      [id] = Map.keys(pending.items)
      assert String.starts_with?(id, "pending-")
    end

    test "sets suggested_by to :implicit" do
      pending = PendingMemories.new()
      item = make_item(%{id: "test-1"})

      pending = PendingMemories.add_implicit(pending, item)

      assert pending.items["test-1"].suggested_by == :implicit
    end

    test "enforces max_items limit by evicting lowest score" do
      pending = PendingMemories.new(3)

      # Add 3 items with different scores
      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "low", importance_score: 0.3}))
        |> PendingMemories.add_implicit(make_item(%{id: "medium", importance_score: 0.5}))
        |> PendingMemories.add_implicit(make_item(%{id: "high", importance_score: 0.8}))

      assert map_size(pending.items) == 3

      # Add a 4th item, should evict the lowest score
      pending = PendingMemories.add_implicit(pending, make_item(%{id: "new", importance_score: 0.6}))

      assert map_size(pending.items) == 3
      refute Map.has_key?(pending.items, "low")
      assert Map.has_key?(pending.items, "medium")
      assert Map.has_key?(pending.items, "high")
      assert Map.has_key?(pending.items, "new")
    end

    test "uses default importance_score of 0.5 if not provided" do
      pending = PendingMemories.new()
      item = make_item(%{id: "test-1"}) |> Map.delete(:importance_score)

      pending = PendingMemories.add_implicit(pending, item)

      assert pending.items["test-1"].importance_score == 0.5
    end

    test "preserves all provided fields" do
      pending = PendingMemories.new()
      now = DateTime.utc_now()

      item = %{
        id: "test-1",
        content: "Specific content",
        memory_type: :discovery,
        confidence: 0.75,
        source_type: :agent,
        evidence: ["evidence1", "evidence2"],
        rationale: "Some rationale",
        importance_score: 0.9,
        created_at: now,
        access_count: 5
      }

      pending = PendingMemories.add_implicit(pending, item)
      stored = pending.items["test-1"]

      assert stored.content == "Specific content"
      assert stored.memory_type == :discovery
      assert stored.confidence == 0.75
      assert stored.source_type == :agent
      assert stored.evidence == ["evidence1", "evidence2"]
      assert stored.rationale == "Some rationale"
      assert stored.importance_score == 0.9
      assert stored.created_at == now
      assert stored.access_count == 5
    end
  end

  describe "add_agent_decision/2" do
    test "adds to agent_decisions list" do
      pending = PendingMemories.new()
      item = make_item(%{id: "agent-1"})

      pending = PendingMemories.add_agent_decision(pending, item)

      assert length(pending.agent_decisions) == 1
    end

    test "sets suggested_by to :agent" do
      pending = PendingMemories.new()
      item = make_item(%{id: "agent-1"})

      pending = PendingMemories.add_agent_decision(pending, item)

      [decision] = pending.agent_decisions
      assert decision.suggested_by == :agent
    end

    test "sets importance_score to 1.0" do
      pending = PendingMemories.new()
      # Even if we provide a lower score, it should be overridden
      item = make_item(%{id: "agent-1", importance_score: 0.3})

      pending = PendingMemories.add_agent_decision(pending, item)

      [decision] = pending.agent_decisions
      assert decision.importance_score == 1.0
    end

    test "generates unique id if not provided" do
      pending = PendingMemories.new()
      item = make_item() |> Map.delete(:id)

      pending = PendingMemories.add_agent_decision(pending, item)

      [decision] = pending.agent_decisions
      assert String.starts_with?(decision.id, "pending-")
    end

    test "does not affect max_items limit (agent decisions are separate)" do
      pending = PendingMemories.new(2)

      # Fill up implicit items
      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "imp-1"}))
        |> PendingMemories.add_implicit(make_item(%{id: "imp-2"}))

      # Add agent decision - should not trigger eviction
      pending = PendingMemories.add_agent_decision(pending, make_item(%{id: "agent-1"}))

      assert map_size(pending.items) == 2
      assert length(pending.agent_decisions) == 1
    end
  end

  describe "ready_for_promotion/2" do
    test "returns items above default threshold (0.6)" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "low", importance_score: 0.4}))
        |> PendingMemories.add_implicit(make_item(%{id: "high", importance_score: 0.7}))

      ready = PendingMemories.ready_for_promotion(pending)

      assert length(ready) == 1
      assert hd(ready).id == "high"
    end

    test "returns items with exact threshold score" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "exact", importance_score: 0.6}))

      ready = PendingMemories.ready_for_promotion(pending, 0.6)

      assert length(ready) == 1
    end

    test "with custom threshold" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "low", importance_score: 0.4}))
        |> PendingMemories.add_implicit(make_item(%{id: "medium", importance_score: 0.5}))
        |> PendingMemories.add_implicit(make_item(%{id: "high", importance_score: 0.7}))

      # With lower threshold
      ready = PendingMemories.ready_for_promotion(pending, 0.4)
      assert length(ready) == 3

      # With higher threshold
      ready = PendingMemories.ready_for_promotion(pending, 0.65)
      assert length(ready) == 1
    end

    test "always includes agent_decisions regardless of threshold" do
      pending = PendingMemories.new()

      # Agent decision would normally be below threshold if it had score 0.3
      # But agent decisions always have score 1.0 anyway
      pending = PendingMemories.add_agent_decision(pending, make_item(%{id: "agent-1"}))

      # Even with high threshold, agent decision is included
      ready = PendingMemories.ready_for_promotion(pending, 0.9)

      assert length(ready) == 1
      assert hd(ready).id == "agent-1"
    end

    test "sorts by importance_score descending" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "medium", importance_score: 0.7}))
        |> PendingMemories.add_implicit(make_item(%{id: "low", importance_score: 0.6}))
        |> PendingMemories.add_implicit(make_item(%{id: "high", importance_score: 0.9}))

      ready = PendingMemories.ready_for_promotion(pending, 0.6)
      ids = Enum.map(ready, & &1.id)

      assert ids == ["high", "medium", "low"]
    end

    test "combines implicit items and agent decisions sorted together" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "imp-high", importance_score: 0.9}))
        |> PendingMemories.add_implicit(make_item(%{id: "imp-low", importance_score: 0.6}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-1"}))

      ready = PendingMemories.ready_for_promotion(pending, 0.6)

      # Agent decision has score 1.0, so it should be first
      assert length(ready) == 3
      [first, second, third] = ready
      assert first.id == "agent-1"
      assert first.importance_score == 1.0
      assert second.id == "imp-high"
      assert third.id == "imp-low"
    end

    test "returns empty list when no items meet threshold" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "low", importance_score: 0.3}))

      ready = PendingMemories.ready_for_promotion(pending, 0.6)

      assert ready == []
    end
  end

  describe "clear_promoted/2" do
    test "removes specified ids from items" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "keep"}))
        |> PendingMemories.add_implicit(make_item(%{id: "remove-1"}))
        |> PendingMemories.add_implicit(make_item(%{id: "remove-2"}))

      pending = PendingMemories.clear_promoted(pending, ["remove-1", "remove-2"])

      assert map_size(pending.items) == 1
      assert Map.has_key?(pending.items, "keep")
    end

    test "clears agent_decisions list" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-1"}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-2"}))

      assert length(pending.agent_decisions) == 2

      pending = PendingMemories.clear_promoted(pending, [])

      assert pending.agent_decisions == []
    end

    test "handles non-existent ids gracefully" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "exists"}))

      # Should not raise
      pending = PendingMemories.clear_promoted(pending, ["nonexistent", "also-nonexistent"])

      assert map_size(pending.items) == 1
      assert Map.has_key?(pending.items, "exists")
    end
  end

  describe "get/2" do
    test "returns pending item by id from items map" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "test-1", content: "Found it"}))

      item = PendingMemories.get(pending, "test-1")

      assert item.content == "Found it"
    end

    test "returns pending item by id from agent_decisions" do
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_agent_decision(pending, make_item(%{id: "agent-1", content: "Agent item"}))

      item = PendingMemories.get(pending, "agent-1")

      assert item.content == "Agent item"
    end

    test "returns nil for non-existent id" do
      pending = PendingMemories.new()

      assert PendingMemories.get(pending, "nonexistent") == nil
    end

    test "prefers items map over agent_decisions for same id" do
      pending = PendingMemories.new()

      # This is an edge case that shouldn't happen in practice
      pending = PendingMemories.add_implicit(pending, make_item(%{id: "same-id", content: "Implicit"}))
      # Manually add to agent_decisions with same id (not normal usage)
      agent_item = %{
        id: "same-id",
        content: "Agent",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: [],
        rationale: nil,
        suggested_by: :agent,
        importance_score: 1.0,
        created_at: DateTime.utc_now(),
        access_count: 0
      }

      pending = %{pending | agent_decisions: [agent_item | pending.agent_decisions]}

      item = PendingMemories.get(pending, "same-id")

      # Should return the implicit one (items map checked first)
      assert item.content == "Implicit"
    end
  end

  describe "size/1" do
    test "returns correct total count" do
      pending = PendingMemories.new()

      assert PendingMemories.size(pending) == 0

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "imp-1"}))
      assert PendingMemories.size(pending) == 1

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "imp-2"}))
      assert PendingMemories.size(pending) == 2

      pending = PendingMemories.add_agent_decision(pending, make_item(%{id: "agent-1"}))
      assert PendingMemories.size(pending) == 3
    end
  end

  describe "update_score/3" do
    test "updates importance_score for existing item" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "test-1", importance_score: 0.5}))
      assert pending.items["test-1"].importance_score == 0.5

      pending = PendingMemories.update_score(pending, "test-1", 0.8)
      assert pending.items["test-1"].importance_score == 0.8
    end

    test "does nothing for non-existent id" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "exists"}))

      # Should not raise, should return unchanged
      updated = PendingMemories.update_score(pending, "nonexistent", 0.9)

      assert updated == pending
    end

    test "clamps score to valid range" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_implicit(pending, make_item(%{id: "test-1"}))

      pending = PendingMemories.update_score(pending, "test-1", 1.5)
      assert pending.items["test-1"].importance_score == 1.0

      pending = PendingMemories.update_score(pending, "test-1", -0.5)
      assert pending.items["test-1"].importance_score == 0.0
    end

    test "does not affect agent_decisions" do
      pending = PendingMemories.new()

      pending = PendingMemories.add_agent_decision(pending, make_item(%{id: "agent-1"}))

      # This should do nothing since update_score only works on implicit items
      pending = PendingMemories.update_score(pending, "agent-1", 0.5)

      [decision] = pending.agent_decisions
      assert decision.importance_score == 1.0
    end
  end

  describe "eviction" do
    test "removes item with lowest importance_score when limit exceeded" do
      pending = PendingMemories.new(2)

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "a", importance_score: 0.5}))
        |> PendingMemories.add_implicit(make_item(%{id: "b", importance_score: 0.3}))

      assert map_size(pending.items) == 2

      # Adding third item should evict "b" (lowest score)
      pending = PendingMemories.add_implicit(pending, make_item(%{id: "c", importance_score: 0.4}))

      assert map_size(pending.items) == 2
      assert Map.has_key?(pending.items, "a")
      assert Map.has_key?(pending.items, "c")
      refute Map.has_key?(pending.items, "b")
    end

    test "evicts correctly when new item has lowest score" do
      pending = PendingMemories.new(2)

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "a", importance_score: 0.5}))
        |> PendingMemories.add_implicit(make_item(%{id: "b", importance_score: 0.6}))

      # New item has lower score than existing items
      pending = PendingMemories.add_implicit(pending, make_item(%{id: "c", importance_score: 0.3}))

      # The new item should be added first, then eviction happens
      # After eviction, "c" (lowest) should be removed
      assert map_size(pending.items) == 2
      assert Map.has_key?(pending.items, "a")
      assert Map.has_key?(pending.items, "b")
      refute Map.has_key?(pending.items, "c")
    end
  end

  describe "list_implicit/1" do
    test "returns all implicit items as list" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "imp-1"}))
        |> PendingMemories.add_implicit(make_item(%{id: "imp-2"}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-1"}))

      items = PendingMemories.list_implicit(pending)

      assert length(items) == 2
      ids = Enum.map(items, & &1.id)
      assert "imp-1" in ids
      assert "imp-2" in ids
    end
  end

  describe "list_agent_decisions/1" do
    test "returns all agent decisions as list" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "imp-1"}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-1"}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-2"}))

      decisions = PendingMemories.list_agent_decisions(pending)

      assert length(decisions) == 2
      ids = Enum.map(decisions, & &1.id)
      assert "agent-1" in ids
      assert "agent-2" in ids
    end
  end

  describe "clear/1" do
    test "clears all pending items" do
      pending = PendingMemories.new()

      pending =
        pending
        |> PendingMemories.add_implicit(make_item(%{id: "imp-1"}))
        |> PendingMemories.add_agent_decision(make_item(%{id: "agent-1"}))

      assert PendingMemories.size(pending) == 2

      pending = PendingMemories.clear(pending)

      assert PendingMemories.size(pending) == 0
      assert pending.items == %{}
      assert pending.agent_decisions == []
    end
  end

  describe "generate_id/0" do
    test "generates unique ids" do
      ids = for _ <- 1..100, do: PendingMemories.generate_id()
      unique_ids = Enum.uniq(ids)

      assert length(unique_ids) == 100
    end

    test "generates ids with expected prefix" do
      id = PendingMemories.generate_id()
      assert String.starts_with?(id, "pending-")
    end
  end
end
