defmodule JidoCode.Session.StateTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.State

  @registry JidoCode.SessionProcessRegistry

  setup do
    setup_session_registry("state_test")
  end

  describe "start_link/1" do
    test "starts state process successfully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      assert {:ok, pid} = State.start_link(session: session)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Cleanup
      GenServer.stop(pid)
    end

    test "registers in SessionProcessRegistry with :state key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = State.start_link(session: session)

      # Should be findable via Registry with :state key
      assert [{^pid, _}] = Registry.lookup(@registry, {:state, session.id})

      # Cleanup
      GenServer.stop(pid)
    end

    test "requires :session option" do
      assert_raise KeyError, ~r/:session/, fn ->
        State.start_link([])
      end
    end

    test "fails for duplicate session ID", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid1} = State.start_link(session: session)

      # Second start with same session should fail
      assert {:error, {:already_started, ^pid1}} = State.start_link(session: session)

      # Cleanup
      GenServer.stop(pid1)
    end
  end

  describe "child_spec/1" do
    test "returns correct specification", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      spec = State.child_spec(session: session)

      assert spec.id == {:session_state, session.id}
      assert spec.start == {State, :start_link, [[session: session]]}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "get_session/1" do
    test "returns the session struct", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)

      {:ok, pid} = State.start_link(session: session)

      assert {:ok, returned_session} = State.get_session(pid)
      assert returned_session.id == session.id
      assert returned_session.project_path == session.project_path

      # Cleanup
      GenServer.stop(pid)
    end
  end

  describe "init/1 state structure" do
    test "initializes with empty messages list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.messages == []

      GenServer.stop(pid)
    end

    test "initializes with empty reasoning_steps list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.reasoning_steps == []

      GenServer.stop(pid)
    end

    test "initializes with empty tool_calls list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.tool_calls == []

      GenServer.stop(pid)
    end

    test "initializes with empty todos list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.todos == []

      GenServer.stop(pid)
    end

    test "initializes with scroll_offset = 0", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.scroll_offset == 0

      GenServer.stop(pid)
    end

    test "initializes with streaming_message = nil", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.streaming_message == nil

      GenServer.stop(pid)
    end

    test "initializes with is_streaming = false", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.is_streaming == false

      GenServer.stop(pid)
    end

    test "stores session_id in state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.session_id == session.id

      GenServer.stop(pid)
    end

    test "stores session struct in state for backwards compatibility", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.session == session

      GenServer.stop(pid)
    end
  end

  describe "get_state/1" do
    test "returns full state for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.get_state(session.id)
      assert state.session_id == session.id
      assert state.messages == []
      assert state.reasoning_steps == []
      assert state.todos == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_state("unknown-session-id")
    end
  end

  describe "get_messages/1" do
    test "returns messages list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, messages} = State.get_messages(session.id)
      assert messages == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_messages("unknown-session-id")
    end
  end

  describe "get_reasoning_steps/1" do
    test "returns reasoning steps list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, steps} = State.get_reasoning_steps(session.id)
      assert steps == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_reasoning_steps("unknown-session-id")
    end
  end

  describe "get_todos/1" do
    test "returns todos list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, todos} = State.get_todos(session.id)
      assert todos == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_todos("unknown-session-id")
    end
  end
end
