defmodule JidoCode.TUITest do
  use ExUnit.Case, async: false

  alias JidoCode.Settings
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias TermUI.Event

  setup do
    # Clear settings cache before each test
    Settings.clear_cache()
    :ok
  end

  describe "Model struct" do
    test "has correct default values" do
      model = %Model{}

      assert model.input_buffer == ""
      assert model.messages == []
      assert model.agent_status == :unconfigured
      assert model.config == %{provider: nil, model: nil}
      assert model.reasoning_steps == []
      assert model.window == {80, 24}
    end

    test "can be created with custom values" do
      model = %Model{
        input_buffer: "test input",
        messages: [%{role: :user, content: "hello", timestamp: DateTime.utc_now()}],
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"},
        reasoning_steps: [%{step: "thinking", status: :active}],
        window: {120, 40}
      }

      assert model.input_buffer == "test input"
      assert length(model.messages) == 1
      assert model.agent_status == :idle
      assert model.config.provider == "anthropic"
      assert model.window == {120, 40}
    end
  end

  describe "init/1" do
    test "returns a Model struct" do
      model = TUI.init([])
      assert %Model{} = model
    end

    test "subscribes to PubSub tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_message, "hello"})
      assert_receive {:test_message, "hello"}, 1000
    end

    test "sets agent_status to :unconfigured when no provider" do
      # Ensure no settings file exists (use empty settings)
      model = TUI.init([])

      # Without settings file, provider and model will be nil
      assert model.agent_status == :unconfigured
    end

    test "initializes with empty messages list" do
      model = TUI.init([])
      assert model.messages == []
    end

    test "initializes with empty input buffer" do
      model = TUI.init([])
      assert model.input_buffer == ""
    end

    test "initializes with empty reasoning steps" do
      model = TUI.init([])
      assert model.reasoning_steps == []
    end
  end

  describe "determine_status/1" do
    test "returns :unconfigured when provider is nil" do
      config = %{provider: nil, model: "gpt-4"}
      assert TUI.determine_status(config) == :unconfigured
    end

    test "returns :unconfigured when model is nil" do
      config = %{provider: "openai", model: nil}
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
    test "Enter key returns {:submit}" do
      model = %Model{}
      event = Event.key(:enter)

      assert TUI.event_to_msg(event, model) == {:submit}
    end

    test "Backspace returns {:key_input, :backspace}" do
      model = %Model{}
      event = Event.key(:backspace)

      assert TUI.event_to_msg(event, model) == {:key_input, :backspace}
    end

    test "Ctrl+C returns :quit" do
      model = %Model{}
      event = Event.key(:c, modifiers: [:ctrl])

      assert TUI.event_to_msg(event, model) == :quit
    end

    test "plain 'c' key returns {:key_input, \"c\"}" do
      model = %Model{}
      event = Event.key(:c, char: "c")

      assert TUI.event_to_msg(event, model) == {:key_input, "c"}
    end

    test "printable characters return {:key_input, char}" do
      model = %Model{}

      # Test various printable characters
      assert TUI.event_to_msg(Event.key(:a, char: "a"), model) == {:key_input, "a"}
      assert TUI.event_to_msg(Event.key(:z, char: "Z"), model) == {:key_input, "Z"}
      assert TUI.event_to_msg(Event.key(:space, char: " "), model) == {:key_input, " "}
      assert TUI.event_to_msg(Event.key(:"1", char: "1"), model) == {:key_input, "1"}
    end

    test "resize event returns {:resize, width, height}" do
      model = %Model{}
      event = Event.resize(120, 40)

      assert TUI.event_to_msg(event, model) == {:resize, 120, 40}
    end

    test "returns :ignore for unhandled events" do
      model = %Model{}

      # Mouse events
      assert TUI.event_to_msg(Event.mouse(:click, :left, 10, 10), model) == :ignore

      # Focus events
      assert TUI.event_to_msg(Event.focus(:gained), model) == :ignore

      # Keys without char (function keys, etc.)
      assert TUI.event_to_msg(Event.key(:f1), model) == :ignore

      # Unknown events
      assert TUI.event_to_msg(:some_event, model) == :ignore
      assert TUI.event_to_msg(nil, model) == :ignore
    end
  end

  describe "update/2 - key input" do
    test "appends character to input buffer" do
      model = %Model{input_buffer: "hel"}

      {new_model, commands} = TUI.update({:key_input, "l"}, model)

      assert new_model.input_buffer == "hell"
      assert commands == []
    end

    test "appends to empty input buffer" do
      model = %Model{input_buffer: ""}

      {new_model, _} = TUI.update({:key_input, "a"}, model)

      assert new_model.input_buffer == "a"
    end

    test "handles multiple characters" do
      model = %Model{input_buffer: ""}

      {model1, _} = TUI.update({:key_input, "h"}, model)
      {model2, _} = TUI.update({:key_input, "i"}, model1)

      assert model2.input_buffer == "hi"
    end
  end

  describe "update/2 - backspace" do
    test "removes last character from input buffer" do
      model = %Model{input_buffer: "hello"}

      {new_model, commands} = TUI.update({:key_input, :backspace}, model)

      assert new_model.input_buffer == "hell"
      assert commands == []
    end

    test "does nothing on empty buffer" do
      model = %Model{input_buffer: ""}

      {new_model, _} = TUI.update({:key_input, :backspace}, model)

      assert new_model.input_buffer == ""
    end

    test "handles single character buffer" do
      model = %Model{input_buffer: "a"}

      {new_model, _} = TUI.update({:key_input, :backspace}, model)

      assert new_model.input_buffer == ""
    end
  end

  describe "update/2 - submit" do
    test "clears input buffer and adds message" do
      model = %Model{input_buffer: "hello", messages: []}

      {new_model, commands} = TUI.update({:submit}, model)

      assert new_model.input_buffer == ""
      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :user
      assert hd(new_model.messages).content == "hello"
      assert commands == []
    end

    test "trims whitespace from input" do
      model = %Model{input_buffer: "  hello world  ", messages: []}

      {new_model, _} = TUI.update({:submit}, model)

      assert hd(new_model.messages).content == "hello world"
    end

    test "does nothing with empty input" do
      model = %Model{input_buffer: "", messages: []}

      {new_model, _} = TUI.update({:submit}, model)

      assert new_model.input_buffer == ""
      assert new_model.messages == []
    end

    test "does nothing with whitespace-only input" do
      model = %Model{input_buffer: "   ", messages: []}

      {new_model, _} = TUI.update({:submit}, model)

      assert new_model.messages == []
    end

    test "appends to existing messages" do
      existing_msg = %{role: :assistant, content: "hi", timestamp: DateTime.utc_now()}
      model = %Model{input_buffer: "hello", messages: [existing_msg]}

      {new_model, _} = TUI.update({:submit}, model)

      assert length(new_model.messages) == 2
      assert List.last(new_model.messages).role == :user
    end
  end

  describe "update/2 - quit" do
    test "returns :quit command" do
      model = %Model{}

      {_new_model, commands} = TUI.update(:quit, model)

      assert commands == [:quit]
    end
  end

  describe "update/2 - resize" do
    test "updates window dimensions" do
      model = %Model{window: {80, 24}}

      {new_model, commands} = TUI.update({:resize, 120, 40}, model)

      assert new_model.window == {120, 40}
      assert commands == []
    end
  end

  describe "update/2 - agent messages" do
    test "handles agent_response" do
      model = %Model{messages: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).role == :assistant
      assert hd(new_model.messages).content == "Hello!"
    end

    test "handles status_update" do
      model = %Model{agent_status: :idle}

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert new_model.agent_status == :processing
    end

    test "handles agent_status as alias for status_update" do
      model = %Model{agent_status: :idle}

      {new_model, _} = TUI.update({:agent_status, :processing}, model)

      assert new_model.agent_status == :processing
    end

    test "handles config_change with atom keys" do
      model = %Model{config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:config_change, %{provider: "anthropic", model: "claude"}}, model)

      assert new_model.config.provider == "anthropic"
      assert new_model.config.model == "claude"
      assert new_model.agent_status == :idle
    end

    test "handles config_change with string keys" do
      model = %Model{config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:config_change, %{"provider" => "openai", "model" => "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
    end

    test "handles config_changed as alias for config_change" do
      model = %Model{config: %{provider: nil, model: nil}}

      {new_model, _} = TUI.update({:config_changed, %{provider: "openai", model: "gpt-4"}}, model)

      assert new_model.config.provider == "openai"
      assert new_model.config.model == "gpt-4"
      assert new_model.agent_status == :idle
    end

    test "handles reasoning_step" do
      model = %Model{reasoning_steps: []}
      step = %{step: "Thinking...", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.reasoning_steps) == 1
      assert hd(new_model.reasoning_steps) == step
    end

    test "handles clear_reasoning_steps" do
      model = %Model{reasoning_steps: [%{step: "Step 1", status: :complete}]}

      {new_model, _} = TUI.update(:clear_reasoning_steps, model)

      assert new_model.reasoning_steps == []
    end
  end

  describe "message queueing" do
    test "agent_response adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:agent_response, "Hello!"}, model)

      assert length(new_model.message_queue) == 1
      {{:agent_response, "Hello!"}, _timestamp} = hd(new_model.message_queue)
    end

    test "status_update adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:status_update, :processing}, model)

      assert length(new_model.message_queue) == 1
      {{:status_update, :processing}, _timestamp} = hd(new_model.message_queue)
    end

    test "config_change adds to message queue" do
      model = %Model{message_queue: []}

      {new_model, _} = TUI.update({:config_change, %{provider: "test"}}, model)

      assert length(new_model.message_queue) == 1
    end

    test "reasoning_step adds to message queue" do
      model = %Model{message_queue: []}
      step = %{step: "Thinking", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.message_queue) == 1
    end

    test "message queue limits size to max_queue_size" do
      # Create a model with a queue at max size
      large_queue =
        Enum.map(1..100, fn i ->
          {{:test_message, i}, DateTime.utc_now()}
        end)

      model = %Model{message_queue: large_queue}

      # Add one more message
      {new_model, _} = TUI.update({:agent_response, "New message"}, model)

      # Queue should still be at max size (100)
      assert length(new_model.message_queue) == 100

      # Most recent message should be first
      {{:agent_response, "New message"}, _} = hd(new_model.message_queue)
    end

    test "queue_message maintains LIFO order" do
      queue = []
      queue = TUI.queue_message(queue, :msg1)
      queue = TUI.queue_message(queue, :msg2)
      queue = TUI.queue_message(queue, :msg3)

      assert length(queue) == 3
      {:msg3, _} = Enum.at(queue, 0)
      {:msg2, _} = Enum.at(queue, 1)
      {:msg1, _} = Enum.at(queue, 2)
    end
  end

  describe "PubSub integration" do
    test "init subscribes to tui.events topic" do
      _model = TUI.init([])

      # Verify subscription by broadcasting and receiving
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "tui.events", {:test_pubsub, "integration"})
      assert_receive {:test_pubsub, "integration"}, 1000
    end

    test "full message flow: agent_response via PubSub" do
      model = TUI.init([])

      # Simulate receiving a PubSub message
      msg = {:agent_response, "Test response from agent"}
      {new_model, _} = TUI.update(msg, model)

      assert length(new_model.messages) == 1
      assert hd(new_model.messages).content == "Test response from agent"
      assert hd(new_model.messages).role == :assistant
    end

    test "full message flow: status transitions" do
      model = TUI.init([])

      # Start processing
      {model, _} = TUI.update({:agent_status, :processing}, model)
      assert model.agent_status == :processing

      # Complete with response
      {model, _} = TUI.update({:agent_response, "Done!"}, model)
      assert length(model.messages) == 1

      # Back to idle
      {model, _} = TUI.update({:agent_status, :idle}, model)
      assert model.agent_status == :idle
    end

    test "full message flow: reasoning steps accumulation" do
      model = TUI.init([])

      # Simulate CoT reasoning flow
      {model, _} = TUI.update({:reasoning_step, %{step: "Understanding", status: :active}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Planning", status: :pending}}, model)
      {model, _} = TUI.update({:reasoning_step, %{step: "Executing", status: :pending}}, model)

      assert length(model.reasoning_steps) == 3
      assert Enum.at(model.reasoning_steps, 0).step == "Understanding"
      assert Enum.at(model.reasoning_steps, 2).step == "Executing"

      # Clear reasoning steps for next query
      {model, _} = TUI.update(:clear_reasoning_steps, model)
      assert model.reasoning_steps == []
    end

    test "rapid message handling doesn't exceed queue limit" do
      model = TUI.init([])

      # Simulate rapid message burst (150 messages)
      model =
        Enum.reduce(1..150, model, fn i, acc ->
          {new_model, _} = TUI.update({:agent_response, "Message #{i}"}, acc)
          new_model
        end)

      # Queue should be limited to 100
      assert length(model.message_queue) == 100

      # All 150 messages should be in the messages list
      assert length(model.messages) == 150
    end
  end

  describe "update/2 - unknown messages" do
    test "returns state unchanged for unknown messages" do
      model = %Model{input_buffer: "test"}

      {new_model, commands} = TUI.update(:unknown_message, model)

      assert new_model == model
      assert commands == []
    end
  end

  describe "view/1" do
    test "returns a render tree" do
      model = %Model{
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"}
      }

      view = TUI.view(model)

      # View should return a RenderNode with type :stack
      assert %TermUI.Component.RenderNode{type: :stack, direction: :vertical} = view
    end

    test "renders unconfigured status message" do
      model = %Model{
        agent_status: :unconfigured,
        config: %{provider: nil, model: nil}
      }

      view = TUI.view(model)

      # Convert view tree to string for inspection
      view_text = inspect(view)

      assert view_text =~ "Not Configured" or view_text =~ "unconfigured"
    end

    test "renders configured status" do
      model = %Model{
        agent_status: :idle,
        config: %{provider: "anthropic", model: "claude-3-5-sonnet"}
      }

      view = TUI.view(model)
      view_text = inspect(view)

      assert view_text =~ "anthropic" or view_text =~ "Idle"
    end
  end

  describe "integration" do
    test "TUI module uses TermUI.Elm behaviour" do
      # Verify the module implements the required callbacks
      behaviours = JidoCode.TUI.__info__(:attributes)[:behaviour] || []
      assert TermUI.Elm in behaviours
    end

    test "Model struct is accessible via JidoCode.TUI.Model" do
      # Verify the nested module is accessible
      assert Code.ensure_loaded?(JidoCode.TUI.Model)
    end
  end
end
