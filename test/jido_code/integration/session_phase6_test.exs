defmodule JidoCode.Integration.SessionPhase6Test do
  @moduledoc """
  Integration tests for Phase 6 (Session Persistence) components.

  These tests verify that all Phase 6 components work together correctly:
  - Session saving on close (auto-save)
  - Session listing (persisted and resumable)
  - Session restoration from persisted files
  - Resume command (/resume)
  - Cleanup and maintenance (delete, clear, cleanup)

  Tests use the application's real infrastructure and verify complete
  save-resume cycles end-to-end.
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Session.Persistence

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    # Set API key for test sessions
    System.put_env("ANTHROPIC_API_KEY", "test-key-for-phase6-integration")

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Clean up sessions directory
    sessions_dir = Persistence.sessions_dir()
    File.rm_rf!(sessions_dir)
    File.mkdir_p!(sessions_dir)

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "phase6_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    on_exit(fn ->
      # Stop all test sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      # Clean up temp directories
      File.rm_rf!(tmp_base)
      File.rm_rf!(sessions_dir)
    end)

    {:ok, tmp_base: tmp_base}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp wait_for_supervisor(retries \\ 50) do
    case Process.whereis(SessionSupervisor) do
      nil when retries > 0 ->
        Process.sleep(10)
        wait_for_supervisor(retries - 1)

      nil ->
        raise "SessionSupervisor did not start within timeout"

      _pid ->
        :ok
    end
  end

  defp create_test_session(tmp_base, name \\ "Test Session") do
    project_path = Path.join(tmp_base, name |> String.downcase() |> String.replace(" ", "_"))
    File.mkdir_p!(project_path)

    config = %{
      provider: "anthropic",
      model: "claude-3-5-haiku-20241022",
      temperature: 0.7,
      max_tokens: 4096
    }

    {:ok, session} =
      SessionSupervisor.create_session(project_path: project_path, name: name, config: config)

    session
  end

  defp add_messages_to_session(session_id, count \\ 3) do
    Enum.each(1..count, fn i ->
      message = %{
        id: "test-msg-#{i}-#{System.unique_integer([:positive])}",
        role: :user,
        content: "Test message #{i}",
        timestamp: DateTime.utc_now()
      }

      Session.State.append_message(session_id, message)
    end)
  end

  defp add_todos_to_session(session_id, count \\ 2) do
    todos =
      Enum.map(1..count, fn i ->
        %{
          content: "Test todo #{i}",
          status: if(rem(i, 2) == 0, do: :pending, else: :completed),
          activeForm: "Working on todo #{i}"
        }
      end)

    Session.State.update_todos(session_id, todos)
  end

  defp wait_for_file(file_path, retries \\ 50) do
    if File.exists?(file_path) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_file(file_path, retries - 1)
      else
        {:error, :timeout}
      end
    end
  end

  # ============================================================================
  # Tests
  # ============================================================================

  test "complete save-resume cycle: create, add data, close, resume", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Cycle Test")

    # Add messages and todos
    add_messages_to_session(session.id, 3)
    add_todos_to_session(session.id, 2)

    # Get state before closing
    {:ok, original_messages} = Session.State.get_messages(session.id)
    {:ok, original_todos} = Session.State.get_todos(session.id)

    # Close session (triggers auto-save)
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file to be created
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify file exists
    assert File.exists?(session_file)

    # Verify session is not active
    assert SessionRegistry.lookup(session.id) == {:error, :not_found}

    # Resume session
    {:ok, resumed_session} = Persistence.resume(session.id)

    # Verify session is active again
    assert {:ok, _} = SessionRegistry.lookup(resumed_session.id)

    # Verify messages restored
    {:ok, restored_messages} = Session.State.get_messages(resumed_session.id)
    assert length(restored_messages) == length(original_messages)

    # Sort both lists by content to ensure order-independent comparison
    original_sorted = Enum.sort_by(original_messages, & &1.content)
    restored_sorted = Enum.sort_by(restored_messages, & &1.content)

    Enum.zip(original_sorted, restored_sorted)
    |> Enum.each(fn {orig, restored} ->
      assert orig.role == restored.role
      assert orig.content == restored.content
    end)

    # Verify todos restored
    {:ok, restored_todos} = Session.State.get_todos(resumed_session.id)
    assert length(restored_todos) == length(original_todos)

    Enum.zip(original_todos, restored_todos)
    |> Enum.each(fn {orig, restored} ->
      assert orig.content == restored.content
      assert orig.status == restored.status
    end)

    # Verify session ID preserved
    assert resumed_session.id == session.id

    # Verify config preserved
    assert resumed_session.config.provider == session.config.provider
    assert resumed_session.config.model == session.config.model

    # Verify persisted file deleted after resume
    refute File.exists?(session_file)

    # Cleanup
    SessionSupervisor.stop_session(resumed_session.id)
  end

  test "session appears in resumable list after close", %{tmp_base: tmp_base} do
    # Initially no resumable sessions
    assert Persistence.list_resumable() == []

    # Create and close session
    session = create_test_session(tmp_base, "List Test")
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify appears in resumable list
    resumable = Persistence.list_resumable()
    assert length(resumable) == 1
    assert hd(resumable).id == session.id
  end

  test "session does not appear in resumable list while active", %{tmp_base: tmp_base} do
    # Create session (active)
    session = create_test_session(tmp_base, "Active Test")

    # Close it (creates file)
    :ok = SessionSupervisor.stop_session(session.id)

    # Wait for file
    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify in resumable list
    assert length(Persistence.list_resumable()) == 1

    # Resume it (becomes active)
    {:ok, resumed_session} = Persistence.resume(session.id)

    # Verify NOT in resumable list anymore
    assert Persistence.list_resumable() == []

    # Cleanup
    SessionSupervisor.stop_session(resumed_session.id)
  end

  test "multiple save-resume cycles preserve data", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Multi Cycle")

    # First cycle
    add_messages_to_session(session.id, 2)
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    {:ok, session1} = Persistence.resume(session.id)
    {:ok, messages1} = Session.State.get_messages(session1.id)
    assert length(messages1) == 2

    # Second cycle - add more messages
    add_messages_to_session(session1.id, 3)
    :ok = SessionSupervisor.stop_session(session1.id)

    assert :ok = wait_for_file(session_file)

    {:ok, session2} = Persistence.resume(session1.id)
    {:ok, messages2} = Session.State.get_messages(session2.id)

    # Verify all messages preserved
    assert length(messages2) == 5

    # Cleanup
    SessionSupervisor.stop_session(session2.id)
  end

  test "resume fails gracefully when project path deleted", %{tmp_base: tmp_base} do
    # Create session
    session = create_test_session(tmp_base, "Deleted Path")

    # Close session
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Delete project directory
    File.rm_rf!(session.project_path)

    # Try to resume - should fail
    assert {:error, :project_path_not_found} = Persistence.resume(session.id)

    # Verify session file still exists (not deleted on error)
    assert File.exists?(session_file)
  end

  test "persisted sessions can be deleted without resuming", %{tmp_base: tmp_base} do
    # Create and close session
    session = create_test_session(tmp_base, "Delete Test")
    :ok = SessionSupervisor.stop_session(session.id)

    session_file = Path.join(Persistence.sessions_dir(), "#{session.id}.json")
    assert :ok = wait_for_file(session_file)

    # Verify file exists
    assert File.exists?(session_file)

    # Delete persisted session
    assert :ok = Persistence.delete_persisted(session.id)

    # Verify file deleted
    refute File.exists?(session_file)
  end

  test "cleanup removes old sessions but keeps recent ones", %{tmp_base: tmp_base} do
    # Create two sessions
    session1 = create_test_session(tmp_base, "Old Session")
    session2 = create_test_session(tmp_base, "Recent Session")

    # Close both
    :ok = SessionSupervisor.stop_session(session1.id)
    :ok = SessionSupervisor.stop_session(session2.id)

    file1 = Path.join(Persistence.sessions_dir(), "#{session1.id}.json")
    file2 = Path.join(Persistence.sessions_dir(), "#{session2.id}.json")
    assert :ok = wait_for_file(file1)
    assert :ok = wait_for_file(file2)

    # Modify first file's timestamp to be 31 days old
    old_time = DateTime.add(DateTime.utc_now(), -31 * 86400, :second)
    {:ok, data} = File.read(file1)
    {:ok, json} = Jason.decode(data)
    old_json = Map.put(json, "closed_at", DateTime.to_iso8601(old_time))
    File.write!(file1, Jason.encode!(old_json))

    # Run cleanup (default 30 days)
    result = Persistence.cleanup()

    # Verify old session deleted, recent kept
    assert result.deleted == 1
    assert result.skipped == 1
    refute File.exists?(file1)
    assert File.exists?(file2)
  end

  test "list_persisted includes all closed sessions", %{tmp_base: tmp_base} do
    # Create three sessions
    s1 = create_test_session(tmp_base, "Session 1")
    s2 = create_test_session(tmp_base, "Session 2")
    s3 = create_test_session(tmp_base, "Session 3")

    # Close all
    :ok = SessionSupervisor.stop_session(s1.id)
    :ok = SessionSupervisor.stop_session(s2.id)
    :ok = SessionSupervisor.stop_session(s3.id)

    # Wait for files
    Enum.each([s1, s2, s3], fn s ->
      file = Path.join(Persistence.sessions_dir(), "#{s.id}.json")
      assert :ok = wait_for_file(file)
    end)

    # Verify all in list
    persisted = Persistence.list_persisted()
    assert length(persisted) == 3

    ids = Enum.map(persisted, & &1.id)
    assert s1.id in ids
    assert s2.id in ids
    assert s3.id in ids
  end

  test "clear removes all persisted sessions", %{tmp_base: tmp_base} do
    # Create two sessions
    s1 = create_test_session(tmp_base, "Clear 1")
    s2 = create_test_session(tmp_base, "Clear 2")

    # Close both
    :ok = SessionSupervisor.stop_session(s1.id)
    :ok = SessionSupervisor.stop_session(s2.id)

    # Wait for files
    f1 = Path.join(Persistence.sessions_dir(), "#{s1.id}.json")
    f2 = Path.join(Persistence.sessions_dir(), "#{s2.id}.json")
    assert :ok = wait_for_file(f1)
    assert :ok = wait_for_file(f2)

    # Verify files exist
    assert File.exists?(f1)
    assert File.exists?(f2)

    # Clear all via iteration (same as /resume clear)
    sessions = Persistence.list_persisted()
    Enum.each(sessions, fn s -> Persistence.delete_persisted(s.id) end)

    # Verify all deleted
    refute File.exists?(f1)
    refute File.exists?(f2)
    assert Persistence.list_persisted() == []
  end
end
