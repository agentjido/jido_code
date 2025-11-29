defmodule JidoCode.TUITest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI
  alias JidoCode.TUI.Model

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

    test "returns :ignore for any event (placeholder implementation)" do
      state = %Model{}
      assert TUI.event_to_msg({:key, "a"}, state) == :ignore
      assert TUI.event_to_msg({:resize, 100, 50}, state) == :ignore
    end
  end

  describe "update/2" do
    test "returns state unchanged with empty commands" do
      state = %Model{input_buffer: "test"}
      {new_state, commands} = TUI.update(:any_message, state)

      assert new_state == state
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
