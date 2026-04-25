# Phase 64 - Runtime Surface Workspace Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_environment_defaults.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/conversation_orchestration.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md`
- `lib/jido_code/conversations/runtime_readiness.ex`
- `lib/jido_code/workbench/project_detail.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code/workbench/project_semantic_inspection.ex`
- `lib/jido_code/workbench/project_memory_inspection.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code_web/live/workbench_live.ex`
- `test/jido_code_web/live/project_detail_live_test.exs`
- `test/jido_code_web/live/workbench_live_test.exs`
- `test/e2e/conversation-ui.spec.ts`

## Relevant Assumptions / Defaults
- No backward compatibility path is needed for runtime messaging; blocked states can move directly to repo-scoped wording and remediation.
- By the start of this phase, managed repositories already own canonical workspace binding and operators already have a repo-scoped way to repair it.
- Repo detail, semantic inspection, memory inspection, and workflow readiness should all describe the same repo-scoped workspace contract instead of drifting into surface-specific language.
- Current-truth subjects should only tighten to the final wording and remediation model once the runtime and operator surfaces actually converge.

[ ] 64 Phase 64 - Runtime Surface Workspace Convergence
  Converge conversation, semantic, memory, workflow, and operator-facing readiness surfaces on one repo-scoped workspace-binding model, then reconcile tests and current truth to the shipped behavior.

  [ ] 64.1 Section - Repo-Scoped Runtime And Knowledge Surface Adoption
    Align every repo-scoped execution surface on the same readiness rule and remediation path so operators stop seeing mixed workspace stories.

    [ ] 64.1.1 Task - Standardize repo-scoped readiness and remediation language
      Make runtime-readiness copy explain the same underlying contract everywhere it appears.

      [ ] 64.1.1.1 Subtask - Update conversation runtime-readiness messaging to describe the managed repository's own workspace binding instead of generic missing-workspace language.
      [ ] 64.1.1.2 Subtask - Align semantic, memory, and workflow readiness messaging with the same repo-scoped workspace-binding vocabulary.
      [ ] 64.1.1.3 Subtask - Route operator remediation from blocked runtime surfaces to the canonical repo-scoped repair path instead of to install-wide setup defaults.

    [ ] 64.1.2 Task - Remove remaining shared-root assumptions from operator surfaces
      Finish the cutover by eliminating UI hints that still imply a single local-root topology.

      [ ] 64.1.2.1 Subtask - Remove copy that treats one install-wide workspace root as the durable explanation for repo execution readiness.
      [ ] 64.1.2.2 Subtask - Keep per-repository workspace identity visible where operators need to distinguish repositories that live in unrelated filesystem locations.
      [ ] 64.1.2.3 Subtask - Keep cloud-backed repositories explicitly unbound to local runtime until a repo-scoped local binding is actually set.

  [ ] 64.2 Section - Current-Truth And Contributor Convergence
    Reconcile the docs and specs only after the runtime surfaces consistently reflect the final repo-scoped model.

    [ ] 64.2.1 Task - Tighten current-truth subjects and contributor guidance to the final cutover
      Move the accepted ADR from planning intent into explicit shipped behavior once the surface convergence is real.

      [ ] 64.2.1.1 Subtask - Update setup, runtime-default, factory-control-plane, and conversation current-truth subjects to describe the shipped repo-scoped behavior precisely.
      [ ] 64.2.1.2 Subtask - Update contributor guidance and route-level operator copy that still implies a shared-parent local workspace model.
      [ ] 64.2.1.3 Subtask - Avoid adding compatibility or migration guidance for the retired shared-root assumption.

  [ ] 64.3 Section - Phase Integration Tests
    Close the cutover with integration coverage that proves operators experience one coherent repo-scoped workspace model.

    [ ] 64.3.1 Task - Add end-to-end repo-scoped runtime-readiness coverage
      Verify the converged behavior across the most important repo-scoped product surfaces.

      [ ] 64.3.1.1 Subtask - Add repo-detail coverage proving conversation runtime readiness reflects repo-scoped workspace binding and links to repo-scoped repair.
      [ ] 64.3.1.2 Subtask - Add semantic, memory, or workflow surface coverage proving the same repository binding drives their readiness and recovery behavior.
      [ ] 64.3.1.3 Subtask - Add browser or multi-surface coverage proving repositories in unrelated local paths remain legible and independently repairable.
