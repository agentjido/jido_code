defmodule JidoCode.Integration.MemoryPhase1Test do
  @moduledoc """
  Integration tests for Phase 1 Memory System.

  These tests verify that the memory foundation works correctly with the existing
  session lifecycle, including:

  - Session.State initializes with empty memory fields
  - Memory fields persist across multiple GenServer calls
  - Session restart resets memory fields to defaults
  - Memory operations don't interfere with existing Session.State operations
  - Multiple sessions have isolated memory state
  """
  use ExUnit.Case, async: false

  @moduletag :integration

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.State
  alias JidoCode.SessionSupervisor
  alias JidoCode.Memory.ShortTerm.AccessLog
  alias JidoCode.Memory.ShortTerm.PendingMemories
  alias JidoCode.Memory.ShortTerm.WorkingContext

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    setup_session_supervisor("memory_phase1_test")
  end

  # ============================================================================
  # 1.6.1 Session Lifecycle Integration Tests
  # ============================================================================

  describe "Session.State initializes with empty memory fields" do
    test "new session has empty working_context", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      {:ok, state} = State.get_state(session.id)

      assert %WorkingContext{} = state.working_context
      assert state.working_context.items == %{}
      assert state.working_context.current_tokens == 0
      assert state.working_context.max_tokens == 12_000

      SessionSupervisor.stop_session(session.id)
    end

    test "new session has empty pending_memories", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      {:ok, state} = State.get_state(session.id)

      assert %PendingMemories{} = state.pending_memories
      assert state.pending_memories.items == %{}
      assert state.pending_memories.agent_decisions == []
      assert state.pending_memories.max_items == 500

      SessionSupervisor.stop_session(session.id)
    end

    test "new session has empty access_log", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      {:ok, state} = State.get_state(session.id)

      assert %AccessLog{} = state.access_log
      assert state.access_log.entries == []
      assert state.access_log.max_entries == 1000

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Memory fields persist across multiple GenServer calls" do
    test "working_context persists across multiple operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add multiple context items
      :ok = State.update_context(session.id, :framework, "Phoenix")
      :ok = State.update_context(session.id, :primary_language, "Elixir")
      :ok = State.update_context(session.id, :project_root, project_path)

      # Perform other state operations
      message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message)
      {:ok, _} = State.set_scroll_offset(session.id, 10)

      # Verify context persisted through all operations
      {:ok, context} = State.get_all_context(session.id)
      assert context == %{
               framework: "Phoenix",
               primary_language: "Elixir",
               project_root: project_path
             }

      SessionSupervisor.stop_session(session.id)
    end

    test "pending_memories persists across multiple operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add multiple pending memory items
      item1 = %{
        content: "Uses Phoenix framework",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      item2 = %{
        content: "Uses Ecto for database",
        memory_type: :fact,
        confidence: 0.85,
        source_type: :tool,
        importance_score: 0.75
      }

      :ok = State.add_pending_memory(session.id, item1)
      :ok = State.add_pending_memory(session.id, item2)

      # Perform other state operations
      message = %{id: "msg-1", role: :user, content: "Test", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message)

      # Add an agent decision
      agent_item = %{
        content: "Critical pattern discovered",
        memory_type: :discovery,
        confidence: 0.95,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      # Verify all pending memories persisted
      {:ok, ready_items} = State.get_pending_memories(session.id)
      # Should include both implicit items (above 0.6 threshold) and agent decision
      assert length(ready_items) == 3

      SessionSupervisor.stop_session(session.id)
    end

    test "access_log persists across multiple operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Record multiple accesses
      :ok = State.record_access(session.id, :framework, :read)
      :ok = State.record_access(session.id, :framework, :read)
      :ok = State.record_access(session.id, :primary_language, :write)

      # Perform other state operations
      message = %{id: "msg-1", role: :user, content: "Test", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message)

      # Record more accesses
      :ok = State.record_access(session.id, {:memory, "mem-123"}, :query)

      # Give casts time to process
      Process.sleep(20)

      # Verify access stats persisted
      {:ok, framework_stats} = State.get_access_stats(session.id, :framework)
      assert framework_stats.frequency == 2

      {:ok, lang_stats} = State.get_access_stats(session.id, :primary_language)
      assert lang_stats.frequency == 1

      {:ok, mem_stats} = State.get_access_stats(session.id, {:memory, "mem-123"})
      assert mem_stats.frequency == 1

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Session restart resets memory fields to defaults" do
    test "memory fields are reset after session restart", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add data to all memory fields
      :ok = State.update_context(session.id, :framework, "Phoenix")

      item = %{
        content: "Test memory",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, item)
      :ok = State.record_access(session.id, :framework, :read)

      # Give cast time to process
      Process.sleep(10)

      # Verify data was added
      {:ok, context} = State.get_all_context(session.id)
      assert context[:framework] == "Phoenix"

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1

      {:ok, stats} = State.get_access_stats(session.id, :framework)
      assert stats.frequency == 1

      # Stop the session
      SessionSupervisor.stop_session(session.id)

      # Wait for session to terminate
      Process.sleep(50)

      # Start a new session with the same path (simulating restart)
      {:ok, new_session} = Session.new(name: "Test Restarted", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(new_session)

      # Verify memory fields are reset to defaults
      {:ok, new_context} = State.get_all_context(new_session.id)
      assert new_context == %{}

      {:ok, new_ready_items} = State.get_pending_memories(new_session.id)
      assert new_ready_items == []

      {:ok, new_stats} = State.get_access_stats(new_session.id, :framework)
      assert new_stats.frequency == 0

      SessionSupervisor.stop_session(new_session.id)
    end
  end

  describe "Memory operations don't interfere with existing Session.State operations" do
    test "message operations work alongside memory operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Interleave memory and message operations
      :ok = State.update_context(session.id, :framework, "Phoenix")

      msg1 = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, msg1)

      :ok = State.record_access(session.id, :framework, :read)

      msg2 = %{id: "msg-2", role: :assistant, content: "Hi!", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, msg2)

      item = %{
        content: "Test",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, item)

      msg3 = %{id: "msg-3", role: :user, content: "Thanks", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, msg3)

      # Verify both message and memory systems work correctly
      {:ok, messages} = State.get_messages(session.id)
      assert length(messages) == 3

      {:ok, context} = State.get_all_context(session.id)
      assert context[:framework] == "Phoenix"

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1

      SessionSupervisor.stop_session(session.id)
    end

    test "streaming operations work alongside memory operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add memory data
      :ok = State.update_context(session.id, :framework, "Phoenix")

      # Start streaming
      {:ok, _} = State.start_streaming(session.id, "stream-1")
      :ok = State.update_streaming(session.id, "Hello ")

      # Add more memory data during streaming
      :ok = State.record_access(session.id, :framework, :read)

      :ok = State.update_streaming(session.id, "world!")

      # Give casts time to process
      Process.sleep(10)

      # End streaming
      {:ok, message} = State.end_streaming(session.id)
      assert message.content == "Hello world!"

      # Verify memory operations still work after streaming
      {:ok, context} = State.get_all_context(session.id)
      assert context[:framework] == "Phoenix"

      {:ok, stats} = State.get_access_stats(session.id, :framework)
      assert stats.frequency == 1

      SessionSupervisor.stop_session(session.id)
    end

    test "todo operations work alongside memory operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Interleave memory and todo operations
      :ok = State.update_context(session.id, :current_task, "Implement feature")

      todos = [
        %{id: "t-1", content: "Task 1", status: :pending},
        %{id: "t-2", content: "Task 2", status: :in_progress}
      ]

      {:ok, _} = State.update_todos(session.id, todos)

      item = %{
        content: "Discovered pattern",
        memory_type: :discovery,
        confidence: 0.8,
        source_type: :tool,
        importance_score: 0.7
      }

      :ok = State.add_pending_memory(session.id, item)

      # Verify both systems work
      {:ok, returned_todos} = State.get_todos(session.id)
      assert length(returned_todos) == 2

      {:ok, context} = State.get_all_context(session.id)
      assert context[:current_task] == "Implement feature"

      SessionSupervisor.stop_session(session.id)
    end

    test "file tracking operations work alongside memory operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      test_file = Path.join(project_path, "test.ex")

      # Interleave memory and file tracking operations
      :ok = State.update_context(session.id, :active_file, test_file)
      {:ok, _} = State.track_file_read(session.id, test_file)

      :ok = State.record_access(session.id, :active_file, :write)

      {:ok, _} = State.track_file_write(session.id, test_file)

      # Give cast time to process
      Process.sleep(10)

      # Verify both systems work
      {:ok, was_read} = State.file_was_read?(session.id, test_file)
      assert was_read == true

      {:ok, context} = State.get_all_context(session.id)
      assert context[:active_file] == test_file

      {:ok, stats} = State.get_access_stats(session.id, :active_file)
      assert stats.frequency == 1

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Multiple sessions have isolated memory state" do
    test "working_context is isolated between sessions", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Add different context to each session
      :ok = State.update_context(session1.id, :framework, "Phoenix")
      :ok = State.update_context(session2.id, :framework, "Rails")

      :ok = State.update_context(session1.id, :primary_language, "Elixir")
      :ok = State.update_context(session2.id, :primary_language, "Ruby")

      # Verify isolation
      {:ok, context1} = State.get_all_context(session1.id)
      assert context1 == %{framework: "Phoenix", primary_language: "Elixir"}

      {:ok, context2} = State.get_all_context(session2.id)
      assert context2 == %{framework: "Rails", primary_language: "Ruby"}

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "pending_memories are isolated between sessions", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Add different memories to each session
      item1 = %{
        content: "Phoenix pattern",
        memory_type: :discovery,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      item2 = %{
        content: "Rails pattern",
        memory_type: :discovery,
        confidence: 0.85,
        source_type: :tool,
        importance_score: 0.75
      }

      :ok = State.add_pending_memory(session1.id, item1)
      :ok = State.add_pending_memory(session2.id, item2)

      # Add agent decision only to session1
      agent_item = %{
        content: "Critical for session1",
        memory_type: :decision,
        confidence: 0.95,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session1.id, agent_item)

      # Verify isolation
      {:ok, ready1} = State.get_pending_memories(session1.id)
      {:ok, ready2} = State.get_pending_memories(session2.id)

      assert length(ready1) == 2  # implicit + agent decision
      assert length(ready2) == 1  # only implicit

      contents1 = Enum.map(ready1, & &1.content)
      assert "Phoenix pattern" in contents1
      assert "Critical for session1" in contents1

      contents2 = Enum.map(ready2, & &1.content)
      assert contents2 == ["Rails pattern"]

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "access_log is isolated between sessions", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Record different access patterns
      :ok = State.record_access(session1.id, :framework, :read)
      :ok = State.record_access(session1.id, :framework, :read)
      :ok = State.record_access(session1.id, :framework, :read)

      :ok = State.record_access(session2.id, :framework, :write)

      # Give casts time to process
      Process.sleep(20)

      # Verify isolation
      {:ok, stats1} = State.get_access_stats(session1.id, :framework)
      {:ok, stats2} = State.get_access_stats(session2.id, :framework)

      assert stats1.frequency == 3
      assert stats2.frequency == 1

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "clearing memory in one session doesn't affect another", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Add same data to both sessions
      :ok = State.update_context(session1.id, :framework, "Phoenix")
      :ok = State.update_context(session2.id, :framework, "Phoenix")

      # Clear context in session1 only
      :ok = State.clear_context(session1.id)

      # Verify session2 is unaffected
      {:ok, context1} = State.get_all_context(session1.id)
      {:ok, context2} = State.get_all_context(session2.id)

      assert context1 == %{}
      assert context2 == %{framework: "Phoenix"}

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end
  end
end
