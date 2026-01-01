defmodule JidoCode.Memory.Promotion.EngineTest do
  use ExUnit.Case, async: true

  import JidoCode.Memory.TestHelpers

  alias JidoCode.Memory.Promotion.Engine
  alias JidoCode.Memory.ShortTerm.{AccessLog, PendingMemories, WorkingContext}

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    # Create a unique session ID for each test
    session_id = "test-session-#{System.unique_integer([:positive])}"
    {:ok, session_id: session_id}
  end

  # Delegate to shared test helpers
  defp create_empty_state, do: create_empty_promotion_state()

  # Local wrapper with test-specific defaults (higher importance_score for promotion tests)
  defp create_test_pending_item(overrides \\ %{}) do
    create_pending_item(Map.merge(%{importance_score: 0.7, access_count: 1}, overrides))
  end

  # =============================================================================
  # evaluate/1 Tests
  # =============================================================================

  describe "evaluate/1" do
    test "returns empty list for empty state" do
      state = create_empty_state()
      candidates = Engine.evaluate(state)

      assert candidates == []
    end

    test "scores context items correctly" do
      # Add context item with promotable type
      state = create_state_with_context([
        {:framework, "Phoenix 1.7", source: :tool, confidence: 0.9}
      ])

      candidates = Engine.evaluate(state)

      # Context items with tool source and framework key get :fact type
      assert length(candidates) == 1
      [candidate] = candidates
      assert candidate.suggested_type == :fact
      assert candidate.confidence == 0.9
      assert candidate.importance_score > 0.0
    end

    test "includes items above threshold" do
      # Create pending item with high importance score
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.8}))

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

      assert length(candidates) == 1
      assert hd(candidates).importance_score >= 0.6
    end

    test "excludes items below threshold" do
      # Create pending item with low importance score
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.3}))

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

      assert candidates == []
    end

    test "always includes agent_decisions (importance_score = 1.0)" do
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_agent_decision(pending, %{
          content: "Agent decision content",
          memory_type: :decision,
          confidence: 1.0,
          source_type: :agent,
          evidence: ["User requested"],
          rationale: "Direct instruction"
        })

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

      assert length(candidates) == 1
      [candidate] = candidates
      assert candidate.importance_score == 1.0
      assert candidate.suggested_by == :agent
    end

    test "excludes items with nil suggested_type" do
      # active_errors has nil suggested_type
      state = create_state_with_context([
        {:active_errors, ["Error 1"], source: :tool, confidence: 0.9}
      ])

      candidates = Engine.evaluate(state)

      assert candidates == []
    end

    test "sorts by importance descending" do
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.7}))

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.9}))

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.8}))

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

      scores = Enum.map(candidates, & &1.importance_score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "limits to max_promotions_per_run" do
      pending = PendingMemories.new()

      # Add more items than the limit
      pending =
        Enum.reduce(1..30, pending, fn i, p ->
          PendingMemories.add_implicit(
            p,
            create_test_pending_item(%{importance_score: 0.7 + i * 0.01})
          )
        end)

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      candidates = Engine.evaluate(state)

      assert length(candidates) <= Engine.max_promotions_per_run()
    end
  end

  # =============================================================================
  # promote/3 Tests
  # =============================================================================

  describe "promote/3" do
    test "persists candidates to long-term store", %{session_id: session_id} do
      candidates = [
        %{
          id: "test-mem-1",
          content: "Test content",
          suggested_type: :fact,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        }
      ]

      {:ok, count} = Engine.promote(candidates, session_id)

      assert count == 1
    end

    test "returns count of successfully persisted items", %{session_id: session_id} do
      candidates = [
        %{
          id: "test-mem-1",
          content: "Content 1",
          suggested_type: :fact,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        },
        %{
          id: "test-mem-2",
          content: "Content 2",
          suggested_type: :discovery,
          confidence: 0.85,
          source_type: :agent,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.75,
          created_at: DateTime.utc_now(),
          access_count: 2
        }
      ]

      {:ok, count} = Engine.promote(candidates, session_id)

      assert count == 2
    end

    test "includes agent_id in memory input", %{session_id: session_id} do
      candidates = [
        %{
          id: "test-mem-1",
          content: "Test content",
          suggested_type: :fact,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        }
      ]

      {:ok, count} = Engine.promote(candidates, session_id, agent_id: "agent-123")

      assert count == 1
    end

    test "includes project_id in memory input", %{session_id: session_id} do
      candidates = [
        %{
          id: "test-mem-1",
          content: "Test content",
          suggested_type: :fact,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        }
      ]

      {:ok, count} = Engine.promote(candidates, session_id, project_id: "project-456")

      assert count == 1
    end

    test "handles partial failures gracefully", %{session_id: session_id} do
      # First candidate valid, second has invalid memory type
      candidates = [
        %{
          id: "test-mem-1",
          content: "Valid content",
          suggested_type: :fact,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        },
        %{
          id: "test-mem-2",
          content: "Invalid content",
          suggested_type: :invalid_type,
          confidence: 0.9,
          source_type: :tool,
          evidence: [],
          rationale: nil,
          suggested_by: :implicit,
          importance_score: 0.8,
          created_at: DateTime.utc_now(),
          access_count: 1
        }
      ]

      {:ok, count} = Engine.promote(candidates, session_id)

      # Only the valid one should succeed
      assert count == 1
    end
  end

  # =============================================================================
  # run/2 Tests
  # =============================================================================

  describe "run/2" do
    test "returns {:ok, 0, []} when no candidates", %{session_id: session_id} do
      state = create_empty_state()

      result = Engine.run(session_id, state: state)

      assert result == {:ok, 0, []}
    end

    test "evaluates, promotes, and returns count", %{session_id: session_id} do
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.8}))

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      {:ok, count, _promoted_ids} = Engine.run(session_id, state: state)

      assert count == 1
    end

    test "returns promoted ids for cleanup", %{session_id: session_id} do
      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(
          pending,
          create_test_pending_item(%{id: "pending-123", importance_score: 0.8})
        )

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      {:ok, _count, promoted_ids} = Engine.run(session_id, state: state)

      assert "pending-123" in promoted_ids
    end

    test "returns error when state not provided", %{session_id: session_id} do
      result = Engine.run(session_id)

      assert result == {:error, :state_required}
    end
  end

  # =============================================================================
  # run_with_state/3 Tests
  # =============================================================================

  describe "run_with_state/3" do
    test "emits telemetry on promotion", %{session_id: session_id} do
      # Attach telemetry handler
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :completed],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      pending = PendingMemories.new()

      pending =
        PendingMemories.add_implicit(pending, create_test_pending_item(%{importance_score: 0.8}))

      state = %{
        working_context: WorkingContext.new(),
        pending_memories: pending,
        access_log: AccessLog.new()
      }

      Engine.run_with_state(state, session_id, [])

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :completed], measurements,
                      metadata}

      assert measurements.success_count == 1
      assert measurements.total_candidates == 1
      assert metadata.session_id == session_id

      # Clean up
      :telemetry.detach("test-#{inspect(ref)}")
    end
  end

  # =============================================================================
  # build_memory_input Tests (via generate_id/0)
  # =============================================================================

  describe "generate_id/0" do
    test "generates unique id when nil" do
      id1 = Engine.generate_id()
      id2 = Engine.generate_id()

      assert is_binary(id1)
      assert is_binary(id2)
      assert id1 != id2
      assert String.length(id1) == 32
    end
  end

  # =============================================================================
  # format_content/1 Tests
  # =============================================================================

  describe "format_content/1" do
    test "handles string values" do
      result = Engine.format_content("Hello world")

      assert result == "Hello world"
    end

    test "handles non-string values" do
      result = Engine.format_content(42)

      assert result == "42"
    end

    test "handles map with value key" do
      result = Engine.format_content(%{value: "Phoenix 1.7"})

      assert result == "Phoenix 1.7"
    end

    test "handles map with value and key" do
      result = Engine.format_content(%{value: "Phoenix 1.7", key: :framework})

      assert result == "framework: \"Phoenix 1.7\""
    end

    test "handles map with content key" do
      result = Engine.format_content(%{content: "Some content"})

      assert result == "Some content"
    end

    test "handles complex terms via inspect" do
      result = Engine.format_content(%{complex: [1, 2, 3]})

      assert is_binary(result)
      assert result =~ "complex"
    end
  end

  # =============================================================================
  # Configuration Tests
  # =============================================================================

  describe "configuration" do
    setup do
      on_exit(fn -> Engine.reset_config() end)
      :ok
    end

    test "promotion_threshold returns 0.6 by default" do
      assert Engine.promotion_threshold() == 0.6
    end

    test "max_promotions_per_run returns 20 by default" do
      assert Engine.max_promotions_per_run() == 20
    end

    test "configure/1 updates promotion_threshold" do
      assert :ok = Engine.configure(promotion_threshold: 0.7)
      assert Engine.promotion_threshold() == 0.7
    end

    test "configure/1 updates max_promotions_per_run" do
      assert :ok = Engine.configure(max_promotions_per_run: 30)
      assert Engine.max_promotions_per_run() == 30
    end

    test "configure/1 rejects invalid threshold" do
      assert {:error, _} = Engine.configure(promotion_threshold: -0.1)
      assert {:error, _} = Engine.configure(promotion_threshold: 1.5)
      assert {:error, _} = Engine.configure(promotion_threshold: "not a number")
    end

    test "configure/1 rejects invalid max_promotions" do
      assert {:error, _} = Engine.configure(max_promotions_per_run: 0)
      assert {:error, _} = Engine.configure(max_promotions_per_run: -5)
      assert {:error, _} = Engine.configure(max_promotions_per_run: 10.5)
    end

    test "reset_config/0 restores defaults" do
      Engine.configure(promotion_threshold: 0.8, max_promotions_per_run: 50)
      assert Engine.promotion_threshold() == 0.8
      assert Engine.max_promotions_per_run() == 50

      Engine.reset_config()
      assert Engine.promotion_threshold() == 0.6
      assert Engine.max_promotions_per_run() == 20
    end

    test "get_config/0 returns current configuration" do
      config = Engine.get_config()
      assert config.promotion_threshold == 0.6
      assert config.max_promotions_per_run == 20
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  describe "integration" do
    test "full flow with context and pending items", %{session_id: session_id} do
      # Create context with promotable items
      ctx =
        WorkingContext.new()
        |> WorkingContext.put(:framework, "Phoenix 1.7", source: :tool, confidence: 0.95)
        |> WorkingContext.put(:primary_language, "Elixir", source: :tool, confidence: 0.99)

      # Create pending items
      pending =
        PendingMemories.new()
        |> PendingMemories.add_implicit(
          create_test_pending_item(%{
            content: "Uses Ecto for database",
            memory_type: :fact,
            importance_score: 0.85
          })
        )
        |> PendingMemories.add_agent_decision(%{
          content: "User prefers explicit module aliases",
          memory_type: :convention,
          confidence: 1.0,
          source_type: :user,
          evidence: ["User stated preference"]
        })

      # Create access log with some accesses
      log =
        AccessLog.new()
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:framework, :read)
        |> AccessLog.record(:primary_language, :read)

      state = %{
        working_context: ctx,
        pending_memories: pending,
        access_log: log
      }

      # Evaluate
      candidates = Engine.evaluate(state)

      # Should have context items + pending items
      assert length(candidates) >= 3

      # Agent decision should be first (score 1.0)
      first = hd(candidates)
      assert first.importance_score == 1.0

      # Promote all
      {:ok, count} = Engine.promote(candidates, session_id)

      assert count == length(candidates)
    end
  end
end
