# Phase 4 - Conversation Ingress and Runtime Overlay Adoption

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_driver.spec.md`
- `../specs/coding_assistance_boundary.spec.md`
- `../decisions/jido_code.factory_control_plane_and_runtime_overlay.md`
- `../decisions/jido_code.coding_assistance_conversation_driver.md`
- `JidoCode.CodeServer`
- `JidoCode.CodingAssistance`
- `JidoCode.JidoOsRuntime`

## Relevant Assumptions / Defaults
- `ManagedRepo`, `WorkItem`, and governed `Run` records exist from earlier phases.
- `jido_os` remains the canonical owner of sessions, turns, runtime steering, and turn policy.
- Existing UI subscribers still depend on the current conversation event contract and should not be broken by the migration.

[x] 4 Phase 4 - Conversation Ingress and Runtime Overlay Adoption
  Make operator and repo conversations true ingress and steering surfaces into the managed-repo control loop while preserving `jido_os` as the runtime overlay and keeping subscriber-facing compatibility stable.

  [x] 4.1 Section - Conversation-to-Control-Loop Normalization
    Stop treating chat as a separate orchestration lane by routing conversation demand into the same work-synthesis and run-governance loop as other inputs.

    [x] 4.1.1 Task - Normalize conversation turns into factory demand records
      Make coding chat create or steer durable control-plane records rather than operating as an isolated project chat runtime.

      [x] 4.1.1.1 Subtask - Route operator and repo conversation turns into `Intake`, `Event`, `Assessment`, and `WorkItem` creation or reprioritization paths where appropriate.
      [x] 4.1.1.2 Subtask - Preserve actor, repo, session, request, and correlation context across conversation ingress.
      [x] 4.1.1.3 Subtask - Distinguish between conversational steering of existing work and new-demand creation for brand-new work items.

    [x] 4.1.2 Task - Align conversation identity with managed-repo and session identity
      Make repo conversations legible in both the control plane and the runtime overlay.

      [x] 4.1.2.1 Subtask - Preserve `conversation_id == session_id` for coding-oriented runtime paths.
      [x] 4.1.2.2 Subtask - Associate conversations with `ManagedRepo` rather than only the transitional `Project` object.
      [x] 4.1.2.3 Subtask - Preserve mixed-mode compatibility while existing UI routes and records still speak in project terms.

  [x] 4.2 Section - Coding Assistance Driver and Event Bridge Adoption
    Move the coding-turn path behind the product-owned boundary while preserving current UI subscriber behavior.

    [x] 4.2.1 Task - Route coding conversations through `JidoCode.CodingAssistance`
      Make the product-owned coding boundary the first-class driver rather than a helper beside the conversation runtime.

      [x] 4.2.1.1 Subtask - Add actor-aware conversation APIs in `CodeServer` and UI entrypoints.
      [x] 4.2.1.2 Subtask - Route coding turns through `JidoCode.CodingAssistance` before any direct runtime-specific delegation.
      [x] 4.2.1.3 Subtask - Preserve public `jido_os` service usage and avoid coupling product code to private internal coding agents.

    [x] 4.2.2 Task - Preserve the subscriber-facing event contract through translation
      Keep the UI stable while the runtime and control-plane integration model changes underneath it.

      [x] 4.2.2.1 Subtask - Translate public `jido_os` session-turn events back into the existing conversation event model.
      [x] 4.2.2.2 Subtask - Preserve `assistant.delta`, `assistant.message`, and failure-event compatibility for current subscribers.
      [x] 4.2.2.3 Subtask - Keep downstream UI-specific rendering logic outside `jido_os` and outside the control-plane ontology.

  [x] 4.3 Section - Runtime Overlay Boundary Hardening
    Preserve the architecture line between product truth and runtime interaction while the conversation path becomes more important.

    [x] 4.3.1 Task - Keep `jido_os` as runtime overlay, not product truth
      Make the runtime/session layer richer without letting it absorb managed-repo control-plane ownership.

      [x] 4.3.1.1 Subtask - Keep `ManagedRepo`, `PolicySet`, `WorkItem`, `Run`, `Evidence`, and `Decision` as product-owned records in `jido_code`.
      [x] 4.3.1.2 Subtask - Keep `jido_os` authoritative for sessions, turns, steering, interruption, and runtime capability gating only.
      [x] 4.3.1.3 Subtask - Preserve clean product-local boundary modules that translate between product records and runtime requests.

    [x] 4.3.2 Task - Keep runtime policy distinct from product governance and Ash policy
      Ensure the new conversation path still respects the three-layer policy model.

      [x] 4.3.2.1 Subtask - Apply Ash authorization before control-plane mutation from conversation ingress.
      [x] 4.3.2.2 Subtask - Apply repo-governance policy when deciding whether chat should create, steer, or halt work.
      [x] 4.3.2.3 Subtask - Preserve runtime policy as the final admission boundary for session and turn execution behavior.

  [x] 4.4 Section - Phase 4 Integration Tests
    Validate conversation ingress normalization, coding-assistance driver adoption, and runtime-overlay boundary preservation end to end.

    [x] 4.4.1 Task - Conversation-ingress scenarios
      Verify coding chat becomes part of the managed-repo work loop without destabilizing the current UI event model.

      [x] 4.4.1.1 Subtask - Add coverage for conversation turns creating or steering durable work records.
      [x] 4.4.1.2 Subtask - Add coverage for actor-aware conversation routing through `JidoCode.CodingAssistance`.
      [x] 4.4.1.3 Subtask - Add coverage for subscriber event compatibility during the driver migration.

    [x] 4.4.2 Task - Runtime-overlay boundary scenarios
      Verify the migration preserves the intended product-versus-runtime ownership line.

      [x] 4.4.2.1 Subtask - Add coverage showing product truth remains in `jido_code` records while runtime turns remain in `jido_os`.
      [x] 4.4.2.2 Subtask - Add coverage for distinct Ash, repo-governance, and runtime policy behavior across conversation-triggered work.
      [x] 4.4.2.3 Subtask - Verify no private `jido_os` agent internals become new caller-visible product APIs.
