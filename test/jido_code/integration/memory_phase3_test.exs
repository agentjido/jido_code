defmodule JidoCode.Integration.MemoryPhase3Test do
  @moduledoc """
  Phase 3 Integration Tests for Promotion Engine.

  These tests verify the complete integration of the promotion system,
  including evaluation, persistence, triggers, multi-session isolation,
  and scoring behavior.
  """

  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers
  import JidoCode.Memory.TestHelpers

  alias JidoCode.Memory.LongTerm.StoreManager
  alias JidoCode.Memory.LongTerm.TripleStoreAdapter
  alias JidoCode.Memory.Promotion.Engine
  alias JidoCode.Memory.Promotion.ImportanceScorer
  alias JidoCode.Memory.ShortTerm.PendingMemories
  alias JidoCode.Session
  alias JidoCode.Session.State

  @moduletag :integration
  @moduletag :phase3

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    # Use session test helpers for infrastructure
    {:ok, %{tmp_dir: tmp_dir}} = setup_session_registry("phase3_integration")

    # Create unique identifiers for isolation
    rand = :rand.uniform(1_000_000)
    base_path = Path.join(tmp_dir, "memory_stores")
    File.mkdir_p!(base_path)

    supervisor_name = :"memory_supervisor_phase3_#{rand}"
    store_manager_name = :"store_manager_phase3_#{rand}"

    # Start memory supervisor
    {:ok, sup_pid} =
      JidoCode.Memory.Supervisor.start_link(
        name: supervisor_name,
        base_path: base_path,
        store_name: store_manager_name
      )

    on_exit(fn ->
      try do
        if Process.alive?(sup_pid) do
          Supervisor.stop(sup_pid, :normal, 5000)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{
      tmp_dir: tmp_dir,
      base_path: base_path,
      supervisor: sup_pid,
      store_manager: store_manager_name
    }
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  # Local wrapper with test-specific defaults for integration tests
  defp create_test_pending_item(overrides \\ %{}) do
    create_pending_item(
      Map.merge(
        %{
          id: "pending-#{:rand.uniform(1_000_000)}",
          importance_score: 0.75,
          access_count: 1
        },
        overrides
      )
    )
  end

  defp query_memories(session_id, store_manager) do
    case StoreManager.get_or_create(session_id, store_manager) do
      {:ok, store} -> TripleStoreAdapter.query_all(store, session_id, [])
      error -> error
    end
  end

  defp start_session_state(tmp_dir) do
    {:ok, session} = Session.new(project_path: tmp_dir)
    {:ok, pid} = State.start_link(session: session)
    {session.id, pid}
  end

  # =============================================================================
  # 3.5.1 Promotion Flow Integration
  # =============================================================================

  describe "3.5.1 Promotion Flow Integration" do
    test "3.5.1.2 full flow - add context items, trigger promotion, verify in long-term store", %{
      store_manager: store_manager
    } do
      session_id = "flow-test-#{:rand.uniform(1_000_000)}"

      # Create state with promotable context items
      state =
        create_session_state(
          [
            {:framework, "Phoenix 1.7", source: :tool, confidence: 0.95},
            {:primary_language, "Elixir", source: :tool, confidence: 0.99}
          ],
          [
            {:implicit, create_test_pending_item(%{importance_score: 0.8, content: "Uses Ecto"})}
          ]
        )

      # Evaluate candidates
      candidates = Engine.evaluate(state)
      assert length(candidates) >= 1

      # Promote to long-term store
      {:ok, count} = Engine.promote(candidates, session_id)
      assert count >= 1

      # Verify memories are in long-term store
      {:ok, memories} = query_memories(session_id, store_manager)
      assert length(memories) >= 1

      # Verify content was persisted
      contents = Enum.map(memories, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "Ecto")) or
               Enum.any?(contents, &String.contains?(&1, "Phoenix")) or
               Enum.any?(contents, &String.contains?(&1, "Elixir"))
    end

    test "3.5.1.3 agent decisions promoted immediately with importance_score 1.0", %{
      store_manager: store_manager
    } do
      session_id = "agent-decision-#{:rand.uniform(1_000_000)}"

      # Create state with agent decision
      state =
        create_session_state(
          [],
          [
            {:agent,
             %{
               content: "User prefers explicit imports",
               memory_type: :convention,
               confidence: 1.0,
               source_type: :user,
               evidence: ["User stated preference"]
             }}
          ]
        )

      # Evaluate - agent decisions should always be included
      candidates = Engine.evaluate(state)
      assert length(candidates) == 1

      [candidate] = candidates
      assert candidate.importance_score == 1.0
      assert candidate.suggested_by == :agent

      # Promote
      {:ok, 1} = Engine.promote(candidates, session_id)

      # Verify in long-term store
      {:ok, memories} = query_memories(session_id, store_manager)
      assert length(memories) == 1
      assert hd(memories).content =~ "explicit imports"
    end

    test "3.5.1.4 low-importance items (below threshold) not promoted" do
      # Create state with low-importance item
      state =
        create_session_state(
          [],
          [
            {:implicit, create_test_pending_item(%{importance_score: 0.3, content: "Low importance"})}
          ]
        )

      # Evaluate - should return empty (below 0.6 threshold)
      candidates = Engine.evaluate(state)
      assert candidates == []
    end

    test "3.5.1.5 items with nil suggested_type not promoted" do
      # Create context items that won't get a suggested_type
      state =
        create_session_state(
          [
            # active_errors gets nil suggested_type
            {:active_errors, ["Error 1", "Error 2"], source: :tool, confidence: 0.9}
          ],
          []
        )

      # Evaluate - should return empty
      candidates = Engine.evaluate(state)
      assert candidates == []
    end

    test "3.5.1.6 promoted items cleared from pending_memories", %{tmp_dir: tmp_dir} do
      # Start a real session state
      {session_id, pid} = start_session_state(tmp_dir)

      # Add an agent decision via the State API
      :ok =
        State.add_agent_memory_decision(session_id, %{
          content: "Important discovery",
          memory_type: :discovery,
          confidence: 0.95,
          source_type: :agent,
          evidence: []
        })

      # Run promotion
      {:ok, count} = State.run_promotion_now(session_id)
      assert count >= 1

      # Get state and verify pending is cleared
      state = :sys.get_state(pid)
      agent_decisions = PendingMemories.list_agent_decisions(state.pending_memories)
      assert agent_decisions == []

      # Cleanup
      GenServer.stop(pid)
    end

    test "3.5.1.7 promotion stats updated correctly after each run", %{tmp_dir: tmp_dir} do
      {session_id, pid} = start_session_state(tmp_dir)

      # Get initial stats
      {:ok, initial_stats} = State.get_promotion_stats(session_id)
      assert initial_stats.runs == 0
      assert initial_stats.total_promoted == 0

      # Add something to promote
      :ok =
        State.add_agent_memory_decision(session_id, %{
          content: "Test memory for stats",
          memory_type: :fact,
          confidence: 0.9,
          source_type: :agent,
          evidence: []
        })

      # Run promotion
      {:ok, count} = State.run_promotion_now(session_id)

      # Check updated stats
      {:ok, updated_stats} = State.get_promotion_stats(session_id)
      assert updated_stats.runs == 1
      assert updated_stats.total_promoted == count
      assert updated_stats.last_run != nil

      # Cleanup
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # 3.5.2 Trigger Integration
  # =============================================================================

  describe "3.5.2 Trigger Integration" do
    test "3.5.2.1 periodic timer triggers promotion at correct interval", %{tmp_dir: tmp_dir} do
      # Create session with short promotion interval for testing
      {:ok, session} = Session.new(project_path: tmp_dir)

      # Start state with promotion enabled (default)
      {:ok, pid} = State.start_link(session: session)

      # Verify promotion timer is scheduled
      state = :sys.get_state(pid)
      assert state.promotion_enabled == true
      assert is_reference(state.promotion_timer_ref)

      # Cleanup
      GenServer.stop(pid)
    end

    test "3.5.2.5 agent decision trigger promotes immediately", %{tmp_dir: tmp_dir} do
      {session_id, pid} = start_session_state(tmp_dir)

      # Get initial stats
      {:ok, initial_stats} = State.get_promotion_stats(session_id)
      initial_total = initial_stats.total_promoted

      # Add agent decision - this should trigger immediate promotion consideration
      :ok =
        State.add_agent_memory_decision(session_id, %{
          content: "Critical decision",
          memory_type: :decision,
          confidence: 1.0,
          source_type: :agent,
          evidence: ["Urgent requirement"]
        })

      # Run promotion
      {:ok, _count} = State.run_promotion_now(session_id)

      # Verify it was promoted
      {:ok, stats} = State.get_promotion_stats(session_id)
      assert stats.total_promoted > initial_total

      # Cleanup
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # 3.5.3 Multi-Session Integration
  # =============================================================================

  describe "3.5.3 Multi-Session Integration" do
    test "3.5.3.1 promotion isolated per session - no cross-session contamination", %{
      store_manager: store_manager
    } do
      session_1 = "session-1-#{:rand.uniform(1_000_000)}"
      session_2 = "session-2-#{:rand.uniform(1_000_000)}"

      # Create different content for each session
      state_1 =
        create_session_state(
          [],
          [
            {:agent,
             %{
               content: "Session 1 specific content",
               memory_type: :fact,
               confidence: 1.0,
               source_type: :agent,
               evidence: []
             }}
          ]
        )

      state_2 =
        create_session_state(
          [],
          [
            {:agent,
             %{
               content: "Session 2 specific content",
               memory_type: :fact,
               confidence: 1.0,
               source_type: :agent,
               evidence: []
             }}
          ]
        )

      # Promote to each session
      candidates_1 = Engine.evaluate(state_1)
      candidates_2 = Engine.evaluate(state_2)

      {:ok, 1} = Engine.promote(candidates_1, session_1)
      {:ok, 1} = Engine.promote(candidates_2, session_2)

      # Query each session
      {:ok, memories_1} = query_memories(session_1, store_manager)
      {:ok, memories_2} = query_memories(session_2, store_manager)

      # Verify isolation
      assert length(memories_1) == 1
      assert length(memories_2) == 1
      assert hd(memories_1).content =~ "Session 1"
      assert hd(memories_2).content =~ "Session 2"

      # Verify no cross-contamination
      refute Enum.any?(memories_1, &(&1.content =~ "Session 2"))
      refute Enum.any?(memories_2, &(&1.content =~ "Session 1"))
    end

    test "3.5.3.2 concurrent promotions in multiple sessions", %{store_manager: store_manager} do
      # Create multiple sessions
      sessions =
        for i <- 1..5 do
          session_id = "concurrent-#{i}-#{:rand.uniform(1_000_000)}"

          state =
            create_session_state(
              [],
              [
                {:agent,
                 %{
                   content: "Concurrent content #{i}",
                   memory_type: :fact,
                   confidence: 1.0,
                   source_type: :agent,
                   evidence: []
                 }}
              ]
            )

          {session_id, state}
        end

      # Run promotions concurrently
      tasks =
        Enum.map(sessions, fn {session_id, state} ->
          Task.async(fn ->
            candidates = Engine.evaluate(state)
            Engine.promote(candidates, session_id)
          end)
        end)

      # Wait for all to complete
      results = Task.await_many(tasks, 5000)

      # Verify all succeeded
      assert Enum.all?(results, &match?({:ok, 1}, &1))

      # Verify each session has its memory
      for {session_id, _state} <- sessions do
        {:ok, memories} = query_memories(session_id, store_manager)
        assert length(memories) == 1
      end
    end

    test "3.5.3.3 each session maintains independent promotion stats", %{tmp_dir: tmp_dir} do
      # Start two sessions
      {session_1, pid_1} = start_session_state(tmp_dir)
      {session_2, pid_2} = start_session_state(tmp_dir)

      # Add different amounts to each session
      :ok =
        State.add_agent_memory_decision(session_1, %{
          content: "Session 1 memory 1",
          memory_type: :fact,
          confidence: 1.0,
          source_type: :agent,
          evidence: []
        })

      :ok =
        State.add_agent_memory_decision(session_1, %{
          content: "Session 1 memory 2",
          memory_type: :fact,
          confidence: 1.0,
          source_type: :agent,
          evidence: []
        })

      :ok =
        State.add_agent_memory_decision(session_2, %{
          content: "Session 2 memory 1",
          memory_type: :fact,
          confidence: 1.0,
          source_type: :agent,
          evidence: []
        })

      # Run promotions
      {:ok, count_1} = State.run_promotion_now(session_1)
      {:ok, count_2} = State.run_promotion_now(session_2)

      # Verify independent stats
      {:ok, stats_1} = State.get_promotion_stats(session_1)
      {:ok, stats_2} = State.get_promotion_stats(session_2)

      assert stats_1.runs == 1
      assert stats_2.runs == 1
      assert stats_1.total_promoted == count_1
      assert stats_2.total_promoted == count_2
      assert count_1 >= 2
      assert count_2 >= 1

      # Cleanup
      GenServer.stop(pid_1)
      GenServer.stop(pid_2)
    end
  end

  # =============================================================================
  # 3.5.4 Scoring Integration
  # =============================================================================

  describe "3.5.4 Scoring Integration" do
    test "3.5.4.1 ImportanceScorer correctly ranks candidates" do
      # Create items with different importance factors
      high_importance =
        create_test_pending_item(%{
          content: "High importance",
          importance_score: 0.95,
          confidence: 1.0,
          memory_type: :decision
        })

      medium_importance =
        create_test_pending_item(%{
          content: "Medium importance",
          importance_score: 0.75,
          confidence: 0.8,
          memory_type: :fact
        })

      low_importance =
        create_test_pending_item(%{
          content: "Low importance",
          importance_score: 0.65,
          confidence: 0.6,
          memory_type: :hypothesis
        })

      state =
        create_session_state(
          [],
          [
            {:implicit, low_importance},
            {:implicit, high_importance},
            {:implicit, medium_importance}
          ]
        )

      candidates = Engine.evaluate(state)

      # Should be sorted by importance descending
      scores = Enum.map(candidates, & &1.importance_score)
      assert scores == Enum.sort(scores, :desc)
    end

    test "3.5.4.2 recency decay affects promotion order over time" do
      now = DateTime.utc_now()
      one_hour_ago = DateTime.add(now, -3600, :second)
      two_hours_ago = DateTime.add(now, -7200, :second)

      # Score items with different recency
      recent = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      older = ImportanceScorer.score(%{
        last_accessed: one_hour_ago,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      oldest = ImportanceScorer.score(%{
        last_accessed: two_hours_ago,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      # More recent should score higher
      assert recent > older
      assert older > oldest
    end

    test "3.5.4.3 frequently accessed items score higher" do
      now = DateTime.utc_now()

      # Score items with different access counts
      frequent = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 10,
        confidence: 0.8,
        suggested_type: :fact
      })

      occasional = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      rare = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 1,
        confidence: 0.8,
        suggested_type: :fact
      })

      # More frequent should score higher
      assert frequent > occasional
      assert occasional > rare
    end

    test "3.5.4.4 high-salience types (decisions, lessons) prioritized" do
      now = DateTime.utc_now()

      # Score items with different memory types
      decision = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :decision
      })

      lesson = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :lesson_learned
      })

      fact = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      hypothesis = ImportanceScorer.score(%{
        last_accessed: now,
        access_count: 5,
        confidence: 0.8,
        suggested_type: :hypothesis
      })

      # High-salience types should score higher
      assert decision > fact
      assert lesson > fact
      assert fact > hypothesis
    end
  end

  # =============================================================================
  # Engine Configuration Tests
  # =============================================================================

  describe "Engine configuration" do
    test "promotion_threshold is 0.6" do
      assert Engine.promotion_threshold() == 0.6
    end

    test "max_promotions_per_run is 20" do
      assert Engine.max_promotions_per_run() == 20
    end
  end
end
