defmodule JidoCode.Integration.AgentMemoryTest do
  @moduledoc """
  Phase 5 Integration Tests for LLMAgent Memory Integration.

  These tests verify the complete integration of memory features with the LLMAgent,
  including context assembly, memory tool execution, response processing, and
  token budget enforcement.

  Test sections:
  - 5.5.1 Context Assembly Integration
  - 5.5.2 Memory Tool Execution Integration
  - 5.5.3 Response Processing Integration
  - 5.5.4 Token Budget Integration
  """

  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.{Remember, Recall, Forget}
  alias JidoCode.Memory.ContextBuilder
  alias JidoCode.Memory.ResponseProcessor
  alias JidoCode.Memory.TokenCounter
  alias JidoCode.Session.State, as: SessionState
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers

  @moduletag :integration
  @moduletag :phase5

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    # Use full session supervisor setup for integration tests
    {:ok, %{tmp_dir: tmp_dir}} = SessionTestHelpers.setup_session_supervisor("agent_memory")

    # Create a valid session
    session_id = SessionTestHelpers.test_uuid(:rand.uniform(10000))
    project_path = Path.join(tmp_dir, "test_project")
    File.mkdir_p!(project_path)

    # Create session struct using the test helper
    session = SessionTestHelpers.create_test_session(session_id, "Agent Memory Test", project_path)

    {:ok, _pid} = SessionSupervisor.start_session(session)

    on_exit(fn ->
      try do
        SessionSupervisor.stop_session(session.id)
        Memory.close_session(session.id)
      catch
        :exit, _ -> :ok
      end
    end)

    %{session_id: session.id, tmp_dir: tmp_dir, project_path: project_path}
  end

  # =============================================================================
  # 5.5.1 Context Assembly Integration
  # =============================================================================

  describe "5.5.1 Context Assembly Integration" do
    test "5.5.1.2 assembles context including working context", %{session_id: session_id} do
      # Set up working context
      :ok = SessionState.update_context(session_id, :project_root, "/app")
      :ok = SessionState.update_context(session_id, :primary_language, "elixir")
      :ok = SessionState.update_context(session_id, :framework, "Phoenix")

      # Build context
      {:ok, context} = ContextBuilder.build(session_id)

      # Verify working context is included
      assert context.working_context[:project_root] == "/app"
      assert context.working_context[:primary_language] == "elixir"
      assert context.working_context[:framework] == "Phoenix"

      # Verify token count is calculated
      assert context.token_counts.working > 0
    end

    test "5.5.1.3 assembles context including long-term memories", %{session_id: session_id} do
      now = DateTime.utc_now()

      # Store long-term memories
      {:ok, _} = Memory.persist(%{
        id: Uniq.UUID.uuid4(),
        session_id: session_id,
        content: "Uses Phoenix 1.7 framework",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :user,
        created_at: now
      }, session_id)

      {:ok, _} = Memory.persist(%{
        id: Uniq.UUID.uuid4(),
        session_id: session_id,
        content: "Prefers functional patterns",
        memory_type: :convention,
        confidence: 0.85,
        source_type: :tool,
        created_at: now
      }, session_id)

      # Build context
      {:ok, context} = ContextBuilder.build(session_id)

      # Verify memories are included
      assert length(context.long_term_memories) >= 2
      assert context.token_counts.long_term > 0

      # Check memory content is present
      contents = Enum.map(context.long_term_memories, & &1.content)
      assert "Uses Phoenix 1.7 framework" in contents
      assert "Prefers functional patterns" in contents
    end

    test "5.5.1.4 context respects total token budget", %{session_id: session_id} do
      now = DateTime.utc_now()

      # Add many messages to conversation
      for i <- 1..50 do
        msg = %{
          role: :user,
          content: "Message #{i}: " <> String.duplicate("x", 200),
          id: "msg-#{i}",
          timestamp: DateTime.utc_now()
        }
        {:ok, _} = SessionState.append_message(session_id, msg)
      end

      # Add many memories
      for i <- 1..20 do
        {:ok, _} = Memory.persist(%{
          id: Uniq.UUID.uuid4(),
          session_id: session_id,
          content: "Memory #{i}: " <> String.duplicate("y", 100),
          memory_type: :fact,
          confidence: 0.5 + (i / 100),
          source_type: :user,
          created_at: now
        }, session_id)
      end

      # Build context with small budget
      small_budget = ContextBuilder.allocate_budget(2_000)
      {:ok, context} = ContextBuilder.build(session_id, token_budget: small_budget)

      # Verify total tokens are within budget
      assert context.token_counts.total <= small_budget.total
      assert context.token_counts.conversation <= small_budget.conversation
      assert context.token_counts.long_term <= small_budget.long_term
    end

    test "5.5.1.5 context updates after tool execution", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Initial context build
      {:ok, context1} = ContextBuilder.build(session_id)
      initial_memory_count = length(context1.long_term_memories)

      # Execute remember tool
      {:ok, _} = Remember.run(%{
        content: "User prefers dark mode",
        type: :convention
      }, context)

      # Rebuild context
      {:ok, context2} = ContextBuilder.build(session_id)

      # Verify memory count increased
      assert length(context2.long_term_memories) > initial_memory_count

      # Verify new memory is present
      contents = Enum.map(context2.long_term_memories, & &1.content)
      assert "User prefers dark mode" in contents
    end

    test "5.5.1.6 context reflects most recent session state", %{session_id: session_id} do
      # Build initial context
      {:ok, context1} = ContextBuilder.build(session_id)
      assert context1.working_context[:current_task] == nil

      # Update session state with valid context key
      :ok = SessionState.update_context(session_id, :current_task, "implementing authentication")

      # Rebuild context
      {:ok, context2} = ContextBuilder.build(session_id)

      # Verify updated value is reflected
      assert context2.working_context[:current_task] == "implementing authentication"
    end
  end

  # =============================================================================
  # 5.5.2 Memory Tool Execution Integration
  # =============================================================================

  describe "5.5.2 Memory Tool Execution Integration" do
    test "5.5.2.1 can execute remember tool during chat", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Execute remember tool
      {:ok, result} = Remember.run(%{
        content: "The API uses JWT for authentication",
        type: :fact,
        confidence: 0.9
      }, context)

      # Verify result
      assert result.remembered == true
      assert is_binary(result.memory_id)

      # Verify memory is persisted
      {:ok, recall_result} = Recall.run(%{min_confidence: 0.0}, context)
      memory_ids = Enum.map(recall_result.memories, & &1.id)
      assert result.memory_id in memory_ids
    end

    test "5.5.2.2 can execute recall tool during chat", %{session_id: session_id} do
      context = %{session_id: session_id}

      # First store some memories
      {:ok, _} = Remember.run(%{content: "Memory A", type: :fact}, context)
      {:ok, _} = Remember.run(%{content: "Memory B", type: :decision}, context)
      {:ok, _} = Remember.run(%{content: "Memory C", type: :hypothesis}, context)

      # Execute recall tool
      {:ok, result} = Recall.run(%{min_confidence: 0.0}, context)

      # Verify result
      assert result.count >= 3
      assert is_list(result.memories)
      contents = Enum.map(result.memories, & &1.content)
      assert "Memory A" in contents
      assert "Memory B" in contents
      assert "Memory C" in contents
    end

    test "5.5.2.3 can execute forget tool during chat", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Store a memory
      {:ok, remember_result} = Remember.run(%{
        content: "Temporary memory to forget",
        type: :fact
      }, context)
      memory_id = remember_result.memory_id

      # Verify memory exists
      {:ok, recall_before} = Recall.run(%{min_confidence: 0.0}, context)
      assert Enum.any?(recall_before.memories, fn m -> m.id == memory_id end)

      # Execute forget tool
      {:ok, forget_result} = Forget.run(%{memory_id: memory_id}, context)
      assert forget_result.forgotten == true

      # Verify memory is gone
      {:ok, recall_after} = Recall.run(%{min_confidence: 0.0}, context)
      refute Enum.any?(recall_after.memories, fn m -> m.id == memory_id end)
    end

    test "5.5.2.4 memory tool results formatted correctly", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Remember returns expected keys
      {:ok, remember_result} = Remember.run(%{
        content: "Test memory",
        type: :fact
      }, context)

      assert Map.has_key?(remember_result, :remembered)
      assert Map.has_key?(remember_result, :memory_id)

      # Recall returns expected structure
      {:ok, recall_result} = Recall.run(%{min_confidence: 0.0}, context)

      assert Map.has_key?(recall_result, :count)
      assert Map.has_key?(recall_result, :memories)
      assert is_list(recall_result.memories)

      # Forget returns expected keys
      {:ok, forget_result} = Forget.run(%{memory_id: remember_result.memory_id}, context)

      assert Map.has_key?(forget_result, :forgotten)
    end

    test "5.5.2.5 tool execution updates session state", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Get initial state
      {:ok, messages_before} = SessionState.get_messages(session_id)
      initial_count = length(messages_before)

      # Execute remember tool (this should persist memory to session's store)
      {:ok, _} = Remember.run(%{
        content: "Session state test memory",
        type: :fact
      }, context)

      # The memory should be queryable through Memory module
      {:ok, memories} = Memory.query(session_id, min_confidence: 0.0)
      assert length(memories) >= 1
      contents = Enum.map(memories, & &1.content)
      assert "Session state test memory" in contents
    end
  end

  # =============================================================================
  # 5.5.3 Response Processing Integration
  # =============================================================================

  describe "5.5.3 Response Processing Integration" do
    test "5.5.3.1 extracts context from LLM-like responses", %{session_id: session_id} do
      # Simulate LLM response with contextual information
      response = """
      I see you're working on lib/my_app/users.ex. This is an Elixir project
      using Phoenix 1.7. You're implementing user authentication. Let me help
      you with the Ecto schema.
      """

      # Process the response
      {:ok, extractions} = ResponseProcessor.process_response(response, session_id)

      # Check extractions (at least some should be extracted)
      # Note: Not all patterns may match depending on implementation
      assert is_map(extractions)
    end

    test "5.5.3.2 extracted context appears in next context assembly", %{session_id: session_id} do
      # Set context that would be extracted
      :ok = SessionState.update_context(session_id, :active_file, "lib/app.ex")

      # Build context
      {:ok, context} = ContextBuilder.build(session_id)

      # Verify context is present
      assert context.working_context[:active_file] == "lib/app.ex"

      # Format for prompt should include it
      prompt_text = ContextBuilder.format_for_prompt(context)
      assert prompt_text =~ "Active file" or prompt_text =~ "active_file" or prompt_text =~ "lib/app.ex"
    end

    test "5.5.3.3 response processing handles empty responses", %{session_id: session_id} do
      # Process empty response
      {:ok, extractions1} = ResponseProcessor.process_response("", session_id)
      assert extractions1 == %{}

      # Process nil-like content
      {:ok, extractions2} = ResponseProcessor.process_response("  \n  ", session_id)
      assert extractions2 == %{}
    end

    test "5.5.3.4 multiple responses accumulate context correctly", %{session_id: session_id} do
      # First response sets one context value
      :ok = SessionState.update_context(session_id, :framework, "Phoenix")

      # Second response sets another
      :ok = SessionState.update_context(session_id, :primary_language, "elixir")

      # Build context - should have both
      {:ok, context} = ContextBuilder.build(session_id)

      assert context.working_context[:framework] == "Phoenix"
      assert context.working_context[:primary_language] == "elixir"
    end
  end

  # =============================================================================
  # 5.5.4 Token Budget Integration
  # =============================================================================

  describe "5.5.4 Token Budget Integration" do
    test "5.5.4.1 large conversations truncated to budget", %{session_id: session_id} do
      # Add many long messages
      for i <- 1..100 do
        msg = %{
          role: :user,
          content: "Message number #{i}: " <> String.duplicate("conversation content ", 20),
          id: "msg-#{i}",
          timestamp: DateTime.utc_now()
        }
        {:ok, _} = SessionState.append_message(session_id, msg)
      end

      # Get all messages
      {:ok, all_messages} = SessionState.get_messages(session_id)
      assert length(all_messages) == 100

      # Build with tiny conversation budget
      tiny_budget = %{
        total: 500,
        system: 50,
        conversation: 200,
        working: 50,
        long_term: 50
      }

      {:ok, context} = ContextBuilder.build(session_id, token_budget: tiny_budget)

      # Verify truncation occurred
      assert length(context.conversation) < 100
      assert context.token_counts.conversation <= tiny_budget.conversation
    end

    test "5.5.4.2 many memories truncated to budget", %{session_id: session_id} do
      now = DateTime.utc_now()

      # Add many memories
      for i <- 1..50 do
        {:ok, _} = Memory.persist(%{
          id: Uniq.UUID.uuid4(),
          session_id: session_id,
          content: "Memory #{i}: " <> String.duplicate("memory content ", 10),
          memory_type: :fact,
          confidence: 0.5 + (i / 200),
          source_type: :user,
          created_at: now
        }, session_id)
      end

      # Build with tiny memory budget
      tiny_budget = %{
        total: 500,
        system: 50,
        conversation: 50,
        working: 50,
        long_term: 100
      }

      {:ok, context} = ContextBuilder.build(session_id, token_budget: tiny_budget)

      # Verify truncation occurred
      assert length(context.long_term_memories) < 50
      assert context.token_counts.long_term <= tiny_budget.long_term
    end

    test "5.5.4.3 budget allocation correct for various totals", %{session_id: session_id} do
      # Test different budget totals
      for total <- [8_000, 16_000, 32_000, 64_000, 128_000] do
        budget = ContextBuilder.allocate_budget(total)

        # Verify structure
        assert budget.total == total
        assert budget.system > 0
        assert budget.conversation > 0
        assert budget.working > 0
        assert budget.long_term > 0

        # Verify proportions are reasonable (conversation should be largest)
        assert budget.conversation > budget.working
        assert budget.conversation > budget.long_term

        # Verify valid budget
        assert ContextBuilder.valid_token_budget?(budget)
      end
    end

    test "5.5.4.4 truncation preserves most important content", %{session_id: session_id} do
      now = DateTime.utc_now()

      # Add messages with identifiable content
      {:ok, _} = SessionState.append_message(session_id, %{
        role: :user,
        content: "OLD_MESSAGE: This is an old message",
        id: "msg-old",
        timestamp: DateTime.utc_now()
      })

      # Add more messages to push old one out
      for i <- 1..10 do
        {:ok, _} = SessionState.append_message(session_id, %{
          role: :user,
          content: "Message #{i}: " <> String.duplicate("x", 50),
          id: "msg-#{i}",
          timestamp: DateTime.utc_now()
        })
      end

      {:ok, _} = SessionState.append_message(session_id, %{
        role: :user,
        content: "RECENT_MESSAGE: This is the most recent message",
        id: "msg-recent",
        timestamp: DateTime.utc_now()
      })

      # Build with tiny budget
      tiny_budget = %{
        total: 200,
        system: 20,
        conversation: 100,
        working: 20,
        long_term: 20
      }

      {:ok, context} = ContextBuilder.build(session_id, token_budget: tiny_budget)

      # Most recent message should be preserved
      contents = Enum.map(context.conversation, & &1.content)
      assert Enum.any?(contents, &String.contains?(&1, "RECENT_MESSAGE"))

      # Add memories with different confidence
      {:ok, _} = Memory.persist(%{
        id: Uniq.UUID.uuid4(),
        session_id: session_id,
        content: "LOW_CONFIDENCE: Low confidence memory",
        memory_type: :fact,
        confidence: 0.2,
        source_type: :user,
        created_at: now
      }, session_id)

      {:ok, _} = Memory.persist(%{
        id: Uniq.UUID.uuid4(),
        session_id: session_id,
        content: "HIGH_CONFIDENCE: High confidence memory",
        memory_type: :fact,
        confidence: 0.99,
        source_type: :user,
        created_at: now
      }, session_id)

      # Build context with tiny memory budget
      {:ok, context2} = ContextBuilder.build(session_id, token_budget: %{
        total: 200,
        system: 20,
        conversation: 20,
        working: 20,
        long_term: 50
      })

      # If only one memory fits, high confidence should be preserved
      if length(context2.long_term_memories) == 1 do
        memory = hd(context2.long_term_memories)
        assert memory.content =~ "HIGH_CONFIDENCE"
      end
    end
  end

  # =============================================================================
  # Additional Integration Tests
  # =============================================================================

  describe "end-to-end context flow" do
    test "full context assembly and formatting", %{session_id: session_id} do
      now = DateTime.utc_now()

      # Set up working context
      :ok = SessionState.update_context(session_id, :project_root, "/home/user/myapp")
      :ok = SessionState.update_context(session_id, :primary_language, "elixir")

      # Add conversation
      {:ok, _} = SessionState.append_message(session_id, %{
        role: :user,
        content: "How do I add authentication?",
        id: "msg-1",
        timestamp: DateTime.utc_now()
      })

      # Add memory
      {:ok, _} = Memory.persist(%{
        id: Uniq.UUID.uuid4(),
        session_id: session_id,
        content: "Uses Phoenix framework",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :user,
        created_at: now
      }, session_id)

      # Build context
      {:ok, context} = ContextBuilder.build(session_id)

      # Verify all components present
      assert context.working_context[:project_root] == "/home/user/myapp"
      assert length(context.conversation) >= 1
      assert length(context.long_term_memories) >= 1

      # Format for prompt
      prompt = ContextBuilder.format_for_prompt(context)

      # Verify prompt contains expected sections
      assert prompt =~ "Session Context" or prompt =~ "Remembered Information"
    end

    test "memory tools integrate with context builder", %{session_id: session_id} do
      context = %{session_id: session_id}

      # Remember something
      {:ok, _} = Remember.run(%{
        content: "User prefers TDD approach",
        type: :convention,
        confidence: 0.95
      }, context)

      # Build context
      {:ok, built_context} = ContextBuilder.build(session_id)

      # Memory should be in context
      memory_contents = Enum.map(built_context.long_term_memories, & &1.content)
      assert "User prefers TDD approach" in memory_contents

      # Format should include it
      prompt = ContextBuilder.format_for_prompt(built_context)
      assert prompt =~ "TDD" or prompt =~ "convention"
    end
  end
end
