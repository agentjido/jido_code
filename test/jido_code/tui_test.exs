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

    test "handles reasoning_step" do
      model = %Model{reasoning_steps: []}
      step = %{step: "Thinking...", status: :active}

      {new_model, _} = TUI.update({:reasoning_step, step}, model)

      assert length(new_model.reasoning_steps) == 1
      assert hd(new_model.reasoning_steps) == step
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
