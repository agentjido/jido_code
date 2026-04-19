# Phase 46 - Real LLM Conversation Runtime Cutover

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation -->
<!-- covers: architecture.conversation_orchestration.conversation_runtime_uses_bounded_llm_boundary -->
<!-- covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit -->
<!-- covers: architecture.conversation_orchestration.real_runtime_cutover_has_no_compatibility_mode -->
<!-- covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_orchestration.spec.md`
- `../specs/agent_os_integration.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../decisions/jido_code.interruptible_conversation_orchestration.md`
- `lib/jido_code/conversations/coordinator.ex`
- `lib/jido_code/conversations/driver.ex`
- `lib/jido_code/conversations/child_work.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `lib/jido_code/pods/coding_pod.ex`
- `lib/jido_code/agents/planner.ex`
- `lib/jido_code/agents/coder.ex`
- `lib/jido_code/agents/reviewer.ex`
- `lib/jido_code/agents/explainer.ex`
- `lib/jido_code/workbench/project_conversation.ex`
- `lib/jido_code_web/live/project_detail_live.ex`
- `lib/jido_code/setup/provider_credential_checks.ex`
- `test/jido_code/phase_forty_four_integration_test.exs`
- `test/jido_code_web/live/project_detail_live_test.exs`

## Relevant Assumptions / Defaults
- Phase 44 adopted a durable repository conversation surface on managed-repository detail routes, but the current route implementation still simulates runtime progress and completion instead of using the real specialist and LLM execution path.
- The repo already has a bounded CodingPod specialist runtime, prompt assembly path, and durable conversation coordinator, so the remaining work is to join those product-owned boundaries rather than introduce a page-local chat runner.
- Real conversation execution must remain explicit, cancellable, explainable, and degraded-safe when providers, runtime services, or policy prerequisites are unavailable.
- This is a greenfield cutover, so Phase 46 should remove the fake route-local runtime rather than preserve a compatibility shim, feature flag, or dual execution path.

[x] 46 Phase 46 - Real LLM Conversation Runtime Cutover
  Replace the remaining fake repository-conversation runtime with a real LLM-backed execution path that stays bounded by the canonical conversation, workspace, and CodingPod contracts.

  [x] 46.1 Section - Product-Owned Conversation Runtime Boundary
    Introduce the runtime seam that lets conversation turns invoke real specialist or LLM-backed execution without pushing prompt assembly or model orchestration into the LiveView surface.

    [x] 46.1.1 Task - Add a real conversation execution boundary behind the coordinator
      Make repository conversation child work invoke a product-owned runtime path that can run real specialist work while preserving conversation ownership, cancellation, and event semantics.

      [x] 46.1.1.1 Subtask - Add a bounded conversation runtime interface that maps `turn.submit` and `turn.resume` into real execution requests instead of fake surface-local scheduling.
      [x] 46.1.1.2 Subtask - Preserve managed-repository, work-item, turn, child-work, and actor metadata as the real execution request crosses from the coordinator into workspace or specialist runtime boundaries.
      [x] 46.1.1.3 Subtask - Keep cancellation and settlement product-owned by routing runtime outcomes back through `tool_result.submit` or equivalent coordinator-managed update paths rather than direct LiveView mutation.

    [x] 46.1.2 Task - Remove simulated repository conversation execution from the route surface
      Cut the managed-repository detail route over from fake progress helpers to the real conversation runtime while keeping the UI event-driven and reconnectable.

      [x] 46.1.2.1 Subtask - Remove timer-driven fake progress, stdout, clarification, delta, and completion scheduling from `ProjectDetailLive`.
      [x] 46.1.2.2 Subtask - Subscribe the route to real runtime-driven conversation updates using the existing snapshot and event stream contract.
      [x] 46.1.2.3 Subtask - Keep the route bounded to product-owned conversation APIs so the LiveView never assembles prompts or calls the LLM directly, and do not preserve the removed fake path behind a compatibility switch.

  [x] 46.2 Section - Bounded Prompt, Context, And Specialist Routing
    Decide how repo conversation turns reach a real model-backed agent and ensure the prompt plus context contract stays explicit, scoped, and explainable.

    [x] 46.2.1 Task - Shape bounded conversation execution context for real turns
      Convert repository conversation scope and shared context into a prompt-safe, specialist-safe execution payload instead of relying on surface text alone.

      [x] 46.2.1.1 Subtask - Define how conversation scope, bounded shared context, accepted tool results, and pending clarification state become the real execution instruction and context payload.
      [x] 46.2.1.2 Subtask - Reuse existing semantic, memory, and workflow provenance context where appropriate through AgentWorkspace rather than inventing a second hidden context channel.
      [x] 46.2.1.3 Subtask - Keep conversation context bounded and explainable so redirected work stays attached to the same repository and governed work state unless scope changes explicitly.

    [x] 46.2.2 Task - Route repository conversation turns through real specialist execution
      Connect repo conversation turns to CodingPod specialists or an adjacent conversation specialist strategy so the model-backed work path is real and cancellable.

      [x] 46.2.2.1 Subtask - Choose and implement the product-owned routing rule for repository conversation turns, whether through existing planner, coder, reviewer, explainer specialists or a dedicated conversation specialist boundary.
      [x] 46.2.2.2 Subtask - Preserve interruptibility by ensuring progress, clarification, delta, and completion updates can be emitted while real specialist work is running.
      [x] 46.2.2.3 Subtask - Keep provider, policy, and runtime readiness explicit so missing prerequisites produce actionable failure states instead of fabricated success.

  [x] 46.3 Section - Integration Coverage, UI Hardening, And Spec Convergence
    Prove the cutover works end to end and keep the current-truth spec plus operator surface aligned with the new real runtime behavior.

    [x] 46.3.1 Task - Add real conversation runtime integration coverage
      Verify repository conversation turns now flow through the real runtime path and preserve coordinator semantics under interruption and clarification.

      [x] 46.3.1.1 Subtask - Add coverage proving a repo conversation turn creates real child work and routes execution through the bounded conversation runtime instead of LiveView-local fake scheduling.
      [x] 46.3.1.2 Subtask - Add coverage proving real progress, clarification, delta, and completion updates flow back through the coordinator and durable snapshot model.
      [x] 46.3.1.3 Subtask - Add coverage proving stop, pause, resume, and cancellation still work while real specialist execution is active.

    [x] 46.3.2 Task - Add route-level degraded and readiness scenarios
      Verify the operator surface remains safe and legible when the real LLM execution path is healthy, degraded, or unavailable.

      [x] 46.3.2.1 Subtask - Add LiveView coverage proving the managed-repository detail route renders real runtime progress instead of the old simulated conversation helpers.
      [x] 46.3.2.2 Subtask - Add coverage proving provider-credential, runtime-service, or policy-readiness failures surface explicit recovery messaging rather than fake completion.
      [x] 46.3.2.3 Subtask - Verify the planning index and conversation spec remain coherent after Phase 46 is introduced and that no compatibility-mode fake runtime remains in the product contract.
