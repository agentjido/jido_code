defmodule JidoCode.Integration.ToolsPhase7Test do
  @moduledoc """
  Integration tests for Phase 7 (Knowledge Graph Tools) using the Handler pattern.

  These tests verify that Phase 7 tools work correctly through the
  Executor → Handler chain with proper session isolation and telemetry.

  ## Tested Tools

  - `knowledge_remember` - Store knowledge with ontology typing (Section 7.1)
  - `knowledge_recall` - Query knowledge with semantic filters (Section 7.2)
  - `knowledge_supersede` - Replace outdated knowledge (Section 7.3)
  - `knowledge_update` - Update confidence/evidence (Section 7.4)
  - `project_conventions` - Get conventions and standards (Section 7.5)
  - `project_decisions` - Get architectural decisions (Section 7.6)
  - `project_risks` - Get known risks (Section 7.7)
  - `knowledge_graph_query` - Relationship traversal (Section 7.8)
  - `knowledge_context` - Auto-relevance context (Section 7.9)

  ## Test Coverage (Section 7.10)

  - 7.10.1: Handler Integration - Executor → Handler chain, session isolation, telemetry
  - 7.10.2: Knowledge Lifecycle - remember → recall, supersede, update flows
  - 7.10.3: Cross-Tool Integration - project_* tools find appropriate memory types

  ## Why async: false

  These tests cannot run async because they:
  1. Share the SessionSupervisor (DynamicSupervisor)
  2. Use SessionRegistry which is a shared ETS table
  3. Require session isolation testing
  4. Need deterministic cleanup between test runs
  """
  use ExUnit.Case, async: false

  alias JidoCode.Memory
  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.Tools.Definitions.Knowledge, as: KnowledgeDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Registry, as: ToolsRegistry

  @moduletag :integration
  @moduletag :phase7

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Process.flag(:trap_exit, true)

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase7_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Register Phase 7 tools
    register_phase7_tools()

    on_exit(fn ->
      # Restore deprecation warnings
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)

      # Stop all test sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      File.rm_rf!(tmp_base)
    end)

    {:ok, tmp_base: tmp_base}
  end

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor not available after waiting"
      end
    end
  end

  defp register_phase7_tools do
    # Register all Phase 7 Knowledge tools
    for tool <- KnowledgeDefs.all() do
      ToolsRegistry.register(tool)
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_dir(base, name) do
    path = Path.join(base, name)
    File.mkdir_p!(path)
    path
  end

  defp create_session(project_path) do
    config = SessionTestHelpers.valid_session_config()
    {:ok, session} = Session.new(project_path: project_path, config: config)
    {:ok, _pid} = SessionSupervisor.start_session(session)
    session
  end

  defp tool_call(name, args) do
    %{
      id: "tc-#{:rand.uniform(100_000)}",
      name: name,
      arguments: args
    }
  end

  # Helper to extract result from Executor.execute response
  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :ok, content: content}}),
    do: {:ok, content}

  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :error, content: content}}),
    do: {:error, content}

  defp unwrap_result({:error, reason}),
    do: {:error, reason}

  defp decode_result({:ok, json}) when is_binary(json), do: {:ok, Jason.decode!(json)}
  defp decode_result(other), do: other

  # Execute tool and decode JSON result
  defp execute_tool(call, context) do
    Executor.execute(call, context: context)
    |> unwrap_result()
    |> decode_result()
  end

  # Clean up memory store after test
  defp cleanup_session(session) do
    Memory.close_session(session.id)
  end

  # ============================================================================
  # Section 7.10.1: Handler Integration Tests
  # ============================================================================

  describe "7.10.1.1 Executor → Handler chain execution" do
    test "knowledge_remember executes through Executor → Handler chain", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "remember_chain_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("knowledge_remember", %{
        "content" => "Phoenix uses Plug for HTTP handling",
        "type" => "fact",
        "confidence" => 0.9
      })

      {:ok, result} = execute_tool(call, context)

      assert is_map(result)
      assert Map.has_key?(result, "memory_id")
      assert result["type"] == "fact"
      assert result["confidence"] == 0.9
    end

    test "knowledge_recall executes through Executor → Handler chain", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "recall_chain_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # First, remember something
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Test content for recall",
        "type" => "fact"
      })

      {:ok, _} = execute_tool(remember_call, context)

      # Then recall
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, result} = execute_tool(recall_call, context)

      assert is_map(result)
      assert Map.has_key?(result, "count")
      assert Map.has_key?(result, "memories")
      assert result["count"] >= 1
    end

    test "all 9 knowledge tools are registered", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "tools_registered_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      tool_names = [
        "knowledge_remember",
        "knowledge_recall",
        "knowledge_supersede",
        "knowledge_update",
        "project_conventions",
        "project_decisions",
        "project_risks",
        "knowledge_graph_query",
        "knowledge_context"
      ]

      for name <- tool_names do
        assert ToolsRegistry.get(name) != nil, "Tool #{name} should be registered"
      end
    end
  end

  describe "7.10.1.2 Session isolation" do
    test "memories are isolated between sessions", %{tmp_base: tmp_base} do
      # Create two separate sessions
      project_dir1 = create_test_dir(tmp_base, "session1")
      project_dir2 = create_test_dir(tmp_base, "session2")

      session1 = create_session(project_dir1)
      session2 = create_session(project_dir2)

      on_exit(fn ->
        cleanup_session(session1)
        cleanup_session(session2)
      end)

      {:ok, context1} = Executor.build_context(session1.id)
      {:ok, context2} = Executor.build_context(session2.id)

      # Remember in session 1
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Session 1 exclusive content",
        "type" => "fact"
      })

      {:ok, remember_result} = execute_tool(remember_call, context1)
      session1_memory_id = remember_result["memory_id"]

      # Recall in session 1 - should find it
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, result1} = execute_tool(recall_call, context1)

      assert result1["count"] >= 1
      memory_ids1 = Enum.map(result1["memories"], & &1["id"])
      assert session1_memory_id in memory_ids1

      # Recall in session 2 - should NOT find it
      {:ok, result2} = execute_tool(recall_call, context2)

      memory_ids2 = Enum.map(result2["memories"], & &1["id"])
      refute session1_memory_id in memory_ids2
    end

    test "supersede only affects memories in same session", %{tmp_base: tmp_base} do
      project_dir1 = create_test_dir(tmp_base, "supersede_session1")
      project_dir2 = create_test_dir(tmp_base, "supersede_session2")

      session1 = create_session(project_dir1)
      session2 = create_session(project_dir2)

      on_exit(fn ->
        cleanup_session(session1)
        cleanup_session(session2)
      end)

      {:ok, context1} = Executor.build_context(session1.id)
      {:ok, context2} = Executor.build_context(session2.id)

      # Remember in session 1
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Original content",
        "type" => "fact"
      })

      {:ok, remember_result} = execute_tool(remember_call, context1)
      memory_id = remember_result["memory_id"]

      # Try to supersede from session 2 - should fail
      supersede_call = tool_call("knowledge_supersede", %{
        "old_memory_id" => memory_id,
        "reason" => "Updated from wrong session"
      })

      {:error, error_msg} = execute_tool(supersede_call, context2)
      assert error_msg =~ "not found" or error_msg =~ "does not exist"
    end
  end

  describe "7.10.1.3 Telemetry emission" do
    test "knowledge_remember emits telemetry event", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "telemetry_remember_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Set up telemetry handler
      test_pid = self()
      ref = make_ref()

      handler_id = "test-remember-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :remember],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      call = tool_call("knowledge_remember", %{
        "content" => "Telemetry test content",
        "type" => "fact"
      })

      {:ok, _} = execute_tool(call, context)

      assert_receive {:telemetry, [:jido_code, :knowledge, :remember], measurements, metadata}, 1000
      assert is_map(measurements)
      assert Map.has_key?(measurements, :duration)
      assert is_map(metadata)
    end

    test "knowledge_recall emits telemetry event", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "telemetry_recall_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Set up telemetry handler
      test_pid = self()
      ref = make_ref()

      handler_id = "test-recall-#{inspect(ref)}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :knowledge, :recall],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})

      {:ok, _} = execute_tool(call, context)

      assert_receive {:telemetry, [:jido_code, :knowledge, :recall], measurements, _metadata}, 1000
      assert Map.has_key?(measurements, :duration)
    end
  end

  # ============================================================================
  # Section 7.10.2: Knowledge Lifecycle Tests
  # ============================================================================

  describe "7.10.2.1 remember → recall → verify content" do
    test "remembered content can be recalled and verified", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_basic")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      content = "Phoenix Framework uses the Plug specification for HTTP handling"
      rationale = "Documented in Phoenix guides"

      # Remember
      remember_call = tool_call("knowledge_remember", %{
        "content" => content,
        "type" => "fact",
        "confidence" => 0.95,
        "rationale" => rationale
      })

      {:ok, remember_result} = execute_tool(remember_call, context)
      memory_id = remember_result["memory_id"]

      # Recall
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, recall_result} = execute_tool(recall_call, context)

      # Verify
      found_memory = Enum.find(recall_result["memories"], &(&1["id"] == memory_id))
      assert found_memory != nil
      assert found_memory["content"] == content
      assert found_memory["type"] == "fact"
      assert found_memory["confidence"] == 0.95
    end

    test "multiple memories can be recalled together", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_multiple")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember multiple items
      contents = [
        {"Elixir runs on the BEAM VM", "fact"},
        {"Consider using GenServer for state", "assumption"},
        {"Redis might improve performance", "hypothesis"}
      ]

      memory_ids =
        for {content, type} <- contents do
          call = tool_call("knowledge_remember", %{"content" => content, "type" => type})
          {:ok, result} = execute_tool(call, context)
          result["memory_id"]
        end

      # Recall all
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, recall_result} = execute_tool(recall_call, context)

      recalled_ids = Enum.map(recall_result["memories"], & &1["id"])

      for memory_id <- memory_ids do
        assert memory_id in recalled_ids
      end
    end
  end

  describe "7.10.2.2 remember → supersede → recall excludes old" do
    test "superseded memory is excluded from default recall", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_supersede")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember original
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Original decision: Use PostgreSQL",
        "type" => "decision"
      })

      {:ok, remember_result} = execute_tool(remember_call, context)
      original_id = remember_result["memory_id"]

      # Supersede it
      supersede_call = tool_call("knowledge_supersede", %{
        "old_memory_id" => original_id,
        "new_content" => "Updated decision: Use SQLite for simplicity",
        "reason" => "Simplified requirements"
      })

      {:ok, supersede_result} = execute_tool(supersede_call, context)
      new_id = supersede_result["new_id"]

      # Recall without include_superseded
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, recall_result} = execute_tool(recall_call, context)

      recalled_ids = Enum.map(recall_result["memories"], & &1["id"])

      # Original should NOT be in results
      refute original_id in recalled_ids
      # New one should be (if new_id is not nil - it was created)
      if new_id, do: assert(new_id in recalled_ids)
    end

    test "superseded memory included when include_superseded is true", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_supersede_include")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember and supersede
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Old architecture",
        "type" => "architectural_decision"
      })

      {:ok, remember_result} = execute_tool(remember_call, context)
      original_id = remember_result["memory_id"]

      supersede_call = tool_call("knowledge_supersede", %{
        "old_memory_id" => original_id,
        "new_content" => "New architecture",
        "reason" => "Better approach"
      })

      {:ok, _} = execute_tool(supersede_call, context)

      # Recall WITH include_superseded
      recall_call = tool_call("knowledge_recall", %{
        "min_confidence" => 0.0,
        "include_superseded" => true
      })

      {:ok, recall_result} = execute_tool(recall_call, context)

      recalled_ids = Enum.map(recall_result["memories"], & &1["id"])
      assert original_id in recalled_ids
    end
  end

  describe "7.10.2.3 remember → update confidence → recall with new confidence" do
    test "updated confidence is reflected in recall", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_update_confidence")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember with initial confidence
      remember_call = tool_call("knowledge_remember", %{
        "content" => "Hypothesis needs verification",
        "type" => "hypothesis",
        "confidence" => 0.5
      })

      {:ok, remember_result} = execute_tool(remember_call, context)
      memory_id = remember_result["memory_id"]

      # Update confidence
      update_call = tool_call("knowledge_update", %{
        "memory_id" => memory_id,
        "new_confidence" => 0.9
      })

      {:ok, update_result} = execute_tool(update_call, context)
      assert update_result["status"] == "updated"
      assert update_result["confidence"] == 0.9

      # Recall and verify
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, recall_result} = execute_tool(recall_call, context)

      found_memory = Enum.find(recall_result["memories"], &(&1["id"] == memory_id))
      assert found_memory["confidence"] == 0.9
    end
  end

  describe "7.10.2.4 remember fact → update with evidence → confidence preserved" do
    test "adding evidence preserves confidence", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "lifecycle_evidence")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember with specific confidence
      remember_call = tool_call("knowledge_remember", %{
        "content" => "The codebase uses Ecto for database access",
        "type" => "fact",
        "confidence" => 0.85
      })

      {:ok, remember_result} = execute_tool(remember_call, context)
      memory_id = remember_result["memory_id"]

      # Update with evidence only (no confidence change)
      update_call = tool_call("knowledge_update", %{
        "memory_id" => memory_id,
        "add_evidence" => ["lib/app/repo.ex", "mix.exs deps"]
      })

      {:ok, update_result} = execute_tool(update_call, context)
      assert update_result["status"] == "updated"

      # Recall and verify confidence unchanged
      recall_call = tool_call("knowledge_recall", %{"min_confidence" => 0.0})
      {:ok, recall_result} = execute_tool(recall_call, context)

      found_memory = Enum.find(recall_result["memories"], &(&1["id"] == memory_id))
      assert found_memory["confidence"] == 0.85
    end
  end

  # ============================================================================
  # Section 7.10.3: Cross-Tool Integration Tests
  # ============================================================================

  describe "7.10.3.1 project_conventions finds convention type memories" do
    test "project_conventions returns convention and coding_standard memories", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "conventions_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember various types
      memories = [
        {"Use Credo for linting", "coding_standard"},
        {"Follow Phoenix conventions for contexts", "convention"},
        {"This is a fact", "fact"},
        {"This is a decision", "decision"}
      ]

      for {content, type} <- memories do
        call = tool_call("knowledge_remember", %{"content" => content, "type" => type})
        {:ok, _} = execute_tool(call, context)
      end

      # Query conventions
      conventions_call = tool_call("project_conventions", %{})
      {:ok, result} = execute_tool(conventions_call, context)

      assert result["count"] >= 2

      types = Enum.map(result["conventions"], & &1["type"])
      assert "coding_standard" in types or "convention" in types
      refute "fact" in types
      refute "decision" in types
    end
  end

  describe "7.10.3.2 project_decisions finds decision type memories" do
    test "project_decisions returns decision type memories", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "decisions_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember various types
      memories = [
        {"Use PostgreSQL for persistence", "decision"},
        {"Adopt event sourcing", "architectural_decision"},
        {"This is a fact", "fact"},
        {"This is a convention", "convention"}
      ]

      for {content, type} <- memories do
        call = tool_call("knowledge_remember", %{"content" => content, "type" => type})
        {:ok, _} = execute_tool(call, context)
      end

      # Query decisions
      decisions_call = tool_call("project_decisions", %{})
      {:ok, result} = execute_tool(decisions_call, context)

      assert result["count"] >= 2

      types = Enum.map(result["decisions"], & &1["type"])
      assert Enum.any?(types, &(&1 in ["decision", "architectural_decision"]))
      refute "fact" in types
      refute "convention" in types
    end
  end

  describe "7.10.3.3 project_risks finds risk type memories" do
    test "project_risks returns risk type memories", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "risks_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember various types
      memories = [
        {"Database migration may cause downtime", "risk"},
        {"Memory usage could spike under load", "risk"},
        {"This is a fact", "fact"},
        {"This is a decision", "decision"}
      ]

      for {content, type} <- memories do
        call = tool_call("knowledge_remember", %{"content" => content, "type" => type})
        {:ok, _} = execute_tool(call, context)
      end

      # Query risks
      risks_call = tool_call("project_risks", %{})
      {:ok, result} = execute_tool(risks_call, context)

      assert result["count"] >= 2

      types = Enum.map(result["risks"], & &1["type"])
      assert Enum.all?(types, &(&1 == "risk"))
    end

    test "project_risks respects min_confidence filter", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "risks_confidence_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember risks with different confidences
      memories = [
        {"High confidence risk", 0.9},
        {"Low confidence risk", 0.3}
      ]

      for {content, confidence} <- memories do
        call = tool_call("knowledge_remember", %{
          "content" => content,
          "type" => "risk",
          "confidence" => confidence
        })

        {:ok, _} = execute_tool(call, context)
      end

      # Query with high min_confidence
      risks_call = tool_call("project_risks", %{"min_confidence" => 0.8})
      {:ok, result} = execute_tool(risks_call, context)

      # Should only find high confidence risk
      assert result["count"] == 1
      assert hd(result["risks"])["content"] == "High confidence risk"
    end
  end

  describe "7.10.3.4 knowledge_context finds relevant memories" do
    test "knowledge_context returns memories matching context hint", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "context_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember various content
      memories = [
        {"Phoenix uses channels for WebSocket communication", "fact"},
        {"Ecto provides database query DSL", "fact"},
        {"Consider Redis for caching", "assumption"}
      ]

      for {content, type} <- memories do
        call = tool_call("knowledge_remember", %{"content" => content, "type" => type})
        {:ok, _} = execute_tool(call, context)
      end

      # Query with context hint about Phoenix
      context_call = tool_call("knowledge_context", %{
        "context_hint" => "WebSocket communication in Phoenix"
      })

      {:ok, result} = execute_tool(context_call, context)

      assert result["count"] >= 1
      assert is_list(result["memories"])

      # The Phoenix WebSocket memory should be in results
      contents = Enum.map(result["memories"], & &1["content"])
      assert Enum.any?(contents, &String.contains?(&1, "WebSocket"))
    end
  end

  describe "7.10.3.5 knowledge_graph_query traverses relationships" do
    test "knowledge_graph_query finds same_type relationships", %{tmp_base: tmp_base} do
      project_dir = create_test_dir(tmp_base, "graph_query_test")
      session = create_session(project_dir)

      on_exit(fn -> cleanup_session(session) end)

      {:ok, context} = Executor.build_context(session.id)

      # Remember multiple facts
      memories = [
        "Elixir compiles to BEAM bytecode",
        "BEAM provides lightweight processes",
        "Processes are isolated and share nothing"
      ]

      memory_ids =
        for content <- memories do
          call = tool_call("knowledge_remember", %{"content" => content, "type" => "fact"})
          {:ok, result} = execute_tool(call, context)
          result["memory_id"]
        end

      first_id = hd(memory_ids)

      # Query for same_type from first memory
      query_call = tool_call("knowledge_graph_query", %{
        "start_from" => first_id,
        "relationship" => "same_type"
      })

      {:ok, result} = execute_tool(query_call, context)

      # Should find other facts
      assert result["count"] >= 1
      found_ids = Enum.map(result["related"], & &1["id"])

      # All results should be facts (same type as start_from)
      for memory <- result["related"] do
        assert memory["type"] == "fact"
      end
    end
  end
end
