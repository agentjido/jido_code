# Phase 81 - CodingPod Refactorer API Exposure

<!-- covers: architecture.agent_os_integration.coding_agents -->
<!-- covers: architecture.agent_os_integration.eager_and_lazy_agent_activation -->
<!-- covers: architecture.agent_os_integration.pod_contains_multiple_agents -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/pods/coding_pod.ex`
- `lib/jido_code/agents/refactorer.ex`
- `lib/jido_code/agent_workspace/specialist_runner.ex`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `lib/jido_code/agent_workspace/deterministic_specialist_runner.ex`
- `docs/developer/04-coding-pod-and-specialist-workflows.md`
- `docs/developer/05-specialist-prompts-context-and-tool-execution.md`

## Relevant Assumptions / Defaults
- `Refactorer` is already part of the `CodingPod` topology as a lazy specialist.
- `AgentWorkspace` is the product-owned boundary for specialist routing; callers should not address pod internals directly.
- Refactoring work must preserve behavior and should follow the same bounded context, workflow provenance, task-board artifact, and pod metadata patterns as plan, execute, review, and explain.
- Refactorer exposure should not change `full_workflow/3,4` by default. Full workflow remains plan -> execute -> review unless a later phase explicitly adopts a refactor stage.

[ ] 81 Phase 81 - CodingPod Refactorer API Exposure
  Expose the existing `CodingPod` refactorer specialist through a first-class product API so behavior-preserving refactoring can use the same runtime, provenance, and context boundaries as other specialist work.

  [x] 81.1 Section - Workspace Refactor Entry Point
    Add the missing product-owned API surface for invoking the lazy refactorer specialist without leaking pod internals.

    [x] 81.1.1 Task - Add `AgentWorkspace.refactor_work/3,4`
      Route refactoring requests through the existing per-work-item `CodingPod` lifecycle and specialist runner pattern.

      [x] 81.1.1.1 Subtask - Resolve workspace path, LLM selection, kernel, and coding pod exactly like `plan_work/4`, `execute_work/4`, `review_work/4`, and `explain_work/4`.
      [x] 81.1.1.2 Subtask - Build refactor instructions through the shared `agent_instruction/4` path with semantic and memory context included when available.
      [x] 81.1.1.3 Subtask - Ensure the `:refactorer` node lazily starts through `ensure_coding_specialist/3`.
      [x] 81.1.1.4 Subtask - Return a bounded result map with refactoring output, original instruction, semantic context, memory context, workflow provenance summary, and LLM selection summary.

    [x] 81.1.2 Task - Persist refactor-stage pod metadata and task-board state
      Keep refactorer runs visible and recoverable using the same product-owned runtime bookkeeping as other CodingPod specialists.

      [x] 81.1.2.1 Subtask - Persist a `:refactoring` stage result with `last_refactor` metadata on the coding pod.
      [x] 81.1.2.2 Subtask - Ensure task-board stage events and artifacts are written by the shared specialist-run wrapper.
      [x] 81.1.2.3 Subtask - Preserve workflow provenance capture for refactorer runs without exposing specialist-local internals to callers.

  [ ] 81.2 Section - Product Routing And Documentation
    Make refactorer exposure understandable to contributors and safe for future conversation or workflow adoption.

    [ ] 81.2.1 Task - Update developer guidance for refactorer API exposure
      Align the CodingPod and prompt-context guides with the new refactorer entrypoint.

      [ ] 81.2.1.1 Subtask - Update the CodingPod guide so `refactor_work/3,4` is listed with plan, execute, review, and explain.
      [ ] 81.2.1.2 Subtask - Update the prompt-context guide so refactorer runs are included in the workspace-prepared specialist request list.
      [ ] 81.2.1.3 Subtask - Document that `full_workflow/3,4` remains plan -> execute -> review unless explicitly changed later.

    [ ] 81.2.2 Task - Keep specialist selection deterministic
      Preserve product-owned dispatch when refactorer work is later adopted by conversations or workflows.

      [ ] 81.2.2.1 Subtask - Keep callers on `AgentWorkspace.refactor_work/3,4` rather than direct pod or agent calls.
      [ ] 81.2.2.2 Subtask - Ensure any future conversation routing maps explicit refactor intent to the refactorer deterministically.
      [ ] 81.2.2.3 Subtask - Keep refactorer unavailable or degraded states typed and product-facing.

  [ ] 81.3 Section - Verification
    Prove the refactorer is exposed through the same bounded runtime contract as the other CodingPod specialists.

    [ ] 81.3.1 Task - Add focused workspace coverage
      Verify `refactor_work/3,4` starts the refactorer lazily and records bounded runtime state.

      [ ] 81.3.1.1 Subtask - Add coverage proving `AgentWorkspace.refactor_work/4` ensures kernel, coding pod, and `:refactorer` node before running.
      [ ] 81.3.1.2 Subtask - Add coverage proving returned refactor results include instruction, semantic context, memory context, workflow provenance, and LLM selection summary.
      [ ] 81.3.1.3 Subtask - Add coverage proving pod metadata records `last_refactor` without disturbing existing `last_plan`, `last_changes`, `last_review`, or `last_explanation` metadata.

    [ ] 81.3.2 Task - Add integration coverage
      Verify refactorer exposure fits the existing CodingPod isolation and lifecycle model.

      [ ] 81.3.2.1 Subtask - Add an integration test proving different work items invoke isolated refactorer specialists in separate CodingPods.
      [ ] 81.3.2.2 Subtask - Add coverage proving completed work-item pod teardown ends refactorer context along with other specialist context.
      [ ] 81.3.2.3 Subtask - Run the relevant CodingPod, AgentWorkspace, and conversation-runtime suites after implementation.
