defmodule JidoCode.TUITest do
  use ExUnit.Case, async: false

  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias JidoCode.Settings

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
    test "returns :ignore for any event (placeholder implementation)" do
      model = %Model{}

      # Test with various event types
      assert TUI.event_to_msg(:some_event, model) == :ignore
      assert TUI.event_to_msg({:key, "a"}, model) == :ignore
      assert TUI.event_to_msg(nil, model) == :ignore
    end
  end

  describe "update/2" do
    test "returns state unchanged (placeholder implementation)" do
      model = %Model{input_buffer: "test"}

      {new_model, commands} = TUI.update(:any_message, model)

      assert new_model == model
      assert commands == []
    end

    test "returns empty command list" do
      model = %Model{}
      {_new_model, commands} = TUI.update(:msg, model)
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
