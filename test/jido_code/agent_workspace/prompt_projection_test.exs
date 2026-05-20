defmodule JidoCode.AgentWorkspace.PromptProjectionTest do
  # covers: architecture.memory_graph_product_adoption.memory_workflows_request_explicit_memory_context
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_context
  use ExUnit.Case, async: true

  alias JidoCode.AgentWorkspace.PromptProjection

  describe "Phase 86.1 - prompt-facing graph projections" do
    test "projects semantic graph context into compact prompt lines" do
      projection =
        PromptProjection.semantic(
          %{
            workflow: :plan,
            graph_status: %{
              ready?: true,
              stale?: false,
              current_revision: "rev-86",
              latest_failure: nil
            },
            results: %{
              modules: %{matches: Enum.map(1..5, &%{module: "Example#{&1}"})},
              functions: %{matches: Enum.map(1..5, &%{function: "greet_#{&1}"})},
              impact: %{paths: Enum.map(1..5, &"path-#{&1}")}
            }
          },
          max_items: 2,
          max_item_bytes: 80
        )

      assert projection.state == :trimmed
      assert "workflow: plan" in projection.lines
      assert "graph_ready?: true" in projection.lines
      assert "graph_revision: rev-86" in projection.lines
      assert Enum.any?(projection.lines, &String.starts_with?(&1, "functions:"))
      assert Enum.any?(projection.lines, &String.contains?(&1, "projection item truncated"))
      assert projection.diagnostics.dropped_items == 1
    end

    test "projects memory graph context without exposing raw internals unbounded" do
      projection =
        PromptProjection.memory(
          %{
            workflow: :execute,
            graph: %{ready?: true, stale?: false, current_revision: "rev-memory-86"},
            freshness: %{label: "Memory graph ready"},
            policy: %{intent: :implementation_constraints, follow_up_intent: :work_item},
            selection: %{
              selected_items: %{
                memories:
                  Enum.map(1..4, fn index ->
                    %{
                      memory_kind: "Decision",
                      content: "Decision #{index}: " <> String.duplicate("keep behavior stable ", 20)
                    }
                  end),
                provenance:
                  Enum.map(1..4, fn index ->
                    %{
                      provenance_kind: "Plan",
                      content: "Plan #{index}: " <> String.duplicate("previous context ", 20)
                    }
                  end)
              },
              governed_references: [%{kind: :work_item, id: "work-86", label: "Current work item"}]
            }
          },
          max_items: 3,
          max_item_bytes: 90
        )

      assert projection.state == :trimmed
      assert "workflow: execute" in projection.lines
      assert "graph_ready?: true" in projection.lines
      assert "policy_intent: implementation_constraints" in projection.lines
      assert Enum.any?(projection.lines, &String.starts_with?(&1, "memory: Decision:"))
      assert Enum.any?(projection.lines, &String.contains?(&1, "projection item truncated"))
      assert projection.diagnostics.original_items == 9
      assert projection.diagnostics.packed_items == 3
      assert projection.diagnostics.dropped_items == 6
    end

    test "returns empty projections for missing graph contexts" do
      assert %{state: :empty, lines: []} = PromptProjection.semantic(%{})
      assert %{state: :empty, lines: []} = PromptProjection.memory(nil)
    end
  end
end
