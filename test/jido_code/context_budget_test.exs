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

  describe "Phase 85.2 - prompt packing service foundation" do
    test "preserves required sections while trimming optional context" do
      policy = ContextBudget.policy(input_token_budget: 80)

      packed =
        ContextBudget.pack(
          [
            ContextBudget.section(:current_request, "Fix the currently failing save path.", retention: :required),
            ContextBudget.section(
              :repository_scope,
              ["managed_repo_id: repo-85", "work_item_id: work-85"],
              retention: :required
            ),
            ContextBudget.section(
              :prompt_memory,
              Enum.map(1..40, &("memory #{&1}: " <> String.duplicate("x", 40))),
              retention: :useful
            ),
            ContextBudget.section(
              :accepted_tool_results,
              Enum.map(1..20, &("tool result #{&1}: " <> String.duplicate("y", 40))),
              retention: :useful
            )
          ],
          policy: policy
        )

      assert packed.text =~ "Current request:"
      assert packed.text =~ "Fix the currently failing save path."
      assert packed.text =~ "Repository scope:"
      assert packed.text =~ "managed_repo_id: repo-85"
      assert packed.summary.state in ["trimmed", "degraded"]

      prompt_memory = Enum.find(packed.diagnostics, &(&1.kind == :prompt_memory))
      accepted_tool_results = Enum.find(packed.diagnostics, &(&1.kind == :accepted_tool_results))

      assert prompt_memory.state in [:trimmed, :dropped]
      assert accepted_tool_results.state in [:trimmed, :dropped]
      assert packed.summary.trimmed_section_count >= 1
      assert packed.summary.dropped_entry_count > 0
    end

    test "reports degraded diagnostics when required context exceeds the budget" do
      packed =
        ContextBudget.pack(
          [
            ContextBudget.section(
              :current_request,
              "Must remain visible. " <> String.duplicate("required ", 100),
              retention: :required
            ),
            ContextBudget.section(:prompt_memory, ["optional memory"], retention: :optional)
          ],
          input_token_budget: 20
        )

      assert packed.text =~ "Must remain visible."
      assert packed.summary.state == "degraded"
      assert packed.summary.degraded? == true

      request_diag = Enum.find(packed.diagnostics, &(&1.kind == :current_request))
      memory_diag = Enum.find(packed.diagnostics, &(&1.kind == :prompt_memory))

      assert request_diag.state == :degraded
      assert request_diag.reason == :required_section_exceeds_remaining_budget
      assert memory_diag.state == :dropped
      assert memory_diag.reason == :budget_exhausted
    end

    test "keeps section diagnostics separate from rendered prompt text" do
      packed =
        ContextBudget.pack(
          [
            ContextBudget.section(:current_request, "Explain the current graph state.", retention: :required),
            ContextBudget.section(:semantic_context, ["module Example", "function greet/1"], retention: :useful)
          ],
          input_token_budget: 120
        )

      assert packed.text =~ "Semantic context:"
      refute packed.text =~ "original_approximate_tokens"
      assert Enum.all?(packed.diagnostics, &Map.has_key?(&1, :original_approximate_tokens))
    end
  end
end
