defmodule JidoCode.Reasoning.ChainOfThoughtTest do
  use ExUnit.Case, async: false

  alias JidoCode.Reasoning.ChainOfThought

  @moduletag :reasoning

  setup do
    # Attach a test handler to capture telemetry events
    test_pid = self()

    :telemetry.attach_many(
      "cot-test-handler-#{inspect(self())}",
      [
        ChainOfThought.event_start(),
        ChainOfThought.event_complete(),
        ChainOfThought.event_fallback(),
        ChainOfThought.event_error()
      ],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach("cot-test-handler-#{inspect(test_pid)}")
    end)

    :ok
  end

  describe "default_config/0" do
    test "returns default configuration" do
      config = ChainOfThought.default_config()

      assert config.mode == :zero_shot
      assert config.temperature == 0.2
      assert config.max_iterations == 1
      assert config.enable_validation == true
      assert config.fallback_on_error == true
    end
  end

  describe "format_steps_for_display/1" do
    test "formats steps with numbers and descriptions" do
      reasoning_plan = %{
        goal: "Test goal",
        analysis: "Test analysis",
        steps: [
          %{number: 1, description: "First step", expected_outcome: nil},
          %{number: 2, description: "Second step", expected_outcome: "Some result"},
          %{number: 3, description: "Third step", expected_outcome: nil}
        ],
        expected_results: "Final result",
        potential_issues: []
      }

      formatted = ChainOfThought.format_steps_for_display(reasoning_plan)

      assert length(formatted) == 3
      assert Enum.at(formatted, 0) == "1. First step"
      assert Enum.at(formatted, 1) == "2. Second step (expected: Some result)"
      assert Enum.at(formatted, 2) == "3. Third step"
    end

    test "returns empty list for nil plan" do
      assert ChainOfThought.format_steps_for_display(nil) == []
    end

    test "returns empty list for plan without steps" do
      assert ChainOfThought.format_steps_for_display(%{}) == []
    end

    test "handles empty steps list" do
      assert ChainOfThought.format_steps_for_display(%{steps: []}) == []
    end
  end

  describe "summarize_plan/1" do
    test "summarizes plan with goal and step count" do
      reasoning_plan = %{
        goal: "Implement rate limiting",
        analysis: "Analysis",
        steps: [
          %{number: 1, description: "Step 1", expected_outcome: nil},
          %{number: 2, description: "Step 2", expected_outcome: nil}
        ],
        expected_results: "Rate limiter works",
        potential_issues: ["Edge case 1", "Edge case 2"]
      }

      summary = ChainOfThought.summarize_plan(reasoning_plan)

      assert summary =~ "Goal: Implement rate limiting"
      assert summary =~ "2 steps"
      assert summary =~ "Issues: 2"
    end

    test "truncates long goals" do
      reasoning_plan = %{
        goal: "This is a very long goal that should be truncated because it exceeds fifty characters",
        analysis: "Analysis",
        steps: [%{number: 1, description: "Step", expected_outcome: nil}],
        expected_results: "Result",
        potential_issues: []
      }

      summary = ChainOfThought.summarize_plan(reasoning_plan)

      assert summary =~ "..."
      assert String.length(summary) < 150
    end

    test "returns message for nil plan" do
      assert ChainOfThought.summarize_plan(nil) == "No reasoning plan available"
    end

    test "returns message for invalid plan" do
      assert ChainOfThought.summarize_plan("invalid") == "Invalid reasoning plan"
    end
  end

  describe "event name accessors" do
    test "event_start/0 returns correct event name" do
      assert ChainOfThought.event_start() == [:jido_code, :reasoning, :start]
    end

    test "event_complete/0 returns correct event name" do
      assert ChainOfThought.event_complete() == [:jido_code, :reasoning, :complete]
    end

    test "event_fallback/0 returns correct event name" do
      assert ChainOfThought.event_fallback() == [:jido_code, :reasoning, :fallback]
    end

    test "event_error/0 returns correct event name" do
      assert ChainOfThought.event_error() == [:jido_code, :reasoning, :error]
    end
  end

  describe "config validation" do
    # These tests verify internal config validation through public API behavior

    test "default config uses zero_shot mode" do
      config = ChainOfThought.default_config()
      assert config.mode == :zero_shot
    end

    test "default config uses temperature 0.2" do
      config = ChainOfThought.default_config()
      assert config.temperature == 0.2
    end

    test "default config enables validation" do
      config = ChainOfThought.default_config()
      assert config.enable_validation == true
    end

    test "default config enables fallback on error" do
      config = ChainOfThought.default_config()
      assert config.fallback_on_error == true
    end
  end

  describe "reasoning step parsing" do
    # Test the step extraction logic through format_steps_for_display

    test "handles steps with expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: "Something done"}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something (expected: Something done)"
    end

    test "handles steps without expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: nil}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something"
    end

    test "handles steps with empty expected outcomes" do
      plan = %{
        steps: [
          %{number: 1, description: "Do something", expected_outcome: ""}
        ]
      }

      formatted = ChainOfThought.format_steps_for_display(plan)

      assert hd(formatted) == "1. Do something"
    end
  end
end
