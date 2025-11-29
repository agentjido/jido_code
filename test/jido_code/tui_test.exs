defmodule JidoCode.TUITest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias TermUI.Command
  alias TermUI.Event

  describe "Model struct" do
    test "creates with default values" do
      model = %Model{}

      assert model.input_buffer == ""
      assert model.messages == []
      assert model.agent_status == :unconfigured
      assert model.config == %{provider: nil, model: nil}
      assert model.reasoning_steps == []
      assert model.window == {80, 24}
    end

    test "supports all required fields" do
      model = %Model{
        input_buffer: "test input",
        messages: [%{role: :user, content: "hello", timestamp: DateTime.utc_now()}],
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        reasoning_steps: [%{step: "analyzing", status: :active}],
        window: {120, 40}
      }

      assert model.input_buffer == "test input"
      assert length(model.messages) == 1
      assert model.agent_status == :idle
      assert model.config.provider == "anthropic"
      assert model.config.model == "claude-3-5-sonnet"
      assert length(model.reasoning_steps) == 1
      assert model.window == {120, 40}
    end
  end

  describe "determine_status/1" do
    test "returns :unconfigured when provider is nil" do
      config = %{provider: nil, model: "claude-3-5-sonnet"}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when model is nil" do
      config = %{provider: "anthropic", model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when both are nil" do
      config = %{provider: nil, model: nil}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :idle when both provider and model are set" do
      config = %{provider: "anthropic", model: "claude-3-5-sonnet"}
      assert TUI.determine_status(config) == :idle
    end
  end

  describe "event_to_msg/2" do
    test "returns :ignore for unknown events" do
      state = %Model{}
      assert TUI.event_to_msg(:unknown_event, state) == :ignore
    end

    test "maps Enter key to :submit message" do
      state = %Model{}
      event = Event.key(:enter)
      assert TUI.event_to_msg(event, state) == {:msg, :submit}
    end

    test "maps Backspace to {:key_input, :backspace} message" do
      state = %Model{}
      event = Event.key(:backspace)
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, :backspace}}
    end

    test "maps Ctrl+C to :quit message" do
      state = %Model{}
      event = Event.key(:c, modifiers: [:ctrl])
      assert TUI.event_to_msg(event, state) == {:msg, :quit}
    end

    test "maps 'c' without Ctrl to {:key_input, \"c\"}" do
      state = %Model{}
      event = Event.key(:c, char: "c")
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, "c"}}
    end

    test "maps printable characters to {:key_input, char} message" do
      state = %Model{}

      # Test letter
      event = Event.key(:a, char: "a")
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, "a"}}

      # Test number
      event = Event.key(:"1", char: "1")
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, "1"}}

      # Test space
      event = Event.key(:space, char: " ")
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, " "}}
    end

    test "maps Resize event to {:resize, width, height} message" do
      state = %Model{}
      event = Event.resize(120, 40)
      assert TUI.event_to_msg(event, state) == {:msg, {:resize, 120, 40}}
    end

    test "returns :ignore for non-printable key events" do
      state = %Model{}
      # Arrow keys have no char
      event = %Event.Key{key: :up, char: nil, modifiers: []}
      assert TUI.event_to_msg(event, state) == :ignore
    end
  end

  describe "update/2" do
    test "returns state unchanged for unknown messages" do
      state = %Model{input_buffer: "test"}
      {new_state, commands} = TUI.update(:unknown_message, state)

      assert new_state == state
      assert commands == []
    end

    test ":submit adds user message to history and clears buffer" do
      state = %Model{input_buffer: "Hello world", messages: []}
      {new_state, commands} = TUI.update(:submit, state)

      assert new_state.input_buffer == ""
      assert length(new_state.messages) == 1

      [message] = new_state.messages
      assert message.role == :user
      assert message.content == "Hello world"
      assert %DateTime{} = message.timestamp

      assert commands == []
    end

    test ":submit with empty buffer does nothing" do
      state = %Model{input_buffer: "", messages: []}
      {new_state, commands} = TUI.update(:submit, state)

      assert new_state == state
      assert commands == []
    end

    test "{:key_input, char} appends character to buffer" do
      state = %Model{input_buffer: "hel"}
      {new_state, commands} = TUI.update({:key_input, "l"}, state)

      assert new_state.input_buffer == "hell"
      assert commands == []
    end

    test "{:key_input, char} works with empty buffer" do
      state = %Model{input_buffer: ""}
      {new_state, commands} = TUI.update({:key_input, "a"}, state)

      assert new_state.input_buffer == "a"
      assert commands == []
    end

    test "{:key_input, :backspace} removes last character" do
      state = %Model{input_buffer: "hello"}
      {new_state, commands} = TUI.update({:key_input, :backspace}, state)

      assert new_state.input_buffer == "hell"
      assert commands == []
    end

    test "{:key_input, :backspace} with empty buffer does nothing" do
      state = %Model{input_buffer: ""}
      {new_state, commands} = TUI.update({:key_input, :backspace}, state)

      assert new_state.input_buffer == ""
      assert commands == []
    end

    test ":quit returns Command.quit()" do
      state = %Model{}
      {new_state, commands} = TUI.update(:quit, state)

      assert new_state == state
      assert length(commands) == 1
      [quit_cmd] = commands
      assert %Command{type: :quit, payload: :user_requested} = quit_cmd
    end

    test "{:resize, width, height} updates window dimensions" do
      state = %Model{window: {80, 24}}
      {new_state, commands} = TUI.update({:resize, 120, 40}, state)

      assert new_state.window == {120, 40}
      assert commands == []
    end
  end

  describe "view/1" do
    alias TermUI.Component.RenderNode

    test "returns a render tree" do
      state = %Model{}
      view = TUI.view(state)

      # View should return a RenderNode with type :stack
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view
      assert is_list(children)
      assert length(children) > 0
    end

    test "includes status bar in view" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle
      }

      %RenderNode{children: children} = TUI.view(state)

      # First child should be status bar (text with style)
      [status_bar | _rest] = children
      assert %RenderNode{type: :text, content: content, style: style} = status_bar
      assert content =~ "anthropic"
      assert style.bg == :blue
    end
  end
end
