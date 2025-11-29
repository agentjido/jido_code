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
      assert model.scroll_offset == 0
      assert model.show_reasoning == false
    end

    test "supports all required fields" do
      model = %Model{
        input_buffer: "test input",
        messages: [%{role: :user, content: "hello", timestamp: DateTime.utc_now()}],
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        reasoning_steps: [%{step: "analyzing", status: :active}],
        window: {120, 40},
        scroll_offset: 5,
        show_reasoning: true
      }

      assert model.input_buffer == "test input"
      assert length(model.messages) == 1
      assert model.agent_status == :idle
      assert model.config.provider == "anthropic"
      assert model.config.model == "claude-3-5-sonnet"
      assert length(model.reasoning_steps) == 1
      assert model.window == {120, 40}
      assert model.scroll_offset == 5
      assert model.show_reasoning == true
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
      # F1 key has no char and is not handled
      event = %Event.Key{key: :f1, char: nil, modifiers: []}
      assert TUI.event_to_msg(event, state) == :ignore
    end

    test "maps Up arrow to :scroll_up message" do
      state = %Model{}
      event = Event.key(:up)
      assert TUI.event_to_msg(event, state) == {:msg, :scroll_up}
    end

    test "maps Down arrow to :scroll_down message" do
      state = %Model{}
      event = Event.key(:down)
      assert TUI.event_to_msg(event, state) == {:msg, :scroll_down}
    end

    test "maps Ctrl+R to :toggle_reasoning message" do
      state = %Model{}
      event = Event.key(:r, modifiers: [:ctrl])
      assert TUI.event_to_msg(event, state) == {:msg, :toggle_reasoning}
    end

    test "maps 'r' without Ctrl to {:key_input, \"r\"}" do
      state = %Model{}
      event = Event.key(:r, char: "r")
      assert TUI.event_to_msg(event, state) == {:msg, {:key_input, "r"}}
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

    test ":scroll_up increases scroll_offset" do
      state = %Model{
        messages: [
          %{role: :user, content: "msg1", timestamp: DateTime.utc_now()},
          %{role: :assistant, content: "msg2", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 0
      }
      {new_state, commands} = TUI.update(:scroll_up, state)

      assert new_state.scroll_offset == 1
      assert commands == []
    end

    test ":scroll_up caps at max offset" do
      state = %Model{
        messages: [
          %{role: :user, content: "msg1", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 0
      }
      # Max offset is length - 1 = 0, so scrolling up shouldn't increase beyond 0
      {new_state, _} = TUI.update(:scroll_up, state)
      assert new_state.scroll_offset == 0
    end

    test ":scroll_down decreases scroll_offset" do
      state = %Model{
        messages: [
          %{role: :user, content: "msg1", timestamp: DateTime.utc_now()},
          %{role: :assistant, content: "msg2", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 1
      }
      {new_state, commands} = TUI.update(:scroll_down, state)

      assert new_state.scroll_offset == 0
      assert commands == []
    end

    test ":scroll_down doesn't go below 0" do
      state = %Model{
        messages: [
          %{role: :user, content: "msg1", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 0
      }
      {new_state, _} = TUI.update(:scroll_down, state)
      assert new_state.scroll_offset == 0
    end

    test ":submit resets scroll_offset to 0" do
      state = %Model{
        input_buffer: "hello",
        messages: [
          %{role: :user, content: "old", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 1
      }
      {new_state, _} = TUI.update(:submit, state)
      assert new_state.scroll_offset == 0
    end

    test ":toggle_reasoning toggles show_reasoning from false to true" do
      state = %Model{show_reasoning: false}
      {new_state, commands} = TUI.update(:toggle_reasoning, state)

      assert new_state.show_reasoning == true
      assert commands == []
    end

    test ":toggle_reasoning toggles show_reasoning from true to false" do
      state = %Model{show_reasoning: true}
      {new_state, commands} = TUI.update(:toggle_reasoning, state)

      assert new_state.show_reasoning == false
      assert commands == []
    end
  end

  describe "update/2 PubSub messages" do
    test "{:agent_response, content} adds assistant message to history" do
      state = %Model{messages: [], agent_status: :processing}
      {new_state, commands} = TUI.update({:agent_response, "Hello from assistant!"}, state)

      assert length(new_state.messages) == 1
      [message] = new_state.messages
      assert message.role == :assistant
      assert message.content == "Hello from assistant!"
      assert %DateTime{} = message.timestamp
      assert new_state.agent_status == :idle
      assert commands == []
    end

    test "{:agent_response, content} appends to existing messages" do
      existing_msg = %{role: :user, content: "Hi", timestamp: DateTime.utc_now()}
      state = %Model{messages: [existing_msg], agent_status: :processing}
      {new_state, commands} = TUI.update({:agent_response, "Hello!"}, state)

      assert length(new_state.messages) == 2
      assert Enum.at(new_state.messages, 0).role == :user
      assert Enum.at(new_state.messages, 1).role == :assistant
      assert commands == []
    end

    test "{:agent_response, content} resets scroll_offset to 0" do
      state = %Model{
        messages: [%{role: :user, content: "Hi", timestamp: DateTime.utc_now()}],
        agent_status: :processing,
        scroll_offset: 1
      }
      {new_state, _} = TUI.update({:agent_response, "Hello!"}, state)
      assert new_state.scroll_offset == 0
    end

    test "{:agent_status, status} updates agent status" do
      state = %Model{agent_status: :idle}

      {new_state, _} = TUI.update({:agent_status, :processing}, state)
      assert new_state.agent_status == :processing

      {new_state, _} = TUI.update({:agent_status, :error}, new_state)
      assert new_state.agent_status == :error

      {new_state, _} = TUI.update({:agent_status, :idle}, new_state)
      assert new_state.agent_status == :idle
    end

    test "{:reasoning_step, step} adds new reasoning step" do
      state = %Model{reasoning_steps: []}
      step = %{step: "Analyzing query", status: :active}
      {new_state, commands} = TUI.update({:reasoning_step, step}, state)

      assert length(new_state.reasoning_steps) == 1
      [added_step] = new_state.reasoning_steps
      assert added_step.step == "Analyzing query"
      assert added_step.status == :active
      assert commands == []
    end

    test "{:reasoning_step, step} updates existing step status" do
      existing_step = %{step: "Analyzing query", status: :pending}
      state = %Model{reasoning_steps: [existing_step]}
      update = %{step: "Analyzing query", status: :complete}
      {new_state, commands} = TUI.update({:reasoning_step, update}, state)

      assert length(new_state.reasoning_steps) == 1
      [updated_step] = new_state.reasoning_steps
      assert updated_step.step == "Analyzing query"
      assert updated_step.status == :complete
      assert commands == []
    end

    test "{:reasoning_step, string} adds step as pending" do
      state = %Model{reasoning_steps: []}
      {new_state, commands} = TUI.update({:reasoning_step, "Thinking..."}, state)

      assert length(new_state.reasoning_steps) == 1
      [step] = new_state.reasoning_steps
      assert step.step == "Thinking..."
      assert step.status == :pending
      assert commands == []
    end

    test "{:config_changed, config} updates config with atom keys" do
      state = %Model{
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      new_config = %{provider: "anthropic", model: "claude-3-5-sonnet"}
      {new_state, commands} = TUI.update({:config_changed, new_config}, state)

      assert new_state.config.provider == "anthropic"
      assert new_state.config.model == "claude-3-5-sonnet"
      assert new_state.agent_status == :idle
      assert commands == []
    end

    test "{:config_changed, config} updates config with string keys" do
      state = %Model{
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      new_config = %{"provider" => "openai", "model" => "gpt-4"}
      {new_state, commands} = TUI.update({:config_changed, new_config}, state)

      assert new_state.config.provider == "openai"
      assert new_state.config.model == "gpt-4"
      assert new_state.agent_status == :idle
      assert commands == []
    end

    test "{:config_changed, config} sets unconfigured when provider nil" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle
      }

      new_config = %{provider: nil, model: "some-model"}
      {new_state, _} = TUI.update({:config_changed, new_config}, state)

      assert new_state.agent_status == :unconfigured
    end
  end

  describe "view/1" do
    alias TermUI.Component.RenderNode

    test "returns a three-pane vertical layout" do
      state = %Model{}
      view = TUI.view(state)

      # View should return a RenderNode with type :stack (vertical)
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view
      assert is_list(children)
      # Three panes: status bar, conversation, input bar
      assert length(children) == 3
    end

    test "first pane is status bar with segments" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      # Status bar is now a horizontal stack of segments
      assert %RenderNode{type: :stack, direction: :horizontal, children: segments} = status_bar
      texts = extract_texts(segments)
      combined = Enum.join(texts, "")

      assert combined =~ "anthropic:claude-3-5-sonnet"
      assert combined =~ "Idle"
      assert combined =~ "Ctrl+C: Quit"

      # Check config segment has blue background
      config_segment = Enum.at(segments, 0)
      assert config_segment.style.bg == :blue
    end

    test "status bar shows 'No provider configured' with red warning" do
      state = %Model{
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar
      texts = extract_texts(segments)
      combined = Enum.join(texts, "")

      assert combined =~ "No provider configured"
      assert combined =~ "Not Configured"

      # Config segment should be red for warning
      config_segment = Enum.at(segments, 0)
      assert config_segment.style.fg == :red
    end

    test "status bar shows processing status with yellow indicator" do
      state = %Model{
        config: %{provider: "openai", model: "gpt-4"},
        agent_status: :processing
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar
      texts = extract_texts(segments)
      combined = Enum.join(texts, "")

      assert combined =~ "Processing"

      # Find status segment and check it's yellow
      status_segment = Enum.find(segments, fn s ->
        s.type == :text and s.content != nil and s.content =~ "Processing"
      end)
      assert status_segment.style.fg == :yellow
    end

    test "status bar shows CoT indicator when reasoning steps are active" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :processing,
        reasoning_steps: [
          %{step: "Analyzing", status: :complete},
          %{step: "Planning", status: :active},
          %{step: "Executing", status: :pending}
        ]
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar
      texts = extract_texts(segments)
      combined = Enum.join(texts, "")

      assert combined =~ "CoT: 1/3"

      # CoT segment should be magenta
      cot_segment = Enum.find(segments, fn s ->
        s.type == :text and s.content != nil and s.content =~ "CoT:"
      end)
      assert cot_segment.style.fg == :magenta
    end

    test "status bar shows idle status with green indicator" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :idle
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar

      # Find idle status segment
      status_segment = Enum.find(segments, fn s ->
        s.type == :text and s.content != nil and s.content =~ "Idle"
      end)
      assert status_segment.style.fg == :green
      assert status_segment.content =~ "●"  # Filled indicator
    end

    test "status bar shows error status with red indicator" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :error
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar

      # Find error status segment
      status_segment = Enum.find(segments, fn s ->
        s.type == :text and s.content != nil and s.content =~ "Error"
      end)
      assert status_segment.style.fg == :red
    end

    test "status bar shows unconfigured status with dim indicator" do
      state = %Model{
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar

      # Find unconfigured status segment
      status_segment = Enum.find(segments, fn s ->
        s.type == :text and s.content != nil and s.content =~ "Not Configured"
      end)
      assert status_segment.style.fg == :bright_black  # Dim
      assert status_segment.content =~ "○"  # Empty indicator
    end

    test "status bar shows 'no model' with yellow warning" do
      state = %Model{
        config: %{provider: "anthropic", model: nil},
        agent_status: :unconfigured
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar

      # First segment is config
      config_segment = Enum.at(segments, 0)
      assert config_segment.content =~ "no model"
      assert config_segment.style.fg == :yellow
    end

    test "status bar includes keyboard hints with Ctrl+M and Ctrl+R" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :idle
      }

      %RenderNode{children: [status_bar | _rest]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: segments} = status_bar
      texts = extract_texts(segments)
      combined = Enum.join(texts, "")

      assert combined =~ "Ctrl+M: Model"
      assert combined =~ "Ctrl+R: Reasoning"
      assert combined =~ "Ctrl+C: Quit"
    end

    test "second pane is conversation area" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle,
        messages: []
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      # Conversation should be a stack
      assert %RenderNode{type: :stack, direction: :vertical} = conversation
    end

    test "conversation shows welcome message when empty and configured" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle,
        messages: []
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      # Check for welcome text in conversation
      assert %RenderNode{type: :stack, children: children} = conversation
      texts = extract_texts(children)
      assert Enum.any?(texts, &(&1 =~ "JidoCode"))
      assert Enum.any?(texts, &(&1 =~ "Ready"))
    end

    test "conversation shows configuration message when unconfigured" do
      state = %Model{
        config: %{provider: nil, model: nil},
        agent_status: :unconfigured,
        messages: []
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: children} = conversation
      texts = extract_texts(children)
      assert Enum.any?(texts, &(&1 =~ "Configuration Required"))
    end

    test "conversation displays user messages with cyan styling" do
      timestamp = DateTime.utc_now()
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle,
        messages: [
          %{role: :user, content: "Hello, assistant!", timestamp: timestamp}
        ]
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      # Find the message in the conversation
      assert %RenderNode{type: :stack, children: children} = conversation
      user_message = find_message_with_content(children, "Hello, assistant!")
      assert user_message != nil
      assert user_message.style.fg == :cyan
    end

    test "conversation displays assistant messages with white styling" do
      timestamp = DateTime.utc_now()
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle,
        messages: [
          %{role: :assistant, content: "Hello, human!", timestamp: timestamp}
        ]
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: children} = conversation
      assistant_message = find_message_with_content(children, "Hello, human!")
      assert assistant_message != nil
      assert assistant_message.style.fg == :white
    end

    test "messages include timestamps" do
      timestamp = ~U[2024-01-15 14:30:00Z]
      state = %Model{
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        agent_status: :idle,
        messages: [
          %{role: :user, content: "Test message", timestamp: timestamp}
        ]
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      assert %RenderNode{type: :stack, children: children} = conversation
      texts = extract_texts(children)
      # Should show HH:MM format
      assert Enum.any?(texts, &(&1 =~ "[14:30]"))
    end

    test "third pane is input bar with green prompt" do
      state = %Model{
        input_buffer: "test input"
      }

      %RenderNode{children: [_status, _conversation, input_bar]} = TUI.view(state)

      # Input bar should be horizontal stack with prompt and buffer
      assert %RenderNode{type: :stack, direction: :horizontal, children: [prompt, buffer]} = input_bar

      # Check prompt styling
      assert %RenderNode{type: :text, content: "> ", style: style} = prompt
      assert style.fg == :green
      assert :bold in MapSet.to_list(style.attrs)

      # Check buffer content
      assert %RenderNode{type: :text, content: "test input"} = buffer
    end

    test "input bar shows empty buffer" do
      state = %Model{
        input_buffer: ""
      }

      %RenderNode{children: [_status, _conversation, input_bar]} = TUI.view(state)

      assert %RenderNode{type: :stack, direction: :horizontal, children: [_prompt, buffer]} = input_bar
      assert %RenderNode{type: :text, content: ""} = buffer
    end

    test "conversation shows scroll indicator when scrolled up" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :idle,
        messages: [
          %{role: :user, content: "msg1", timestamp: DateTime.utc_now()},
          %{role: :assistant, content: "msg2", timestamp: DateTime.utc_now()},
          %{role: :user, content: "msg3", timestamp: DateTime.utc_now()}
        ],
        scroll_offset: 1
      }

      %RenderNode{children: [_status, conversation, _input]} = TUI.view(state)

      texts = extract_texts([conversation])
      assert Enum.any?(texts, &(&1 =~ "more message(s) below"))
    end

    test "reasoning panel is hidden when show_reasoning is false" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :processing,
        show_reasoning: false,
        reasoning_steps: [
          %{step: "Analyzing", status: :active}
        ],
        window: {120, 40}
      }

      view = TUI.view(state)

      # Should be simple 3-pane layout without reasoning panel
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view
      assert length(children) == 3

      # Should not contain "Reasoning (N)" header (note: "Ctrl+R: Reasoning" is in hints)
      texts = extract_texts(children)
      refute Enum.any?(texts, &(&1 =~ "Reasoning ("))
    end

    test "reasoning panel is hidden when reasoning_steps is empty" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :processing,
        show_reasoning: true,
        reasoning_steps: [],
        window: {120, 40}
      }

      view = TUI.view(state)

      # Should be simple 3-pane layout without reasoning panel
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view
      assert length(children) == 3

      # Should not contain "Reasoning (N)" header (note: "Ctrl+R: Reasoning" is in hints)
      texts = extract_texts(children)
      refute Enum.any?(texts, &(&1 =~ "Reasoning ("))
    end

    test "reasoning panel shows as bottom drawer for narrow terminals" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :processing,
        show_reasoning: true,
        reasoning_steps: [
          %{step: "Step 1", status: :complete},
          %{step: "Step 2", status: :active},
          %{step: "Step 3", status: :pending}
        ],
        window: {80, 24}  # Narrow terminal (< 100)
      }

      view = TUI.view(state)

      # Should have 4 panes in narrow mode: status, conversation, reasoning panel, input
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view
      assert length(children) == 4

      # Check that reasoning panel is present
      texts = extract_texts(children)
      assert Enum.any?(texts, &(&1 =~ "Reasoning (3)"))
    end

    test "reasoning panel shows as right sidebar for wide terminals" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :processing,
        show_reasoning: true,
        reasoning_steps: [
          %{step: "Step 1", status: :complete},
          %{step: "Step 2", status: :active}
        ],
        window: {120, 40}  # Wide terminal (>= 100)
      }

      view = TUI.view(state)

      # Wide layout uses horizontal stacks for sidebar
      assert %RenderNode{type: :stack, direction: :vertical, children: children} = view

      # First child should be horizontal stack with status and reasoning header
      [first_row | _] = children
      assert %RenderNode{type: :stack, direction: :horizontal} = first_row

      # Check that reasoning header is present
      texts = extract_texts(children)
      assert Enum.any?(texts, &(&1 =~ "Reasoning (2)"))
    end

    test "reasoning panel displays step status indicators" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :processing,
        show_reasoning: true,
        reasoning_steps: [
          %{step: "Complete step", status: :complete},
          %{step: "Active step", status: :active},
          %{step: "Pending step", status: :pending}
        ],
        window: {80, 24}  # Narrow for bottom drawer
      }

      view = TUI.view(state)

      texts = extract_texts([view])
      combined = Enum.join(texts, " ")

      # Check for status indicators
      assert combined =~ "✓"  # Complete
      assert combined =~ "●"  # Active
      assert combined =~ "○"  # Pending
    end

    test "reasoning panel step styling uses correct colors" do
      state = %Model{
        config: %{provider: "anthropic", model: "claude"},
        agent_status: :idle,  # Use idle to avoid processing indicator matching
        show_reasoning: true,
        reasoning_steps: [
          %{step: "Completed Task", status: :complete}
        ],
        window: {120, 40}  # Wide for sidebar
      }

      view = TUI.view(state)

      # Find the step node with checkmark (complete indicator)
      step_node = find_step_with_checkmark(view)
      assert step_node != nil
      assert step_node.style.fg == :green  # Complete step is green
    end
  end

  describe "wrap_text/3" do
    test "returns single line when text fits" do
      result = TUI.wrap_text("hello world", 20, 20)
      assert result == ["hello world"]
    end

    test "wraps text at word boundaries" do
      result = TUI.wrap_text("hello world foo bar", 11, 11)
      assert result == ["hello world", "foo bar"]
    end

    test "handles empty text" do
      result = TUI.wrap_text("", 20, 20)
      assert result == [""]
    end

    test "handles single word longer than width" do
      result = TUI.wrap_text("superlongword", 5, 5)
      # Single word doesn't fit but we keep it anyway
      assert result == ["superlongword"]
    end

    test "handles multiple words requiring multiple lines" do
      result = TUI.wrap_text("one two three four five", 10, 10)
      assert result == ["one two", "three four", "five"]
    end

    test "respects different first line and continuation widths" do
      result = TUI.wrap_text("hello world foo bar baz", 11, 15)
      # First line: "hello world" (11 chars)
      # Continuation: "foo bar baz" (11 chars, fits in 15)
      assert result == ["hello world", "foo bar baz"]
    end
  end

  # Helper functions for view tests

  alias TermUI.Component.RenderNode

  defp extract_texts(nodes) when is_list(nodes) do
    Enum.flat_map(nodes, &extract_texts/1)
  end

  defp extract_texts(%RenderNode{type: :text, content: content}) when is_binary(content) do
    [content]
  end

  defp extract_texts(%RenderNode{type: :stack, children: children}) do
    extract_texts(children)
  end

  defp extract_texts(_), do: []

  defp find_message_with_content(nodes, content) when is_list(nodes) do
    Enum.find_value(nodes, fn node -> find_message_with_content(node, content) end)
  end

  defp find_message_with_content(%RenderNode{type: :text, content: text_content} = node, content)
       when is_binary(text_content) do
    if String.contains?(text_content, content), do: node, else: nil
  end

  defp find_message_with_content(%RenderNode{type: :stack, children: children}, content) do
    find_message_with_content(children, content)
  end

  defp find_message_with_content(_, _), do: nil

  # Helper to find a step node with checkmark (complete indicator only)
  defp find_step_with_checkmark(nodes) when is_list(nodes) do
    Enum.find_value(nodes, fn node -> find_step_with_checkmark(node) end)
  end

  defp find_step_with_checkmark(%RenderNode{type: :text, content: content} = node)
       when is_binary(content) do
    if String.contains?(content, "✓") do
      node
    else
      nil
    end
  end

  defp find_step_with_checkmark(%RenderNode{type: :stack, children: children}) do
    find_step_with_checkmark(children)
  end

  defp find_step_with_checkmark(_), do: nil
end
