defmodule JidoCode.ContextBudgetTest do
  # covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary
  use ExUnit.Case, async: true

  alias JidoCode.ContextBudget

  describe "Phase 85.1 - context budget policy model" do
    test "defines canonical section and retention contracts" do
      assert :current_request in ContextBudget.section_kinds()
      assert :repository_scope in ContextBudget.section_kinds()
      assert :prompt_memory in ContextBudget.section_kinds()
      assert :semantic_context in ContextBudget.section_kinds()
      assert :memory_context in ContextBudget.section_kinds()
      assert :tool_output in ContextBudget.section_kinds()

      assert ContextBudget.retention_classes() == [:required, :important, :useful, :optional]

      section =
        ContextBudget.section(:current_request, "Implement bounded context.", retention: :required)

      assert section.kind == :current_request
      assert section.retention == :required
      assert section.label == "Current request"
      assert section.text == "Implement bounded context."
      assert section.entries == ["Implement bounded context."]
    end

    test "resolves known model defaults without fallback diagnostics" do
      policy =
        ContextBudget.policy(
          llm_selection: %{
            provider: "deterministic",
            model: "deterministic",
            model_spec: "deterministic:deterministic"
          }
        )

      assert policy.id == "context-budget:v1"
      assert policy.provider == "deterministic"
      assert policy.model == "deterministic"
      assert policy.context_window_tokens == 4_096
      assert policy.output_token_reserve == 512
      assert policy.input_token_budget == 3_584
      assert policy.source == :model_default
      assert policy.diagnostics == []
    end

    test "uses conservative fallback diagnostics for unknown model metadata" do
      policy =
        ContextBudget.policy(
          llm_selection: %{
            provider: "unknown-provider",
            model: "unknown-model",
            model_spec: "unknown-provider:unknown-model"
          }
        )

      assert policy.input_token_budget == 14_000
      assert policy.source == :fallback
      assert [%{kind: :missing_model_metadata, state: :degraded}] = policy.diagnostics
    end

    test "accepts validated explicit budget and ratio overrides" do
      policy =
        ContextBudget.policy(
          input_token_budget: 2_048,
          output_token_reserve: 256,
          section_ratios: %{prompt_memory: 0.25, semantic_context: 0.5},
          history: %{max_messages: 12, token_budget: 1_024},
          tool_output: %{max_bytes: 1_500, max_lines: 50, max_results: 25}
        )

      assert policy.source == :override
      assert policy.input_token_budget == 2_048
      assert policy.output_token_reserve == 256
      assert policy.section_ratios.prompt_memory == 0.25
      assert policy.section_ratios.semantic_context == 0.5
      assert policy.history.max_messages == 12
      assert policy.history.token_budget == 1_024
      assert policy.tool_output.max_bytes == 1_500
      assert policy.tool_output.max_lines == 50
      assert policy.tool_output.max_results == 25
    end

    test "estimates bytes and approximate tokens explicitly" do
      assert %{bytes: 8, approximate_tokens: 2} = ContextBudget.estimate("12345678")
      assert %{bytes: bytes, approximate_tokens: tokens} = ContextBudget.estimate(["one", "two"])
      assert bytes > 0
      assert tokens > 0
    end
  end
end
