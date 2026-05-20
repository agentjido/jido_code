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

  describe "Phase 87.1 - specialist history budget contract" do
    test "packs old ReAct history while preserving current user turn" do
      messages =
        [
          %{role: :system, content: "system prompt"},
          %{role: :user, content: "old user " <> String.duplicate("x", 200)},
          %{role: :assistant, content: "old assistant " <> String.duplicate("y", 200)}
        ] ++
          Enum.map(1..12, fn index ->
            %{role: :user, content: "old turn #{index} " <> String.duplicate("z", 120)}
          end) ++
          [%{role: :user, content: "current request must survive"}]

      packed = ContextBudget.pack_messages(messages, token_budget: 80, max_messages: 5)

      assert List.first(packed.messages).content == "system prompt"
      assert List.last(packed.messages).content == "current request must survive"
      assert packed.diagnostics.state == :trimmed
      assert packed.diagnostics.dropped_messages > 0
      assert length(packed.messages) <= 6
    end

    test "keeps assistant tool-call groups paired with tool results" do
      messages = [
        %{role: :system, content: "system"},
        %{role: :user, content: "old request " <> String.duplicate("a", 300)},
        %{
          role: :assistant,
          content: nil,
          tool_calls: [%{id: "call-1", name: "read_file", arguments: %{path: "lib/a.ex"}}]
        },
        %{role: :tool, tool_call_id: "call-1", name: "read_file", content: "file output"},
        %{role: :user, content: "current request"}
      ]

      packed = ContextBudget.pack_messages(messages, token_budget: 40, max_messages: 4)

      roles = Enum.map(packed.messages, & &1.role)

      assert roles == [:system, :assistant, :tool, :user]
      assert Enum.any?(packed.messages, &(Map.get(&1, :tool_call_id) == "call-1"))
      assert packed.diagnostics.dropped_messages == 1
    end

    test "ReAct request transformer delegates message packing through policy" do
      request = %{
        messages: [
          %{role: :system, content: "system"},
          %{role: :user, content: "old " <> String.duplicate("x", 200)},
          %{role: :user, content: "current"}
        ],
        llm_opts: [],
        tools: %{}
      }

      policy = ContextBudget.policy(input_token_budget: 120, history: %{token_budget: 20, max_messages: 2})

      assert {:ok, %{messages: messages}} =
               JidoCode.ContextBudget.ReActRequestTransformer.transform_request(
                 request,
                 %{},
                 %{model: "deterministic:deterministic"},
                 %{context_budget_policy: policy}
               )

      assert Enum.map(messages, & &1.content) == ["system", "current"]
    end
  end
end
