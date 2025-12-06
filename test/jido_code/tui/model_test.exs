defmodule JidoCode.TUI.ModelTest do
  @moduledoc """
  Unit tests for the TUI Model struct.

  Tests verify that the Model struct:
  1. Has session tracking fields for multi-session support
  2. Has correct default values
  3. Types compile correctly
  """
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Model

  describe "Model struct" do
    test "has session tracking fields" do
      model = %Model{}

      assert Map.has_key?(model, :sessions)
      assert Map.has_key?(model, :session_order)
      assert Map.has_key?(model, :active_session_id)
    end

    test "sessions field defaults to empty map" do
      model = %Model{}
      assert model.sessions == %{}
    end

    test "session_order field defaults to empty list" do
      model = %Model{}
      assert model.session_order == []
    end

    test "active_session_id field defaults to nil" do
      model = %Model{}
      assert model.active_session_id == nil
    end

    test "focus field defaults to :input" do
      model = %Model{}
      assert model.focus == :input
    end

    test "focus field accepts valid focus states" do
      # :input is default
      model = %Model{focus: :input}
      assert model.focus == :input

      # :conversation for scrolling
      model = %Model{focus: :conversation}
      assert model.focus == :conversation

      # :tabs for tab navigation
      model = %Model{focus: :tabs}
      assert model.focus == :tabs
    end
  end

  describe "Model struct defaults" do
    test "has correct UI state defaults" do
      model = %Model{}

      assert model.text_input == nil
      assert model.window == {80, 24}
      assert model.show_reasoning == false
      assert model.show_tool_details == false
      assert model.agent_status == :unconfigured
      assert model.config == %{provider: nil, model: nil}
    end

    test "has correct modal defaults" do
      model = %Model{}

      assert model.shell_dialog == nil
      assert model.shell_viewport == nil
      assert model.pick_list == nil
    end

    test "has correct legacy per-session field defaults" do
      model = %Model{}

      assert model.messages == []
      assert model.reasoning_steps == []
      assert model.tool_calls == []
      assert model.message_queue == []
      assert model.scroll_offset == 0
      assert model.agent_name == :llm_agent
      assert model.streaming_message == nil
      assert model.is_streaming == false
      assert model.session_topic == nil
      assert model.conversation_view == nil
    end
  end

  describe "Model struct with sessions" do
    test "can store sessions in sessions map" do
      # Create a mock session (simplified for testing)
      mock_session = %{id: "session-1", name: "project-a", project_path: "/tmp/project-a"}

      model = %Model{
        sessions: %{"session-1" => mock_session},
        session_order: ["session-1"],
        active_session_id: "session-1"
      }

      assert model.sessions["session-1"] == mock_session
      assert model.session_order == ["session-1"]
      assert model.active_session_id == "session-1"
    end

    test "can store multiple sessions in order" do
      mock_session_1 = %{id: "session-1", name: "project-a"}
      mock_session_2 = %{id: "session-2", name: "project-b"}
      mock_session_3 = %{id: "session-3", name: "project-c"}

      model = %Model{
        sessions: %{
          "session-1" => mock_session_1,
          "session-2" => mock_session_2,
          "session-3" => mock_session_3
        },
        session_order: ["session-1", "session-2", "session-3"],
        active_session_id: "session-2"
      }

      assert map_size(model.sessions) == 3
      assert length(model.session_order) == 3
      assert model.active_session_id == "session-2"

      # Verify order is preserved
      assert Enum.at(model.session_order, 0) == "session-1"
      assert Enum.at(model.session_order, 1) == "session-2"
      assert Enum.at(model.session_order, 2) == "session-3"
    end
  end

  describe "Model struct update" do
    test "can update session tracking fields" do
      model = %Model{}

      # Add a session
      mock_session = %{id: "new-session", name: "new-project"}

      updated = %{
        model
        | sessions: Map.put(model.sessions, "new-session", mock_session),
          session_order: model.session_order ++ ["new-session"],
          active_session_id: "new-session"
      }

      assert updated.sessions["new-session"] == mock_session
      assert "new-session" in updated.session_order
      assert updated.active_session_id == "new-session"
    end

    test "can update focus state" do
      model = %Model{focus: :input}

      # Switch to conversation focus
      updated = %{model | focus: :conversation}
      assert updated.focus == :conversation

      # Switch to tabs focus
      updated = %{model | focus: :tabs}
      assert updated.focus == :tabs
    end
  end

  # ===========================================================================
  # Session Access Helper Tests
  # ===========================================================================

  describe "get_active_session/1" do
    test "returns nil when no active session" do
      model = %Model{active_session_id: nil}
      assert Model.get_active_session(model) == nil
    end

    test "returns nil when active_session_id not in sessions map" do
      model = %Model{
        active_session_id: "missing-session",
        sessions: %{}
      }

      assert Model.get_active_session(model) == nil
    end

    test "returns the active session when it exists" do
      mock_session = %{id: "session-1", name: "project-a", project_path: "/tmp/a"}

      model = %Model{
        active_session_id: "session-1",
        sessions: %{"session-1" => mock_session}
      }

      assert Model.get_active_session(model) == mock_session
    end

    test "returns correct session from multiple sessions" do
      session_1 = %{id: "s1", name: "project-a"}
      session_2 = %{id: "s2", name: "project-b"}
      session_3 = %{id: "s3", name: "project-c"}

      model = %Model{
        active_session_id: "s2",
        sessions: %{
          "s1" => session_1,
          "s2" => session_2,
          "s3" => session_3
        }
      }

      assert Model.get_active_session(model) == session_2
    end
  end

  describe "get_session_by_index/2" do
    test "returns nil when no sessions exist" do
      model = %Model{session_order: [], sessions: %{}}
      assert Model.get_session_by_index(model, 1) == nil
    end

    test "returns first session for index 1" do
      session_1 = %{id: "s1", name: "project-a"}
      session_2 = %{id: "s2", name: "project-b"}

      model = %Model{
        session_order: ["s1", "s2"],
        sessions: %{"s1" => session_1, "s2" => session_2}
      }

      assert Model.get_session_by_index(model, 1) == session_1
    end

    test "returns second session for index 2" do
      session_1 = %{id: "s1", name: "project-a"}
      session_2 = %{id: "s2", name: "project-b"}

      model = %Model{
        session_order: ["s1", "s2"],
        sessions: %{"s1" => session_1, "s2" => session_2}
      }

      assert Model.get_session_by_index(model, 2) == session_2
    end

    test "returns nil for out-of-range index" do
      session_1 = %{id: "s1", name: "project-a"}

      model = %Model{
        session_order: ["s1"],
        sessions: %{"s1" => session_1}
      }

      # Only 1 session, index 2 should return nil
      assert Model.get_session_by_index(model, 2) == nil
      assert Model.get_session_by_index(model, 10) == nil
    end

    test "returns 10th session for index 10 (Ctrl+0)" do
      # Create 10 sessions
      sessions =
        for i <- 1..10, into: %{} do
          {"s#{i}", %{id: "s#{i}", name: "project-#{i}"}}
        end

      session_order = for i <- 1..10, do: "s#{i}"

      model = %Model{
        session_order: session_order,
        sessions: sessions
      }

      # Index 10 should return the 10th session (s10)
      result = Model.get_session_by_index(model, 10)
      assert result.id == "s10"
    end

    test "returns nil for index 0" do
      session_1 = %{id: "s1", name: "project-a"}

      model = %Model{
        session_order: ["s1"],
        sessions: %{"s1" => session_1}
      }

      assert Model.get_session_by_index(model, 0) == nil
    end

    test "returns nil for negative index" do
      session_1 = %{id: "s1", name: "project-a"}

      model = %Model{
        session_order: ["s1"],
        sessions: %{"s1" => session_1}
      }

      assert Model.get_session_by_index(model, -1) == nil
    end

    test "returns nil for index > 10" do
      session_1 = %{id: "s1", name: "project-a"}

      model = %Model{
        session_order: ["s1"],
        sessions: %{"s1" => session_1}
      }

      assert Model.get_session_by_index(model, 11) == nil
    end
  end

  describe "get_active_session_state/1" do
    test "returns nil when no active session" do
      model = %Model{active_session_id: nil}
      assert Model.get_active_session_state(model) == nil
    end

    # Note: Testing get_active_session_state with a real Session.State process
    # requires integration tests with the full session infrastructure.
    # These unit tests verify the nil case; integration tests cover the full flow.
  end
end
