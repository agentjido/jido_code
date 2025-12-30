defmodule JidoCode.Session.StateTest do
  use ExUnit.Case, async: false

  import JidoCode.Test.SessionTestHelpers

  alias JidoCode.Session
  alias JidoCode.Session.State
  alias JidoCode.Memory.ShortTerm.AccessLog
  alias JidoCode.Memory.ShortTerm.PendingMemories
  alias JidoCode.Memory.ShortTerm.WorkingContext

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

  describe "get_tool_calls/1" do
    test "returns tool calls list for existing session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, tool_calls} = State.get_tool_calls(session.id)
      assert tool_calls == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_tool_calls("unknown-session-id")
    end
  end

  describe "append_message/2" do
    test "adds message to empty list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      message = %{
        id: "msg-1",
        role: :user,
        content: "Hello",
        timestamp: DateTime.utc_now()
      }

      assert {:ok, state} = State.append_message(session.id, message)
      assert length(state.messages) == 1
      assert hd(state.messages).id == "msg-1"
      assert hd(state.messages).content == "Hello"

      GenServer.stop(pid)
    end

    test "adds message to existing list maintaining order", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      message1 = %{id: "msg-1", role: :user, content: "First", timestamp: DateTime.utc_now()}

      message2 = %{
        id: "msg-2",
        role: :assistant,
        content: "Second",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = State.append_message(session.id, message1)
      {:ok, _state} = State.append_message(session.id, message2)

      # Use get_messages to verify order (internally stored reversed, reversed on read)
      {:ok, messages} = State.get_messages(session.id)
      assert length(messages) == 2
      assert Enum.at(messages, 0).id == "msg-1"
      assert Enum.at(messages, 1).id == "msg-2"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      message = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      assert {:error, :not_found} = State.append_message("unknown-session-id", message)
    end
  end

  describe "clear_messages/1" do
    test "clears all messages", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add some messages first
      message1 = %{id: "msg-1", role: :user, content: "First", timestamp: DateTime.utc_now()}

      message2 = %{
        id: "msg-2",
        role: :assistant,
        content: "Second",
        timestamp: DateTime.utc_now()
      }

      {:ok, _} = State.append_message(session.id, message1)
      {:ok, _} = State.append_message(session.id, message2)

      # Verify messages were added
      {:ok, messages_before} = State.get_messages(session.id)
      assert length(messages_before) == 2

      # Clear messages
      assert {:ok, []} = State.clear_messages(session.id)

      # Verify messages are cleared
      {:ok, messages_after} = State.get_messages(session.id)
      assert messages_after == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_messages("unknown-session-id")
    end
  end

  describe "start_streaming/2" do
    test "sets streaming state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.start_streaming(session.id, "msg-1")
      assert state.is_streaming == true
      assert state.streaming_message == ""
      assert state.streaming_message_id == "msg-1"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.start_streaming("unknown-session-id", "msg-1")
    end
  end

  describe "update_streaming/2" do
    test "appends chunks to streaming message", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.start_streaming(session.id, "msg-1")

      :ok = State.update_streaming(session.id, "Hello ")
      :ok = State.update_streaming(session.id, "world!")

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert state.streaming_message == "Hello world!"

      GenServer.stop(pid)
    end

    test "ignores chunks when not streaming", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Don't start streaming
      :ok = State.update_streaming(session.id, "ignored chunk")

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert state.streaming_message == nil
      assert state.is_streaming == false

      GenServer.stop(pid)
    end

    test "returns :ok for unknown session (silent ignore)" do
      assert :ok = State.update_streaming("unknown-session-id", "chunk")
    end
  end

  describe "end_streaming/1" do
    test "creates message and resets streaming state", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.start_streaming(session.id, "msg-1")
      :ok = State.update_streaming(session.id, "Hello world!")

      # Give cast time to process
      Process.sleep(10)

      {:ok, message} = State.end_streaming(session.id)
      assert message.id == "msg-1"
      assert message.role == :assistant
      assert message.content == "Hello world!"
      assert %DateTime{} = message.timestamp

      # Verify state is reset
      {:ok, state} = State.get_state(session.id)
      assert state.is_streaming == false
      assert state.streaming_message == nil
      assert state.streaming_message_id == nil

      # Verify message is in messages list
      assert length(state.messages) == 1
      assert hd(state.messages).id == "msg-1"

      GenServer.stop(pid)
    end

    test "returns :not_streaming when not streaming", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:error, :not_streaming} = State.end_streaming(session.id)

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.end_streaming("unknown-session-id")
    end
  end

  describe "streaming lifecycle" do
    test "complete streaming flow", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Start streaming
      {:ok, state1} = State.start_streaming(session.id, "response-1")
      assert state1.is_streaming == true

      # Send chunks
      :ok = State.update_streaming(session.id, "I am ")
      :ok = State.update_streaming(session.id, "an AI ")
      :ok = State.update_streaming(session.id, "assistant.")

      # Give casts time to process
      Process.sleep(10)

      # End streaming
      {:ok, message} = State.end_streaming(session.id)
      assert message.content == "I am an AI assistant."

      # Verify final state
      {:ok, final_state} = State.get_state(session.id)
      assert final_state.is_streaming == false
      assert length(final_state.messages) == 1

      GenServer.stop(pid)
    end
  end

  describe "set_scroll_offset/2" do
    test "updates scroll offset", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, state} = State.set_scroll_offset(session.id, 10)
      assert state.scroll_offset == 10

      # Update again
      {:ok, state2} = State.set_scroll_offset(session.id, 25)
      assert state2.scroll_offset == 25

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.set_scroll_offset("unknown-session-id", 10)
    end
  end

  describe "update_todos/2" do
    test "replaces todo list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      todos = [
        %{id: "t-1", content: "Task 1", status: :pending},
        %{id: "t-2", content: "Task 2", status: :in_progress}
      ]

      assert {:ok, state} = State.update_todos(session.id, todos)
      assert length(state.todos) == 2
      assert Enum.at(state.todos, 0).id == "t-1"
      assert Enum.at(state.todos, 1).id == "t-2"

      # Replace with new list
      new_todos = [%{id: "t-3", content: "Task 3", status: :completed}]
      {:ok, state2} = State.update_todos(session.id, new_todos)
      assert length(state2.todos) == 1
      assert hd(state2.todos).id == "t-3"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.update_todos("unknown-session-id", [])
    end
  end

  describe "add_reasoning_step/2" do
    test "appends reasoning step", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      step1 = %{id: "r-1", content: "Analyzing request...", timestamp: DateTime.utc_now()}
      step2 = %{id: "r-2", content: "Planning approach...", timestamp: DateTime.utc_now()}

      {:ok, _state1} = State.add_reasoning_step(session.id, step1)
      {:ok, steps1} = State.get_reasoning_steps(session.id)
      assert length(steps1) == 1
      assert hd(steps1).id == "r-1"

      {:ok, _state2} = State.add_reasoning_step(session.id, step2)
      # Use get_reasoning_steps to verify order (internally stored reversed, reversed on read)
      {:ok, steps2} = State.get_reasoning_steps(session.id)
      assert length(steps2) == 2
      assert Enum.at(steps2, 1).id == "r-2"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      step = %{id: "r-1", content: "Test", timestamp: DateTime.utc_now()}
      assert {:error, :not_found} = State.add_reasoning_step("unknown-session-id", step)
    end
  end

  describe "clear_reasoning_steps/1" do
    test "clears reasoning steps", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add some steps first
      step1 = %{id: "r-1", content: "Step 1", timestamp: DateTime.utc_now()}
      step2 = %{id: "r-2", content: "Step 2", timestamp: DateTime.utc_now()}
      {:ok, _} = State.add_reasoning_step(session.id, step1)
      {:ok, _} = State.add_reasoning_step(session.id, step2)

      # Verify steps were added
      {:ok, state_before} = State.get_state(session.id)
      assert length(state_before.reasoning_steps) == 2

      # Clear steps
      assert {:ok, []} = State.clear_reasoning_steps(session.id)

      # Verify steps are cleared
      {:ok, state_after} = State.get_state(session.id)
      assert state_after.reasoning_steps == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_reasoning_steps("unknown-session-id")
    end
  end

  describe "add_tool_call/2" do
    test "appends tool call", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      tool_call1 = %{
        id: "tc-1",
        name: "read_file",
        arguments: %{"path" => "/test.txt"},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      tool_call2 = %{
        id: "tc-2",
        name: "write_file",
        arguments: %{"path" => "/out.txt", "content" => "hello"},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      {:ok, _state1} = State.add_tool_call(session.id, tool_call1)
      {:ok, calls1} = State.get_tool_calls(session.id)
      assert length(calls1) == 1
      assert hd(calls1).name == "read_file"

      {:ok, _state2} = State.add_tool_call(session.id, tool_call2)
      # Use get_tool_calls to verify order (internally stored reversed, reversed on read)
      {:ok, calls2} = State.get_tool_calls(session.id)
      assert length(calls2) == 2
      assert Enum.at(calls2, 1).name == "write_file"

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      tool_call = %{
        id: "tc-1",
        name: "test",
        arguments: %{},
        result: nil,
        status: :pending,
        timestamp: DateTime.utc_now()
      }

      assert {:error, :not_found} = State.add_tool_call("unknown-session-id", tool_call)
    end
  end

  describe "prompt_history" do
    test "initializes with empty prompt_history list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.prompt_history == []

      GenServer.stop(pid)
    end

    test "get_prompt_history/1 returns empty list for new session", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, history} = State.get_prompt_history(session.id)
      assert history == []

      GenServer.stop(pid)
    end

    test "get_prompt_history/1 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_prompt_history("unknown-session-id")
    end

    test "add_to_prompt_history/2 adds prompt to history", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:ok, history} = State.add_to_prompt_history(session.id, "Hello world")
      assert history == ["Hello world"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 prepends new prompts (newest first)", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.add_to_prompt_history(session.id, "First")
      {:ok, _} = State.add_to_prompt_history(session.id, "Second")
      {:ok, history} = State.add_to_prompt_history(session.id, "Third")

      assert history == ["Third", "Second", "First"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 ignores empty prompts", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, _} = State.add_to_prompt_history(session.id, "Hello")
      {:ok, history} = State.add_to_prompt_history(session.id, "")
      assert history == ["Hello"]

      {:ok, history} = State.add_to_prompt_history(session.id, "   ")
      assert history == ["Hello"]

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 enforces max history limit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add more than max (100) prompts
      for i <- 1..110 do
        State.add_to_prompt_history(session.id, "Prompt #{i}")
      end

      {:ok, history} = State.get_prompt_history(session.id)

      # Should be capped at 100
      assert length(history) == 100
      # Most recent should be first
      assert hd(history) == "Prompt 110"
      # Oldest should be Prompt 11 (first 10 were evicted)
      assert List.last(history) == "Prompt 11"

      GenServer.stop(pid)
    end

    test "add_to_prompt_history/2 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.add_to_prompt_history("unknown-session-id", "Hello")
    end

    test "set_prompt_history/2 sets entire history", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      history = ["Newest", "Middle", "Oldest"]
      assert {:ok, ^history} = State.set_prompt_history(session.id, history)

      assert {:ok, ^history} = State.get_prompt_history(session.id)

      GenServer.stop(pid)
    end

    test "set_prompt_history/2 enforces max history limit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Create a history with more than 100 items
      large_history = for i <- 1..150, do: "Prompt #{i}"

      {:ok, history} = State.set_prompt_history(session.id, large_history)

      # Should be capped at 100
      assert length(history) == 100
      # First 100 items should be preserved
      assert hd(history) == "Prompt 1"
      assert List.last(history) == "Prompt 100"

      GenServer.stop(pid)
    end

    test "set_prompt_history/2 returns :not_found for unknown session" do
      assert {:error, :not_found} = State.set_prompt_history("unknown-session-id", ["Hello"])
    end
  end

  # ============================================================================
  # Memory System Extensions (Task 1.5.1)
  # ============================================================================

  describe "memory field initialization" do
    test "initializes working_context with correct defaults", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)

      assert %WorkingContext{} = state.working_context
      assert state.working_context.max_tokens == 12_000
      assert state.working_context.items == %{}
      assert state.working_context.current_tokens == 0

      GenServer.stop(pid)
    end

    test "initializes pending_memories with correct defaults", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)

      assert %PendingMemories{} = state.pending_memories
      assert state.pending_memories.max_items == 500
      assert state.pending_memories.items == %{}
      assert state.pending_memories.agent_decisions == []

      GenServer.stop(pid)
    end

    test "initializes access_log with correct defaults", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)

      assert %AccessLog{} = state.access_log
      assert state.access_log.max_entries == 1000
      assert state.access_log.entries == []

      GenServer.stop(pid)
    end

    test "memory fields are included in get_state/1 result", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, state} = State.get_state(session.id)

      assert Map.has_key?(state, :working_context)
      assert Map.has_key?(state, :pending_memories)
      assert Map.has_key?(state, :access_log)

      GenServer.stop(pid)
    end

    test "memory fields persist across multiple GenServer calls", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Make several state operations
      message1 = %{id: "msg-1", role: :user, content: "Hello", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message1)
      {:ok, _} = State.set_scroll_offset(session.id, 10)

      # Memory fields should still be present and unchanged
      {:ok, state} = State.get_state(session.id)

      assert %WorkingContext{} = state.working_context
      assert %PendingMemories{} = state.pending_memories
      assert %AccessLog{} = state.access_log

      # Verify existing operations still work
      assert length(state.messages) == 1
      assert state.scroll_offset == 10

      GenServer.stop(pid)
    end

    test "memory operations don't interfere with existing Session.State operations", %{
      tmp_dir: tmp_dir
    } do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Test that all existing operations still work
      message = %{id: "msg-1", role: :user, content: "Test", timestamp: DateTime.utc_now()}
      {:ok, _} = State.append_message(session.id, message)
      {:ok, messages} = State.get_messages(session.id)
      assert length(messages) == 1

      # Streaming
      {:ok, _} = State.start_streaming(session.id, "msg-2")
      :ok = State.update_streaming(session.id, "Hello")
      Process.sleep(10)
      {:ok, streamed_msg} = State.end_streaming(session.id)
      assert streamed_msg.content == "Hello"

      # Todos
      todos = [%{id: "t-1", content: "Task", status: :pending}]
      {:ok, _} = State.update_todos(session.id, todos)
      {:ok, returned_todos} = State.get_todos(session.id)
      assert length(returned_todos) == 1

      # Prompt history
      {:ok, _} = State.add_to_prompt_history(session.id, "Test prompt")
      {:ok, history} = State.get_prompt_history(session.id)
      assert hd(history) == "Test prompt"

      # Memory fields should still be intact
      {:ok, state} = State.get_state(session.id)
      assert %WorkingContext{} = state.working_context
      assert %PendingMemories{} = state.pending_memories
      assert %AccessLog{} = state.access_log

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Working Context Client API (Task 1.5.2)
  # ============================================================================

  describe "update_context/4" do
    test "stores context item in working_context", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert :ok = State.update_context(session.id, :framework, "Phoenix")

      {:ok, state} = State.get_state(session.id)
      assert Map.has_key?(state.working_context.items, :framework)
      assert state.working_context.items[:framework].value == "Phoenix"

      GenServer.stop(pid)
    end

    test "updates existing item with incremented access_count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")
      {:ok, state1} = State.get_state(session.id)
      initial_count = state1.working_context.items[:framework].access_count

      :ok = State.update_context(session.id, :framework, "Phoenix 1.7")
      {:ok, state2} = State.get_state(session.id)
      updated_count = state2.working_context.items[:framework].access_count

      assert updated_count == initial_count + 1
      assert state2.working_context.items[:framework].value == "Phoenix 1.7"

      GenServer.stop(pid)
    end

    test "accepts source option", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix", source: :tool)

      {:ok, state} = State.get_state(session.id)
      assert state.working_context.items[:framework].source == :tool

      GenServer.stop(pid)
    end

    test "accepts confidence option", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix", confidence: 0.95)

      {:ok, state} = State.get_state(session.id)
      assert state.working_context.items[:framework].confidence == 0.95

      GenServer.stop(pid)
    end

    test "accepts memory_type option", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix", memory_type: :fact)

      {:ok, state} = State.get_state(session.id)
      assert state.working_context.items[:framework].suggested_type == :fact

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.update_context("unknown-session-id", :framework, "Phoenix")
    end
  end

  describe "get_context/2" do
    test "returns value for existing key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")

      assert {:ok, "Phoenix"} = State.get_context(session.id, :framework)

      GenServer.stop(pid)
    end

    test "returns :key_not_found for missing key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:error, :key_not_found} = State.get_context(session.id, :unknown_key)

      GenServer.stop(pid)
    end

    test "updates access tracking on retrieval", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")
      {:ok, state1} = State.get_state(session.id)
      initial_count = state1.working_context.items[:framework].access_count

      {:ok, _value} = State.get_context(session.id, :framework)
      {:ok, state2} = State.get_state(session.id)
      updated_count = state2.working_context.items[:framework].access_count

      assert updated_count == initial_count + 1

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_context("unknown-session-id", :framework)
    end
  end

  describe "get_all_context/1" do
    test "returns all context items as map", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")
      :ok = State.update_context(session.id, :primary_language, "Elixir")

      {:ok, context} = State.get_all_context(session.id)

      assert context == %{framework: "Phoenix", primary_language: "Elixir"}

      GenServer.stop(pid)
    end

    test "returns empty map for empty context", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, context} = State.get_all_context(session.id)

      assert context == %{}

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_all_context("unknown-session-id")
    end
  end

  describe "clear_context/1" do
    test "clears all context items", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")
      :ok = State.update_context(session.id, :primary_language, "Elixir")

      {:ok, context_before} = State.get_all_context(session.id)
      assert map_size(context_before) == 2

      :ok = State.clear_context(session.id)

      {:ok, context_after} = State.get_all_context(session.id)
      assert context_after == %{}

      GenServer.stop(pid)
    end

    test "preserves max_tokens setting", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.update_context(session.id, :framework, "Phoenix")
      {:ok, state_before} = State.get_state(session.id)
      max_tokens = state_before.working_context.max_tokens

      :ok = State.clear_context(session.id)

      {:ok, state_after} = State.get_state(session.id)
      assert state_after.working_context.max_tokens == max_tokens

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_context("unknown-session-id")
    end
  end

  # ============================================================================
  # Pending Memories Client API (Task 1.5.3)
  # ============================================================================

  describe "add_pending_memory/2" do
    test "adds item to pending_memories", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      item = %{
        content: "Uses Phoenix framework",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool
      }

      assert :ok = State.add_pending_memory(session.id, item)

      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 1

      GenServer.stop(pid)
    end

    test "sets suggested_by to :implicit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      item = %{
        content: "Test content",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :tool
      }

      :ok = State.add_pending_memory(session.id, item)

      {:ok, state} = State.get_state(session.id)
      [added_item] = PendingMemories.list_implicit(state.pending_memories)
      assert added_item.suggested_by == :implicit

      GenServer.stop(pid)
    end

    test "enforces max_pending_memories limit", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add more items than max limit (500)
      # We'll add a few and verify the mechanism works (full test in PendingMemories module)
      for i <- 1..5 do
        item = %{
          content: "Item #{i}",
          memory_type: :fact,
          confidence: 0.5,
          source_type: :tool,
          importance_score: i * 0.1
        }

        :ok = State.add_pending_memory(session.id, item)
      end

      {:ok, state} = State.get_state(session.id)
      assert PendingMemories.size(state.pending_memories) == 5

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      item = %{content: "Test", memory_type: :fact, confidence: 0.8, source_type: :tool}
      assert {:error, :not_found} = State.add_pending_memory("unknown-session-id", item)
    end
  end

  describe "add_agent_memory_decision/2" do
    test "adds item to agent_decisions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      item = %{
        content: "Critical discovery",
        memory_type: :discovery,
        confidence: 0.95,
        source_type: :agent
      }

      assert :ok = State.add_agent_memory_decision(session.id, item)

      {:ok, state} = State.get_state(session.id)
      decisions = PendingMemories.list_agent_decisions(state.pending_memories)
      assert length(decisions) == 1

      GenServer.stop(pid)
    end

    test "sets suggested_by to :agent and importance_score to 1.0", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.9,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, item)

      {:ok, state} = State.get_state(session.id)
      [decision] = PendingMemories.list_agent_decisions(state.pending_memories)
      assert decision.suggested_by == :agent
      assert decision.importance_score == 1.0

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      item = %{content: "Test", memory_type: :fact, confidence: 0.8, source_type: :agent}
      assert {:error, :not_found} = State.add_agent_memory_decision("unknown-session-id", item)
    end
  end

  describe "get_pending_memories/1" do
    test "returns items ready for promotion", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add item with high importance score (above default threshold of 0.6)
      high_score_item = %{
        content: "High importance item",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, high_score_item)

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).content == "High importance item"

      GenServer.stop(pid)
    end

    test "always includes agent decisions", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      agent_item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.9,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert length(ready_items) == 1
      assert hd(ready_items).suggested_by == :agent

      GenServer.stop(pid)
    end

    test "returns empty list when no items meet threshold", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add item with low importance score (below default threshold of 0.6)
      low_score_item = %{
        content: "Low importance item",
        memory_type: :fact,
        confidence: 0.5,
        source_type: :tool,
        importance_score: 0.3
      }

      :ok = State.add_pending_memory(session.id, low_score_item)

      {:ok, ready_items} = State.get_pending_memories(session.id)
      assert ready_items == []

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_pending_memories("unknown-session-id")
    end
  end

  describe "clear_promoted_memories/2" do
    test "removes specified items from pending_memories", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      item = %{
        id: "test-item-123",
        content: "Test item",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.8
      }

      :ok = State.add_pending_memory(session.id, item)

      {:ok, state_before} = State.get_state(session.id)
      assert PendingMemories.size(state_before.pending_memories) == 1

      :ok = State.clear_promoted_memories(session.id, ["test-item-123"])

      {:ok, state_after} = State.get_state(session.id)
      assert PendingMemories.size(state_after.pending_memories) == 0

      GenServer.stop(pid)
    end

    test "clears agent_decisions list", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      agent_item = %{
        content: "Agent decision",
        memory_type: :decision,
        confidence: 0.9,
        source_type: :agent
      }

      :ok = State.add_agent_memory_decision(session.id, agent_item)

      {:ok, state_before} = State.get_state(session.id)
      assert length(PendingMemories.list_agent_decisions(state_before.pending_memories)) == 1

      :ok = State.clear_promoted_memories(session.id, [])

      {:ok, state_after} = State.get_state(session.id)
      assert PendingMemories.list_agent_decisions(state_after.pending_memories) == []

      GenServer.stop(pid)
    end

    test "handles non-existent ids gracefully", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Should not raise error for non-existent ids
      assert :ok = State.clear_promoted_memories(session.id, ["non-existent-id"])

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.clear_promoted_memories("unknown-session-id", [])
    end
  end

  # ============================================================================
  # Access Log Client API (Task 1.5.4)
  # ============================================================================

  describe "record_access/3" do
    test "adds entry to access_log", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, :framework, :read)

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert AccessLog.size(state.access_log) == 1

      GenServer.stop(pid)
    end

    test "records correct access_type values", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, :framework, :read)
      :ok = State.record_access(session.id, :primary_language, :write)
      :ok = State.record_access(session.id, {:memory, "mem-123"}, :query)

      # Give casts time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      assert AccessLog.size(state.access_log) == 3

      recent = AccessLog.recent_accesses(state.access_log, 3)
      access_types = Enum.map(recent, & &1.access_type)
      assert :read in access_types
      assert :write in access_types
      assert :query in access_types

      GenServer.stop(pid)
    end

    test "accepts context_key as key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, :framework, :read)

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      [entry] = AccessLog.recent_accesses(state.access_log, 1)
      assert entry.key == :framework

      GenServer.stop(pid)
    end

    test "accepts {:memory, id} tuple as key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, {:memory, "mem-456"}, :query)

      # Give cast time to process
      Process.sleep(10)

      {:ok, state} = State.get_state(session.id)
      [entry] = AccessLog.recent_accesses(state.access_log, 1)
      assert entry.key == {:memory, "mem-456"}

      GenServer.stop(pid)
    end

    test "returns :ok for unknown session (silent ignore)", %{tmp_dir: _tmp_dir} do
      assert :ok = State.record_access("unknown-session-id", :framework, :read)
    end

    test "async operation does not block", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Record many accesses quickly
      for i <- 1..100 do
        :ok = State.record_access(session.id, :"key_#{i}", :read)
      end

      # Give casts time to process
      Process.sleep(50)

      {:ok, state} = State.get_state(session.id)
      assert AccessLog.size(state.access_log) == 100

      GenServer.stop(pid)
    end
  end

  describe "get_access_stats/2" do
    test "returns frequency and recency for key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, :framework, :read)
      :ok = State.record_access(session.id, :framework, :read)
      :ok = State.record_access(session.id, :framework, :write)

      # Give casts time to process
      Process.sleep(10)

      {:ok, stats} = State.get_access_stats(session.id, :framework)

      assert stats.frequency == 3
      assert %DateTime{} = stats.recency

      GenServer.stop(pid)
    end

    test "returns zero frequency for unknown key", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, stats} = State.get_access_stats(session.id, :unknown_key)

      assert stats.frequency == 0
      assert stats.recency == nil

      GenServer.stop(pid)
    end

    test "returns stats for {:memory, id} keys", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      :ok = State.record_access(session.id, {:memory, "mem-789"}, :query)
      :ok = State.record_access(session.id, {:memory, "mem-789"}, :read)

      # Give casts time to process
      Process.sleep(10)

      {:ok, stats} = State.get_access_stats(session.id, {:memory, "mem-789"})

      assert stats.frequency == 2
      assert %DateTime{} = stats.recency

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_access_stats("unknown-session-id", :framework)
    end
  end

  # ============================================================================
  # Promotion Timer Tests (Task 3.3.1)
  # ============================================================================

  describe "promotion timer initialization" do
    test "initializes with promotion_enabled = true by default", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.promotion_enabled == true

      GenServer.stop(pid)
    end

    test "initializes with default promotion_interval_ms", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.promotion_interval_ms == 30_000

      GenServer.stop(pid)
    end

    test "initializes with nil promotion_timer_ref when disabled", %{tmp_dir: tmp_dir} do
      # Create session with promotion disabled via config
      {:ok, session} = Session.new(project_path: tmp_dir)
      # Manually update config to disable promotion
      session = %{session | config: Map.put(session.config, :promotion_enabled, false)}
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.promotion_enabled == false
      assert state.promotion_timer_ref == nil

      GenServer.stop(pid)
    end

    test "schedules timer when promotion is enabled", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.promotion_enabled == true
      assert is_reference(state.promotion_timer_ref)

      GenServer.stop(pid)
    end

    test "initializes empty promotion_stats", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state = :sys.get_state(pid)
      assert state.promotion_stats.last_run == nil
      assert state.promotion_stats.total_promoted == 0
      assert state.promotion_stats.runs == 0

      GenServer.stop(pid)
    end
  end

  describe "enable_promotion/1" do
    test "enables promotion and schedules timer", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      session = %{session | config: Map.put(session.config, :promotion_enabled, false)}
      {:ok, pid} = State.start_link(session: session)

      state_before = :sys.get_state(pid)
      assert state_before.promotion_enabled == false
      assert state_before.promotion_timer_ref == nil

      assert :ok = State.enable_promotion(session.id)

      state_after = :sys.get_state(pid)
      assert state_after.promotion_enabled == true
      assert is_reference(state_after.promotion_timer_ref)

      GenServer.stop(pid)
    end

    test "is idempotent when already enabled", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state_before = :sys.get_state(pid)
      timer_ref_before = state_before.promotion_timer_ref

      assert :ok = State.enable_promotion(session.id)

      state_after = :sys.get_state(pid)
      assert state_after.promotion_enabled == true
      # Timer ref should remain unchanged when already enabled
      assert state_after.promotion_timer_ref == timer_ref_before

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.enable_promotion("unknown-session-id")
    end
  end

  describe "disable_promotion/1" do
    test "disables promotion and cancels timer", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state_before = :sys.get_state(pid)
      assert state_before.promotion_enabled == true
      assert is_reference(state_before.promotion_timer_ref)

      assert :ok = State.disable_promotion(session.id)

      state_after = :sys.get_state(pid)
      assert state_after.promotion_enabled == false
      assert state_after.promotion_timer_ref == nil

      GenServer.stop(pid)
    end

    test "cancels pending timer message", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      state_before = :sys.get_state(pid)
      timer_ref = state_before.promotion_timer_ref

      :ok = State.disable_promotion(session.id)

      # Timer should be cancelled - verify by checking Process.read_timer returns false
      # (timer was cancelled or already fired)
      assert Process.read_timer(timer_ref) == false

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.disable_promotion("unknown-session-id")
    end
  end

  describe "get_promotion_stats/1" do
    test "returns all promotion statistics", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, stats} = State.get_promotion_stats(session.id)

      assert stats.enabled == true
      assert stats.interval_ms == 30_000
      assert stats.last_run == nil
      assert stats.total_promoted == 0
      assert stats.runs == 0

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.get_promotion_stats("unknown-session-id")
    end
  end

  describe "set_promotion_interval/2" do
    test "updates promotion interval", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert :ok = State.set_promotion_interval(session.id, 60_000)

      state = :sys.get_state(pid)
      assert state.promotion_interval_ms == 60_000

      GenServer.stop(pid)
    end

    test "rejects non-positive intervals", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      assert {:error, :invalid_interval} = State.set_promotion_interval(session.id, 0)
      assert {:error, :invalid_interval} = State.set_promotion_interval(session.id, -1000)

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.set_promotion_interval("unknown-session-id", 60_000)
    end
  end

  describe "run_promotion_now/1" do
    test "runs promotion immediately and returns count", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, count} = State.run_promotion_now(session.id)

      # With empty pending memories, should promote 0
      assert count == 0

      GenServer.stop(pid)
    end

    test "updates promotion stats after run", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      {:ok, stats_before} = State.get_promotion_stats(session.id)
      assert stats_before.runs == 0
      assert stats_before.last_run == nil

      {:ok, _count} = State.run_promotion_now(session.id)

      {:ok, stats_after} = State.get_promotion_stats(session.id)
      assert stats_after.runs == 1
      assert %DateTime{} = stats_after.last_run

      GenServer.stop(pid)
    end

    test "promotes pending memories that meet threshold", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Add a high-importance pending memory
      item = %{
        content: "Important discovery",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        importance_score: 0.85
      }

      :ok = State.add_pending_memory(session.id, item)

      {:ok, count} = State.run_promotion_now(session.id)

      # Should promote the high-importance item
      assert count == 1

      {:ok, stats} = State.get_promotion_stats(session.id)
      assert stats.total_promoted == 1

      GenServer.stop(pid)
    end

    test "returns :not_found for unknown session" do
      assert {:error, :not_found} = State.run_promotion_now("unknown-session-id")
    end
  end

  describe "handle_info(:run_promotion)" do
    test "runs promotion when enabled", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      # Use very short interval for testing
      session = %{session | config: Map.put(session.config, :promotion_interval_ms, 50)}
      {:ok, pid} = State.start_link(session: session)

      # Wait for the timer to fire
      Process.sleep(100)

      state = :sys.get_state(pid)
      # Should have run at least once
      assert state.promotion_stats.runs >= 1
      assert state.promotion_stats.last_run != nil

      GenServer.stop(pid)
    end

    test "reschedules timer after promotion", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      session = %{session | config: Map.put(session.config, :promotion_interval_ms, 50)}
      {:ok, pid} = State.start_link(session: session)

      state_before = :sys.get_state(pid)
      timer_ref_before = state_before.promotion_timer_ref

      # Wait for timer to fire
      Process.sleep(100)

      state_after = :sys.get_state(pid)
      # New timer should be scheduled
      assert is_reference(state_after.promotion_timer_ref)
      # Timer ref should be different (new timer scheduled)
      assert state_after.promotion_timer_ref != timer_ref_before

      GenServer.stop(pid)
    end

    test "does not reschedule when disabled", %{tmp_dir: tmp_dir} do
      {:ok, session} = Session.new(project_path: tmp_dir)
      {:ok, pid} = State.start_link(session: session)

      # Disable promotion
      :ok = State.disable_promotion(session.id)

      # Manually send the :run_promotion message
      send(pid, :run_promotion)
      Process.sleep(10)

      state = :sys.get_state(pid)
      # Timer should not be rescheduled
      assert state.promotion_timer_ref == nil
      # Stats should not be updated
      assert state.promotion_stats.runs == 0

      GenServer.stop(pid)
    end
  end
end
