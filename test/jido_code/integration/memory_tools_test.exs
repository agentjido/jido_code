defmodule JidoCode.Integration.MemoryToolsTest do
  @moduledoc """
  Phase 4 Integration Tests for Memory Tools.

  These tests verify the complete integration of memory actions (remember, recall, forget)
  including tool execution flows, session context handling, executor integration,
  and telemetry emissions.
  """

  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions
  alias JidoCode.Memory.Actions.{Remember, Recall, Forget}
  alias JidoCode.Tools.Executor

  @moduletag :integration
  @moduletag :phase4

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    # Ensure application is started
    Application.ensure_all_started(:jido_code)

    session_id = "integration-test-#{System.unique_integer([:positive])}"
    context = %{session_id: session_id}

    on_exit(fn ->
      # Cleanup: close the memory store for this session
      Memory.close_session(session_id)
    end)

    %{session_id: session_id, context: context}
  end

  # =============================================================================
  # 4.5.1 Tool Execution Integration
  # =============================================================================

  describe "4.5.1 Tool Execution Integration" do
    test "4.5.1.2 Remember tool creates memory accessible via Recall", %{context: context} do
      # Remember something
      {:ok, remember_result} =
        Remember.run(%{content: "Phoenix uses Plug for HTTP handling", type: :fact}, context)

      assert remember_result.remembered == true
      memory_id = remember_result.memory_id

      # Recall should find it
      {:ok, recall_result} = Recall.run(%{min_confidence: 0.0}, context)

      assert recall_result.count >= 1
      assert Enum.any?(recall_result.memories, fn m -> m.id == memory_id end)
    end

    test "4.5.1.3 Remember -> Recall flow returns persisted memory", %{context: context} do
      content = "The project uses Ecto for database access"

      # Remember
      {:ok, remember_result} = Remember.run(%{content: content, type: :fact}, context)

      # Recall and verify content matches
      {:ok, recall_result} = Recall.run(%{min_confidence: 0.0}, context)

      found_memory = Enum.find(recall_result.memories, fn m ->
        m.id == remember_result.memory_id
      end)

      assert found_memory != nil
      assert found_memory.content == content
      assert found_memory.type == :fact
    end

    test "4.5.1.4 Recall returns memories filtered by type", %{context: context} do
      # Create memories of different types
      {:ok, _} = Remember.run(%{content: "This is a fact", type: :fact}, context)
      {:ok, _} = Remember.run(%{content: "This is a decision", type: :decision}, context)
      {:ok, _} = Remember.run(%{content: "This is a hypothesis", type: :hypothesis}, context)

      # Recall only facts
      {:ok, facts} = Recall.run(%{type: :fact, min_confidence: 0.0}, context)
      assert Enum.all?(facts.memories, fn m -> m.type == :fact end)

      # Recall only decisions
      {:ok, decisions} = Recall.run(%{type: :decision, min_confidence: 0.0}, context)
      assert Enum.all?(decisions.memories, fn m -> m.type == :decision end)
    end

    test "4.5.1.5 Recall returns memories filtered by confidence", %{context: context} do
      # Create memories with different confidence levels
      {:ok, _} = Remember.run(%{content: "High confidence", confidence: 0.95}, context)
      {:ok, _} = Remember.run(%{content: "Medium confidence", confidence: 0.7}, context)
      {:ok, _} = Remember.run(%{content: "Low confidence", confidence: 0.4}, context)

      # Recall only high confidence
      {:ok, result} = Recall.run(%{min_confidence: 0.9}, context)

      # Should only get the high confidence memory
      assert result.count >= 1
      assert Enum.all?(result.memories, fn m -> m.confidence >= 0.9 end)
    end

    test "4.5.1.6 Recall with query filters by text content", %{context: context} do
      {:ok, _} = Remember.run(%{content: "Phoenix uses LiveView for real-time"}, context)
      {:ok, _} = Remember.run(%{content: "Ecto handles database queries"}, context)
      {:ok, _} = Remember.run(%{content: "Mix is the build tool"}, context)

      # Query for "LiveView"
      {:ok, result} = Recall.run(%{query: "LiveView", min_confidence: 0.0}, context)

      assert result.count >= 1
      assert Enum.any?(result.memories, fn m -> String.contains?(m.content, "LiveView") end)
      refute Enum.any?(result.memories, fn m -> String.contains?(m.content, "Ecto") end)
    end

    test "4.5.1.7 Forget tool removes memory from normal Recall results", %{context: context} do
      # Remember something
      {:ok, remember_result} =
        Remember.run(%{content: "This will be forgotten", type: :fact}, context)

      memory_id = remember_result.memory_id

      # Verify it's there
      {:ok, before_forget} = Recall.run(%{min_confidence: 0.0}, context)
      assert Enum.any?(before_forget.memories, fn m -> m.id == memory_id end)

      # Forget it
      {:ok, forget_result} = Forget.run(%{memory_id: memory_id}, context)
      assert forget_result.forgotten == true

      # Verify it's gone from normal recall
      {:ok, after_forget} = Recall.run(%{min_confidence: 0.0}, context)
      refute Enum.any?(after_forget.memories, fn m -> m.id == memory_id end)
    end

    test "4.5.1.8 Forgotten memories still exist for provenance", %{
      session_id: session_id,
      context: context
    } do
      # Remember and forget
      {:ok, remember_result} =
        Remember.run(%{content: "Memory for provenance test", type: :fact}, context)

      memory_id = remember_result.memory_id

      {:ok, _} = Forget.run(%{memory_id: memory_id}, context)

      # Query with include_superseded to find it
      {:ok, memories} = Memory.query(session_id, include_superseded: true)

      assert Enum.any?(memories, fn m -> m.id == memory_id end)
    end

    test "4.5.1.9 Forget with replacement_id creates supersession chain", %{context: context} do
      # Create original memory
      {:ok, original} =
        Remember.run(%{content: "Original information", type: :fact}, context)

      # Create replacement memory
      {:ok, replacement} =
        Remember.run(%{content: "Updated information", type: :fact}, context)

      # Forget original with replacement
      {:ok, forget_result} =
        Forget.run(
          %{memory_id: original.memory_id, replacement_id: replacement.memory_id},
          context
        )

      assert forget_result.forgotten == true
      assert forget_result.replacement_id == replacement.memory_id
      assert forget_result.message =~ "superseded by"
    end
  end

  # =============================================================================
  # 4.5.2 Session Context Integration
  # =============================================================================

  describe "4.5.2 Session Context Integration" do
    test "4.5.2.1 Memory tools work with valid session context", %{context: context} do
      # All operations should succeed with valid context
      {:ok, remember_result} = Remember.run(%{content: "Test content"}, context)
      assert remember_result.remembered == true

      {:ok, recall_result} = Recall.run(%{}, context)
      assert is_integer(recall_result.count)

      {:ok, forget_result} = Forget.run(%{memory_id: remember_result.memory_id}, context)
      assert forget_result.forgotten == true
    end

    test "4.5.2.2 Memory tools return appropriate error without session_id" do
      empty_context = %{}

      {:error, remember_error} = Remember.run(%{content: "Test"}, empty_context)
      assert remember_error =~ "Session ID"

      {:error, recall_error} = Recall.run(%{}, empty_context)
      assert recall_error =~ "Session ID"

      {:error, forget_error} = Forget.run(%{memory_id: "some-id"}, empty_context)
      assert forget_error =~ "Session ID"
    end

    test "4.5.2.3 Memory tools respect session isolation" do
      session_1 = "isolation-test-1-#{System.unique_integer([:positive])}"
      session_2 = "isolation-test-2-#{System.unique_integer([:positive])}"
      context_1 = %{session_id: session_1}
      context_2 = %{session_id: session_2}

      # Remember in session 1
      {:ok, result_1} =
        Remember.run(%{content: "Session 1 only content"}, context_1)

      # Remember in session 2
      {:ok, result_2} =
        Remember.run(%{content: "Session 2 only content"}, context_2)

      # Recall in session 1 - should only see session 1 content
      {:ok, recall_1} = Recall.run(%{min_confidence: 0.0}, context_1)
      assert Enum.any?(recall_1.memories, fn m -> m.id == result_1.memory_id end)
      refute Enum.any?(recall_1.memories, fn m -> m.id == result_2.memory_id end)

      # Recall in session 2 - should only see session 2 content
      {:ok, recall_2} = Recall.run(%{min_confidence: 0.0}, context_2)
      assert Enum.any?(recall_2.memories, fn m -> m.id == result_2.memory_id end)
      refute Enum.any?(recall_2.memories, fn m -> m.id == result_1.memory_id end)

      # Cleanup
      Memory.close_session(session_1)
      Memory.close_session(session_2)
    end

    test "4.5.2.4 Multiple sessions can use memory tools concurrently" do
      sessions =
        for i <- 1..5 do
          session_id = "concurrent-#{i}-#{System.unique_integer([:positive])}"
          context = %{session_id: session_id}
          {session_id, context}
        end

      # Run remember operations concurrently
      tasks =
        Enum.map(sessions, fn {session_id, context} ->
          Task.async(fn ->
            {:ok, result} = Remember.run(%{content: "Content for #{session_id}"}, context)
            {session_id, result.memory_id}
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # Verify each session has its memory
      for {session_id, memory_id} <- results do
        context = %{session_id: session_id}
        {:ok, recall_result} = Recall.run(%{min_confidence: 0.0}, context)
        assert Enum.any?(recall_result.memories, fn m -> m.id == memory_id end)
      end

      # Cleanup
      for {session_id, _} <- sessions do
        Memory.close_session(session_id)
      end
    end
  end

  # =============================================================================
  # 4.5.3 Executor Integration
  # =============================================================================

  describe "4.5.3 Executor Integration" do
    test "4.5.3.1 Memory tools execute through standard executor flow", %{
      session_id: session_id,
      context: context
    } do
      # Execute remember through executor
      tool_call = %{
        id: "call-remember-1",
        name: "remember",
        arguments: %{content: "Executor integration test", type: :fact}
      }

      {:ok, result} = Executor.execute(tool_call, context: context)

      assert result.status == :ok
      assert result.tool_name == "remember"
      assert is_binary(result.content)

      # Verify the memory was actually created
      {:ok, memories} = Memory.query(session_id, min_confidence: 0.0)
      assert Enum.any?(memories, fn m -> m.content == "Executor integration test" end)
    end

    test "4.5.3.2 Tool validation rejects invalid arguments", %{context: context} do
      # Empty content should fail
      tool_call = %{
        id: "call-remember-invalid",
        name: "remember",
        arguments: %{content: ""}
      }

      {:ok, result} = Executor.execute(tool_call, context: context)

      assert result.status == :error
      assert result.content =~ "empty"
    end

    test "4.5.3.3 Tool results format correctly for LLM consumption", %{context: context} do
      # Remember
      remember_call = %{
        id: "call-remember-format",
        name: "remember",
        arguments: %{content: "Format test content", type: :fact}
      }

      {:ok, remember_result} = Executor.execute(remember_call, context: context)

      assert remember_result.status == :ok
      # Content should be JSON for LLM
      assert is_binary(remember_result.content)
      {:ok, parsed} = Jason.decode(remember_result.content)
      assert Map.has_key?(parsed, "remembered")
      assert Map.has_key?(parsed, "memory_id")
    end

    test "4.5.3.4 Error messages are clear and actionable", %{context: context} do
      # Try to forget non-existent memory
      forget_call = %{
        id: "call-forget-missing",
        name: "forget",
        arguments: %{memory_id: "nonexistent-memory-id"}
      }

      {:ok, result} = Executor.execute(forget_call, context: context)

      assert result.status == :error
      assert result.content =~ "not found"
    end

    test "executor routes all memory tools correctly", %{context: context} do
      # Test all three tools through executor
      for tool_name <- ["remember", "recall", "forget"] do
        assert Executor.memory_tool?(tool_name)
      end

      assert Executor.memory_tools() == ["remember", "recall", "forget"]
    end

    test "executor passes session_id in context", %{context: context} do
      # This implicitly tests that session_id is passed correctly
      # because remember would fail without it
      tool_call = %{
        id: "call-session-test",
        name: "remember",
        arguments: %{content: "Session context test"}
      }

      {:ok, result} = Executor.execute(tool_call, context: context)
      assert result.status == :ok
    end
  end

  # =============================================================================
  # 4.5.4 Telemetry Integration
  # =============================================================================

  describe "4.5.4 Telemetry Integration" do
    test "4.5.4.1 Remember emits telemetry with session_id and type", %{
      session_id: session_id,
      context: context
    } do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-remember-telemetry-#{inspect(ref)}",
        [:jido_code, :memory, :remember],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _} = Remember.run(%{content: "Telemetry test", type: :decision}, context)

      assert_receive {:telemetry, [:jido_code, :memory, :remember], measurements, metadata}

      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.session_id == session_id
      assert metadata.memory_type == :decision

      :telemetry.detach("test-remember-telemetry-#{inspect(ref)}")
    end

    test "4.5.4.2 Recall emits telemetry with query parameters", %{
      session_id: session_id,
      context: context
    } do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-recall-telemetry-#{inspect(ref)}",
        [:jido_code, :memory, :recall],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _} = Recall.run(%{type: :fact, min_confidence: 0.7, limit: 5}, context)

      assert_receive {:telemetry, [:jido_code, :memory, :recall], measurements, metadata}

      assert is_integer(measurements.duration)
      assert is_integer(measurements.result_count)
      assert metadata.session_id == session_id
      assert metadata.memory_type == :fact
      assert metadata.min_confidence == 0.7
      assert metadata.has_query == false

      :telemetry.detach("test-recall-telemetry-#{inspect(ref)}")
    end

    test "4.5.4.3 Forget emits telemetry with memory_id", %{
      session_id: session_id,
      context: context
    } do
      # First create a memory to forget
      {:ok, remember_result} = Remember.run(%{content: "To be forgotten"}, context)
      memory_id = remember_result.memory_id

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-forget-telemetry-#{inspect(ref)}",
        [:jido_code, :memory, :forget],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _} = Forget.run(%{memory_id: memory_id}, context)

      assert_receive {:telemetry, [:jido_code, :memory, :forget], measurements, metadata}

      assert is_integer(measurements.duration)
      assert metadata.session_id == session_id
      assert metadata.memory_id == memory_id

      :telemetry.detach("test-forget-telemetry-#{inspect(ref)}")
    end
  end

  # =============================================================================
  # Actions Registry Tests
  # =============================================================================

  describe "Actions registry integration" do
    test "Actions.all/0 returns all three action modules" do
      modules = Actions.all()

      assert length(modules) == 3
      assert Remember in modules
      assert Recall in modules
      assert Forget in modules
    end

    test "Actions.get/1 returns correct module for each name" do
      assert {:ok, Remember} = Actions.get("remember")
      assert {:ok, Recall} = Actions.get("recall")
      assert {:ok, Forget} = Actions.get("forget")
    end

    test "Actions.get/1 returns error for unknown name" do
      assert {:error, :not_found} = Actions.get("unknown_action")
      assert {:error, :not_found} = Actions.get("read_file")
    end

    test "Actions.to_tool_definitions/0 produces valid tool definitions" do
      defs = Actions.to_tool_definitions()

      assert length(defs) == 3

      for def <- defs do
        assert Map.has_key?(def, :name)
        assert Map.has_key?(def, :description)
        assert Map.has_key?(def, :parameters_schema)
        assert def[:name] in ["remember", "recall", "forget"]
      end
    end

    test "tool definitions have correct name, description, parameters" do
      defs = Actions.to_tool_definitions()

      remember_def = Enum.find(defs, fn d -> d[:name] == "remember" end)
      assert remember_def[:description] =~ "Persist"
      assert remember_def[:parameters_schema][:properties]["content"] != nil

      recall_def = Enum.find(defs, fn d -> d[:name] == "recall" end)
      assert recall_def[:description] =~ "Search"
      assert recall_def[:parameters_schema][:properties]["type"] != nil

      forget_def = Enum.find(defs, fn d -> d[:name] == "forget" end)
      assert forget_def[:description] =~ "superseded"
      assert forget_def[:parameters_schema][:properties]["memory_id"] != nil
    end
  end
end
