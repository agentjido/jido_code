# Phase 52 - Deterministic Conversation Workflow Routing And Clarification

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.workflow_routing_is_deterministic_and_product_owned -->
<!-- covers: architecture.conversation_orchestration.explicit_workflow_intent_and_continuity_take_precedence -->
<!-- covers: architecture.conversation_orchestration.ambiguous_workflow_routing_requests_clarification -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `lib/jido_code/conversations.ex`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/conversations/work_resolution.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `test/jido_code/phase_forty_six_integration_test.exs`
- `test/jido_code/phase_fifty_one_integration_test.exs`

## Relevant Assumptions / Defaults
- Phases 46 through 51 already establish the real LLM conversation runtime, canonical work-item conversation identity, and current work-item lifecycle rules.
- Current workflow routing is still duplicated across conversation boundaries and remains too dependent on coarse free-text heuristics.
- Productive workflow routing should stay deterministic and product-owned rather than delegating specialist selection to the active AI agent or provider runtime.
- The canonical productive workflow set for this phase remains `:plan`, `:execute`, `:review`, and `:explain`; introducing a separate `:refactor` workflow remains a later decision.

[x] 52 Phase 52 - Deterministic Conversation Workflow Routing And Clarification
  Centralize productive conversation workflow routing into one deterministic product-owned boundary, preserve explicit operator intent and continuity ahead of text heuristics, and ask for clarification when routing is ambiguous instead of silently guessing the specialist.

  [x] 52.1 Section - Canonical Routing Boundary
    Replace duplicated workflow inference paths with one bounded routing contract that downstream conversation helpers can reuse without drift.

    [x] 52.1.1 Task - Introduce one product-owned workflow routing contract
      Define a canonical router that accepts bounded turn, conversation, and surface context and returns a reusable workflow decision with inspectable metadata.

      [x] 52.1.1.1 Subtask - Define normalized routing inputs for explicit workflow intent, prior workflow continuity, bounded surface intent, and free-text cues.
      [x] 52.1.1.2 Subtask - Return bounded routing outputs such as selected workflow, routing source, confidence or ambiguity state, and explainable routing reasons.
      [x] 52.1.1.3 Subtask - Persist routing metadata on the turn or child-work path so runtime helpers can reuse the same decision instead of re-inferring it later.

    [x] 52.1.2 Task - Remove duplicated routing heuristics from conversation boundaries
      Make the existing work-resolution and runtime boundaries consume the canonical routing result so productive routing stops drifting between phases of the same turn.

      [x] 52.1.2.1 Subtask - Replace `WorkResolution` workflow inference with the canonical routing boundary.
      [x] 52.1.2.2 Subtask - Replace `Conversations.Runtime` workflow re-inference with reuse of the canonical routing result and explicit continuity metadata.
      [x] 52.1.2.3 Subtask - Keep specialist dispatch deterministic and product-owned after routing rather than letting the model self-select a specialist.

  [x] 52.2 Section - Explicit Intent And Ambiguity Handling
    Make routing follow explicit product signals and governed continuity first, while routing conflicts or weak signals yield clarification rather than silent misclassification.

    [x] 52.2.1 Task - Prioritize explicit workflow intent and continuity over text heuristics
      Preserve the operator’s stated intent and the active governed work thread before falling back to free-text scoring.

      [x] 52.2.1.1 Subtask - Let bounded product entrypoints pass explicit workflow intent when the surface already knows whether the operator wants planning, execution, review, or explanation.
      [x] 52.2.1.2 Subtask - Reuse prior workflow for clarification, resume, and active work-item continuation paths unless the operator explicitly changes it.
      [x] 52.2.1.3 Subtask - Keep routing decisions explainable across repo-intake, work-item, and governed follow-up flows without introducing hidden AI-driven classification.

    [x] 52.2.2 Task - Clarify ambiguous routing instead of guessing
      Define how the conversation runtime identifies ambiguous routing states and turns them into bounded clarification requests that preserve continuity.

      [x] 52.2.2.1 Subtask - Define deterministic ambiguity and tie behavior for conflicting or weak routing cues.
      [x] 52.2.2.2 Subtask - Emit clarification through the normal conversation control flow when routing cannot confidently select a workflow.
      [x] 52.2.2.3 Subtask - Preserve work-item linkage, bounded shared context, and pending routing state so clarified turns resume the intended governed work thread.

  [x] 52.3 Section - Integration Coverage And Current-Truth Convergence
    Prove the new routing model end to end and keep current-truth specs plus contributor guidance aligned once routing stops being duplicated heuristic logic.

    [x] 52.3.1 Task - Add end-to-end coverage for deterministic and ambiguous routing cases
      Verify that explicit intent, continuity, ambiguity handling, and specialist dispatch all stay coherent through the real conversation runtime.

      [x] 52.3.1.1 Subtask - Add coverage proving explicit workflow intent overrides ambiguous free-text cues.
      [x] 52.3.1.2 Subtask - Add coverage proving clarification and resume paths preserve the established workflow without reclassification drift.
      [x] 52.3.1.3 Subtask - Add coverage proving ambiguous requests yield clarification instead of silently dispatching the wrong specialist.

    [x] 52.3.2 Task - Converge specs, planning, and contributor guidance
      Keep the architecture and contributor mental model coherent after deterministic routing becomes the canonical product behavior.

      [x] 52.3.2.1 Subtask - Update conversation specs to describe deterministic routing precedence, bounded routing metadata, and clarification behavior.
      [x] 52.3.2.2 Subtask - Verify the planning index remains coherent once Phase 52 is introduced.
      [x] 52.3.2.3 Subtask - Update contributor-facing guidance so future conversation work treats workflow routing as one shared product-owned boundary.
