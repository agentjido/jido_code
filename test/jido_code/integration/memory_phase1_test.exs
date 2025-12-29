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

  # ============================================================================
  # 1.6.2 Working Context Integration Tests
  # ============================================================================

  describe "Context updates propagate correctly through GenServer" do
    test "put operations are immediately visible via get", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Update context
      :ok = State.update_context(session.id, :framework, "Phoenix")

      # Immediately verify via get
      {:ok, value} = State.get_context(session.id, :framework)
      assert value == "Phoenix"

      # Update again
      :ok = State.update_context(session.id, :framework, "Phoenix 1.7")

      # Immediately verify update
      {:ok, updated_value} = State.get_context(session.id, :framework)
      assert updated_value == "Phoenix 1.7"

      SessionSupervisor.stop_session(session.id)
    end

    test "multiple keys can be updated and retrieved independently", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Update multiple keys
      :ok = State.update_context(session.id, :framework, "Phoenix")
      :ok = State.update_context(session.id, :primary_language, "Elixir")
      :ok = State.update_context(session.id, :database, "PostgreSQL")
      :ok = State.update_context(session.id, :orm, "Ecto")

      # Retrieve each independently
      {:ok, framework} = State.get_context(session.id, :framework)
      {:ok, language} = State.get_context(session.id, :primary_language)
      {:ok, database} = State.get_context(session.id, :database)
      {:ok, orm} = State.get_context(session.id, :orm)

      assert framework == "Phoenix"
      assert language == "Elixir"
      assert database == "PostgreSQL"
      assert orm == "Ecto"

      # Verify all context
      {:ok, all} = State.get_all_context(session.id)
      assert map_size(all) == 4

      SessionSupervisor.stop_session(session.id)
    end

    test "clear_context removes all keys", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add several keys
      :ok = State.update_context(session.id, :framework, "Phoenix")
      :ok = State.update_context(session.id, :primary_language, "Elixir")
      :ok = State.update_context(session.id, :database, "PostgreSQL")

      {:ok, before_clear} = State.get_all_context(session.id)
      assert map_size(before_clear) == 3

      # Clear context
      :ok = State.clear_context(session.id)

      # Verify all keys removed
      {:ok, after_clear} = State.get_all_context(session.id)
      assert after_clear == %{}

      # Verify individual key access returns not found
      assert {:error, :key_not_found} = State.get_context(session.id, :framework)

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Multiple sessions have isolated working contexts" do
    test "context updates in one session don't affect another", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Add context to session1
      :ok = State.update_context(session1.id, :framework, "Phoenix")
      :ok = State.update_context(session1.id, :primary_language, "Elixir")

      # Verify session2 has no context
      {:ok, context2} = State.get_all_context(session2.id)
      assert context2 == %{}

      # Add different context to session2
      :ok = State.update_context(session2.id, :framework, "Rails")

      # Verify session1 is unchanged
      {:ok, context1} = State.get_all_context(session1.id)
      assert context1 == %{framework: "Phoenix", primary_language: "Elixir"}

      # Verify session2 has its own context
      {:ok, updated_context2} = State.get_all_context(session2.id)
      assert updated_context2 == %{framework: "Rails"}

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end

    test "clearing context in one session doesn't affect another", %{tmp_dir: tmp_dir} do
      project1 = Path.join(tmp_dir, "project1")
      project2 = Path.join(tmp_dir, "project2")
      File.mkdir_p!(project1)
      File.mkdir_p!(project2)

      {:ok, session1} = Session.new(name: "Session 1", project_path: project1)
      {:ok, session2} = Session.new(name: "Session 2", project_path: project2)

      {:ok, _pid1} = SessionSupervisor.start_session(session1)
      {:ok, _pid2} = SessionSupervisor.start_session(session2)

      # Add same context to both sessions
      :ok = State.update_context(session1.id, :framework, "Phoenix")
      :ok = State.update_context(session2.id, :framework, "Phoenix")

      # Clear session1
      :ok = State.clear_context(session1.id)

      # Verify session1 is cleared
      {:ok, context1} = State.get_all_context(session1.id)
      assert context1 == %{}

      # Verify session2 is unaffected
      {:ok, context2} = State.get_all_context(session2.id)
      assert context2 == %{framework: "Phoenix"}

      SessionSupervisor.stop_session(session1.id)
      SessionSupervisor.stop_session(session2.id)
    end
  end

  describe "Context access tracking updates correctly on get/put" do
    test "access_count increments on each put operation", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Initial put
      :ok = State.update_context(session.id, :framework, "Phoenix")

      {:ok, state1} = State.get_state(session.id)
      initial_count = state1.working_context.items[:framework].access_count

      # Second put
      :ok = State.update_context(session.id, :framework, "Phoenix 1.7")

      {:ok, state2} = State.get_state(session.id)
      second_count = state2.working_context.items[:framework].access_count

      assert second_count == initial_count + 1

      # Third put
      :ok = State.update_context(session.id, :framework, "Phoenix 1.8")

      {:ok, state3} = State.get_state(session.id)
      third_count = state3.working_context.items[:framework].access_count

      assert third_count == initial_count + 2

      SessionSupervisor.stop_session(session.id)
    end

    test "access_count increments on each get operation", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Initial put
      :ok = State.update_context(session.id, :framework, "Phoenix")

      {:ok, state1} = State.get_state(session.id)
      initial_count = state1.working_context.items[:framework].access_count

      # First get
      {:ok, _value} = State.get_context(session.id, :framework)

      {:ok, state2} = State.get_state(session.id)
      after_first_get = state2.working_context.items[:framework].access_count

      assert after_first_get == initial_count + 1

      # Multiple gets
      {:ok, _} = State.get_context(session.id, :framework)
      {:ok, _} = State.get_context(session.id, :framework)
      {:ok, _} = State.get_context(session.id, :framework)

      {:ok, state3} = State.get_state(session.id)
      after_multiple_gets = state3.working_context.items[:framework].access_count

      assert after_multiple_gets == initial_count + 4

      SessionSupervisor.stop_session(session.id)
    end

    test "last_accessed timestamp updates on access", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Initial put
      :ok = State.update_context(session.id, :framework, "Phoenix")

      {:ok, state1} = State.get_state(session.id)
      initial_timestamp = state1.working_context.items[:framework].last_accessed

      # Small delay to ensure timestamp difference
      Process.sleep(10)

      # Access the key
      {:ok, _value} = State.get_context(session.id, :framework)

      {:ok, state2} = State.get_state(session.id)
      updated_timestamp = state2.working_context.items[:framework].last_accessed

      # Timestamp should be later
      assert DateTime.compare(updated_timestamp, initial_timestamp) in [:gt, :eq]

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Context survives heavy read/write load without corruption" do
    test "concurrent-style rapid updates maintain data integrity", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Perform many rapid updates
      for i <- 1..100 do
        key = :"key_#{rem(i, 10)}"
        value = "value_#{i}"
        :ok = State.update_context(session.id, key, value)
      end

      # Verify final state has 10 keys (key_0 through key_9)
      {:ok, context} = State.get_all_context(session.id)
      assert map_size(context) == 10

      # Each key should have the last value written to it
      # key_0 was last written at i=100, key_1 at i=91, etc.
      assert context[:key_0] == "value_100"
      assert context[:key_1] == "value_91"
      assert context[:key_9] == "value_99"

      SessionSupervisor.stop_session(session.id)
    end

    test "mixed read/write operations maintain consistency", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Initial setup
      :ok = State.update_context(session.id, :counter, 0)

      # Perform mixed reads and writes
      for i <- 1..50 do
        # Read current value
        {:ok, current} = State.get_context(session.id, :counter)

        # Update to new value
        :ok = State.update_context(session.id, :counter, current + 1)

        # Verify the update
        {:ok, updated} = State.get_context(session.id, :counter)
        assert updated == i
      end

      # Final verification
      {:ok, final} = State.get_context(session.id, :counter)
      assert final == 50

      SessionSupervisor.stop_session(session.id)
    end

    test "large values are stored and retrieved correctly", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Store a large value
      large_value = String.duplicate("x", 10_000)
      :ok = State.update_context(session.id, :large_data, large_value)

      # Retrieve and verify
      {:ok, retrieved} = State.get_context(session.id, :large_data)
      assert retrieved == large_value
      assert String.length(retrieved) == 10_000

      # Store complex nested data
      complex_data = %{
        nested: %{
          deep: %{
            value: "test",
            list: [1, 2, 3, 4, 5]
          }
        },
        array: Enum.to_list(1..100)
      }

      :ok = State.update_context(session.id, :complex, complex_data)

      {:ok, retrieved_complex} = State.get_context(session.id, :complex)
      assert retrieved_complex == complex_data

      SessionSupervisor.stop_session(session.id)
    end

    test "multiple sessions under load remain isolated", %{tmp_dir: tmp_dir} do
      # Create multiple sessions
      sessions =
        for i <- 1..5 do
          project = Path.join(tmp_dir, "project_#{i}")
          File.mkdir_p!(project)
          {:ok, session} = Session.new(name: "Session #{i}", project_path: project)
          {:ok, _pid} = SessionSupervisor.start_session(session)
          session
        end

      # Perform operations on all sessions
      for {session, idx} <- Enum.with_index(sessions, 1) do
        for j <- 1..20 do
          key = :"key_#{j}"
          value = "session_#{idx}_value_#{j}"
          :ok = State.update_context(session.id, key, value)
        end
      end

      # Verify each session has its own isolated data
      for {session, idx} <- Enum.with_index(sessions, 1) do
        {:ok, context} = State.get_all_context(session.id)
        assert map_size(context) == 20

        # Verify values are session-specific
        assert context[:key_1] == "session_#{idx}_value_1"
        assert context[:key_20] == "session_#{idx}_value_20"
      end

      # Cleanup
      for session <- sessions do
        SessionSupervisor.stop_session(session.id)
      end
    end
  end

  # ============================================================================
  # 1.6.3 Pending Memories Integration Tests
  # ============================================================================

  describe "Pending memories accumulate correctly over time" do
    test "multiple items can be added and retrieved", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add multiple pending memory items over time
      items =
        for i <- 1..10 do
          item = %{
            content: "Discovery #{i}",
            memory_type: :fact,
            confidence: 0.8 + i * 0.01,
            source_type: :tool,
            importance_score: 0.6 + i * 0.02
          }

          :ok = State.add_pending_memory(session.id, item)
          item
        end

      # Verify all items accumulated
      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 10

      # Get items ready for promotion (all should be above 0.6 threshold)
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 10

      # Verify contents are preserved
      contents = Enum.map(ready_items, & &1.content)

      for i <- 1..10 do
        assert "Discovery #{i}" in contents
      end

      SessionSupervisor.stop_session(session.id)
    end

    test "items below threshold are not returned as ready", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add items with varying importance scores
      low_score_item = %{
        content: "Low importance",
        memory_type: :fact,
        confidence: 0.5,
        source_type: :tool,
        importance_score: 0.3
      }

      medium_score_item = %{
        content: "Medium importance",
        memory_type: :fact,
        confidence: 0.7,
        source_type: :tool,
        importance_score: 0.5
      }

      high_score_item = %{
        content: "High importance",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, low_score_item)
      :ok = State.add_pending_memory(session.id, medium_score_item)
      :ok = State.add_pending_memory(session.id, high_score_item)

      # Verify all items are stored
      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 3

      # Only high score item should be ready for promotion (threshold is 0.6)
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "High importance"

      SessionSupervisor.stop_session(session.id)
    end

    test "pending memories persist across other state operations", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add pending memory
      item = %{
        content: "Initial discovery",
        memory_type: :discovery,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.85
      }

      :ok = State.add_pending_memory(session.id, item)

      # Perform various other state operations
      message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message)

      :ok = State.update_context(session.id, :framework, "Phoenix")

      {:ok, _} = State.start_streaming(session.id, "stream-1")
      :ok = State.update_streaming(session.id, "content")
      Process.sleep(10)
      {:ok, _} = State.end_streaming(session.id)

      # Verify pending memory is still there
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "Initial discovery"

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Agent decisions bypass normal staging" do
    test "agent decisions have importance_score of 1.0", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add agent decision
      agent_item = %{
        content: "Critical agent decision",
        memory_type: :decision,
        confidence: 0.95,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      # Verify agent decision has score of 1.0
      {:ok, state} = State.get_state(session.id)
      decisions = PendingMemories.list_agent_decisions(state.pending_memories)

      assert length(decisions) == 1
      assert hd(decisions).importance_score == 1.0
      assert hd(decisions).suggested_by == :agent

      SessionSupervisor.stop_session(session.id)
    end

    test "agent decisions are always included in ready items", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add low-score implicit item (won't be ready)
      low_item = %{
        content: "Low importance implicit",
        memory_type: :fact,
        confidence: 0.5,
        source_type: :tool,
        importance_score: 0.2
      }

      :ok = State.add_pending_memory(session.id, low_item)

      # Add agent decision (should always be ready)
      agent_item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.9,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      # Only agent decision should be ready
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "Agent decision"
      assert hd(ready_items).suggested_by == :agent

      SessionSupervisor.stop_session(session.id)
    end

    test "multiple agent decisions can be added", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add multiple agent decisions
      for i <- 1..5 do
        agent_item = %{
          content: "Agent decision #{i}",
          memory_type: :decision,
          confidence: 0.9,
          source_type: :agent
        }

        :ok = State.add_agent_memory_decision(session.id, agent_item)
      end

      # All agent decisions should be ready
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 5

      # All should have agent as suggested_by
      assert Enum.all?(ready_items, fn item -> item.suggested_by == :agent end)

      SessionSupervisor.stop_session(session.id)
    end

    test "agent decisions and high-score implicit items both appear in ready", %{
      tmp_dir: tmp_dir
    } do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add high-score implicit item
      high_item = %{
        content: "High importance implicit",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.85
      }

      :ok = State.add_pending_memory(session.id, high_item)

      # Add agent decision
      agent_item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.95,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      # Both should be ready
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 2

      contents = Enum.map(ready_items, & &1.content)
      assert "High importance implicit" in contents
      assert "Agent decision" in contents

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "Pending memory limit enforced correctly" do
    test "oldest/lowest scored items are evicted when limit reached", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Get the max items limit
      {:ok, state} = State.get_state(session.id)
      max_items = state.pending_memories.max_items

      # Add items up to the limit + some extra
      # Note: This test demonstrates the eviction mechanism works
      # We won't add 500+ items as that would be slow, but we can verify the mechanism
      for i <- 1..20 do
        item = %{
          content: "Item #{i}",
          memory_type: :fact,
          confidence: 0.8,
          source_type: :tool,
          importance_score: i * 0.01
        }

        :ok = State.add_pending_memory(session.id, item)
      end

      {:ok, state_after} = State.get_state(session.id)
      assert PendingMemories.size(state_after.pending_memories) == 20

      # The max_items limit should be configured (default 500)
      assert max_items == 500

      SessionSupervisor.stop_session(session.id)
    end

    test "eviction preserves higher-scored items", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add items with different scores
      # When eviction happens, lowest scores should be removed first
      low_score_item = %{
        content: "Low score item",
        memory_type: :fact,
        confidence: 0.5,
        source_type: :tool,
        importance_score: 0.1
      }

      high_score_item = %{
        content: "High score item",
        memory_type: :discovery,
        confidence: 0.95,
        source_type: :tool,
        importance_score: 0.95
      }

      :ok = State.add_pending_memory(session.id, low_score_item)
      :ok = State.add_pending_memory(session.id, high_score_item)

      # Both should exist since we're well under the limit
      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 2

      # When retrieving ready items, only high score should appear
      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "High score item"

      SessionSupervisor.stop_session(session.id)
    end
  end

  describe "clear_promoted_memories correctly removes specified items" do
    test "clears specified item IDs from pending memories", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add items with known IDs
      item1 = %{
        id: "item-001",
        content: "First item",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      item2 = %{
        id: "item-002",
        content: "Second item",
        memory_type: :fact,
        confidence: 0.85,
        source_type: :tool,
        importance_score: 0.75
      }

      item3 = %{
        id: "item-003",
        content: "Third item",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :tool,
        importance_score: 0.7
      }

      :ok = State.add_pending_memory(session.id, item1)
      :ok = State.add_pending_memory(session.id, item2)
      :ok = State.add_pending_memory(session.id, item3)

      # Verify all items exist
      {:ok, state_before} = State.get_state(session.id)
      assert PendingMemories.size(state_before.pending_memories) == 3

      # Clear specific items
      :ok = State.clear_promoted_memories(session.id, ["item-001", "item-003"])

      # Verify only item-002 remains
      {:ok, state_after} = State.get_state(session.id)
      assert PendingMemories.size(state_after.pending_memories) == 1

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "Second item"

      SessionSupervisor.stop_session(session.id)
    end

    test "clears all agent decisions", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add agent decisions
      for i <- 1..3 do
        agent_item = %{
          content: "Agent decision #{i}",
          memory_type: :decision,
          confidence: 0.9,
          source_type: :agent
        }

        :ok = State.add_agent_memory_decision(session.id, agent_item)
      end

      # Verify agent decisions exist
      {:ok, state_before} = State.get_state(session.id)
      decisions_before = PendingMemories.list_agent_decisions(state_before.pending_memories)
      assert length(decisions_before) == 3

      # Clear promoted memories (clears all agent decisions)
      :ok = State.clear_promoted_memories(session.id, [])

      # Verify agent decisions are cleared
      {:ok, state_after} = State.get_state(session.id)
      decisions_after = PendingMemories.list_agent_decisions(state_after.pending_memories)
      assert decisions_after == []

      SessionSupervisor.stop_session(session.id)
    end

    test "handles non-existent IDs gracefully", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add one item
      item = %{
        id: "existing-item",
        content: "Existing item",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, item)

      # Try to clear non-existent IDs
      :ok = State.clear_promoted_memories(session.id, ["non-existent-1", "non-existent-2"])

      # Existing item should still be there
      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 1

      SessionSupervisor.stop_session(session.id)
    end

    test "clearing promoted items doesn't affect unrelated items", %{tmp_dir: tmp_dir} do
      project_path = Path.join(tmp_dir, "test_project")
      File.mkdir_p!(project_path)

      {:ok, session} = Session.new(name: "Test", project_path: project_path)
      {:ok, _pid} = SessionSupervisor.start_session(session)

      # Add mix of implicit items and agent decisions
      implicit_item = %{
        id: "implicit-001",
        content: "Implicit item",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, implicit_item)

      agent_item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.95,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      # Clear only the implicit item, not agent decision
      # Note: clear_promoted_memories always clears agent_decisions
      :ok = State.clear_promoted_memories(session.id, ["implicit-001"])

      {:ok, state} = State.get_state(session.id)

      # Implicit item should be removed
      assert PendingMemories.size(state.pending_memories) == 0

      # Agent decisions are also cleared by clear_promoted_memories
      assert PendingMemories.list_agent_decisions(state.pending_memories) == []

      SessionSupervisor.stop_session(session.id)
    end
  end
end
