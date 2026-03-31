# Phase 7 - Public Turn Runtime Bridge and Governed Projection Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/conversation_driver.spec.md`
- `../specs/coding_assistance_boundary.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.jido_os_public_turn_runtime_adoption.md`
- `JidoCode.CodingAssistance`
- `JidoCode.Conversations.Driver`
- `JidoCode.Conversations.EventBridge`
- `JidoCode.CodeServer`
- `JidoCode.Orchestration.RunBridge`
- `JidoCode.Governance.RunGovernanceBridge`

## Relevant Assumptions / Defaults
- Phases 1 through 6 are already complete, including managed-repo control records, governed runs, and the current conversation-driver seam.
- `jido_os` now exposes richer public coding-turn surfaces, but downstream live subscription may still arrive after the first product adoption slice.
- `jido_code` remains the durable product control plane while `jido_os` remains the runtime overlay for turn execution, replay, interruption, and runtime capability policy.
- Subscriber-facing UI surfaces still depend on the existing conversation event contract and should remain stable during the public-turn adoption work.

[ ] 7 Phase 7 - Public Turn Runtime Bridge and Governed Projection Adoption
  Adopt the richer public `jido_os` turn runtime in product-owned `jido_code` seams by exposing boundary wrappers first, routing conversations through non-blocking turn start second, bridging replay-driven subscriber updates third, and materializing terminal turn outputs into governed run and evidence records last.

  [ ] 7.1 Section - Coding Assistance Public Turn Wrapper Adoption
    Expose the newer public `jido_os` turn runtime through `JidoCode.CodingAssistance` so product callers can use one product-owned API instead of constructing raw runtime requests or consuming runtime payloads directly.

    [ ] 7.1.1 Task - Add product-local wrappers for the public turn runtime
      Make `JidoCode.CodingAssistance` the single product boundary for the full public turn surface before the conversation driver changes its execution path.

      [ ] 7.1.1.1 Subtask - Add wrappers for public `jido_os` operations equivalent to `start_turn`, `get_turn`, `list_turns`, `list_turn_events`, `list_turn_artifacts`, `cancel_turn`, and `review_turn`.
      [ ] 7.1.1.2 Subtask - Preserve product-owned context assembly for actor, session, project, request, correlation, and workspace identifiers across every new wrapper call.
      [ ] 7.1.1.3 Subtask - Keep product code talking only to public `Jido.Os.CodingAssist.Service` and canonical session or directory authorities instead of private coding agents or runtime internals.

    [ ] 7.1.2 Task - Keep compatibility `assist` subordinate to the same public turn runtime
      Preserve migration safety while making sure `assist` no longer acts like a second execution engine with different semantics.

      [ ] 7.1.2.1 Subtask - Keep `assist` available only as a compatibility or convenience path over the same public turn runtime boundary.
      [ ] 7.1.2.2 Subtask - Align error, tracing, and policy context behavior between compatibility `assist` and the new wrapper family.
      [ ] 7.1.2.3 Subtask - Extend boundary tests so callers can verify the wrapper family without depending on conversation-driver entrypoints.

  [ ] 7.2 Section - Conversation Driver Start-Turn Adoption
    Change the coding conversation driver to prefer non-blocking public turn start while preserving the existing ingress, policy, and identity rules that already make conversation part of the factory control loop.

    [ ] 7.2.1 Task - Make non-blocking public turn start the primary conversation execution path
      Replace one-shot compatibility `assist` routing in the driver with explicit turn creation that can be observed, replayed, and governed over time.

      [ ] 7.2.1.1 Subtask - Update `JidoCode.Conversations.Driver` to call the new `JidoCode.CodingAssistance.start_turn` wrapper after policy and ingress succeed.
      [ ] 7.2.1.2 Subtask - Preserve `conversation_id == session_id`, actor propagation, and managed-repo binding behavior when the driver starts a public runtime turn.
      [ ] 7.2.1.3 Subtask - Treat compatibility `assist` as a fallback path only for explicitly limited migration cases rather than the normal driver contract.

    [ ] 7.2.2 Task - Prepare conversation runtime lifecycle for background turn observation
      Make `CodeServer` and surrounding conversation state aware that coding turns now progress asynchronously after admission.

      [ ] 7.2.2.1 Subtask - Persist enough driver metadata to correlate a conversation with the started public turn identity and latest replay cursor.
      [ ] 7.2.2.2 Subtask - Preserve current user-message ingestion ordering so product ingress happens before runtime turn execution begins.
      [ ] 7.2.2.3 Subtask - Keep typed failure behavior explicit when turn start is denied, unavailable, or fails after conversation admission.

  [ ] 7.3 Section - Replay Bridge and Subscriber Contract Preservation
    Bridge the new public turn runtime back into the existing subscriber-facing event model so UI surfaces gain real turn progress without learning `jido_os` transport details.

    [ ] 7.3.1 Task - Add a product-local replay bridge worker
      Make progress delivery work now by polling public replay and terminal read surfaces while downstream live subscription remains additive.

      [ ] 7.3.1.1 Subtask - Add a bridge worker or equivalent runtime loop that polls `list_turn_events` incrementally and reads terminal turn state until completion.
      [ ] 7.3.1.2 Subtask - Track replay cursor, terminal state, and stop conditions per conversation so restart and retry logic remain deterministic.
      [ ] 7.3.1.3 Subtask - Preserve clear boundaries so the bridge can later swap from polling replay to public live subscription without changing subscriber contracts.

    [ ] 7.3.2 Task - Translate public turn projections into the stable conversation event contract
      Keep current subscribers stable while replacing placeholder event fabrication with real projected turn lifecycle behavior.

      [ ] 7.3.2.1 Subtask - Update `JidoCode.Conversations.EventBridge` to translate projected turn progress, tool activity, artifacts, failures, and terminal summaries into the existing event families.
      [ ] 7.3.2.2 Subtask - Preserve `assistant.delta`, `assistant.message`, and typed failure-event compatibility for `CodeServer` subscribers and current LiveView consumers.
      [ ] 7.3.2.3 Subtask - Keep runtime-native payloads, transport framing, and provider-neutral raw envelopes out of subscriber-facing UI contracts.

  [ ] 7.4 Section - Governed Run and Evidence Materialization
    Make terminal coding-turn outcomes durable in product truth by connecting runtime turn identity and outputs back into governed `Run`, `Evidence`, `ChangeRequest`, and `Decision` records.

    [ ] 7.4.1 Task - Carry public turn identity into governed product records
      Preserve a durable join between conversation ingress, runtime execution, and governed outcome records before richer projection work lands.

      [ ] 7.4.1.1 Subtask - Record `turn_id` and related runtime identifiers in conversation ingress metadata, work-item context, and run launch metadata where appropriate.
      [ ] 7.4.1.2 Subtask - Keep the runtime-turn join provider-neutral and scoped to one managed repo, conversation, and work-item lineage.
      [ ] 7.4.1.3 Subtask - Preserve compatibility with existing `WorkflowRun` projection seams while adding the newer turn-aware linkage.

    [ ] 7.4.2 Task - Materialize terminal turn outputs and operator review into governed artifacts
      Ensure final runtime outcomes become governed product evidence rather than remaining visible only through runtime replay.

      [ ] 7.4.2.1 Subtask - Project terminal turn summaries, artifacts, and relevant replay evidence into governed `Run` and `Evidence` records.
      [ ] 7.4.2.2 Subtask - Use public operator review or terminal turn reads to enrich `ChangeRequest` and `Decision` records where reviewable runtime evidence exists.
      [ ] 7.4.2.3 Subtask - Keep product-owned governance records authoritative for operator reporting and rollout decisions even though runtime evidence originates in `jido_os`.

  [ ] 7.5 Section - Phase 7 Integration Tests
    Validate the new wrapper family, non-blocking turn-start conversation path, replay bridge behavior, and governed terminal projection end to end before any later live-subscription swap.

    [ ] 7.5.1 Task - Boundary and conversation-driver scenarios
      Verify the product-owned wrapper and conversation-driver layers adopt the public turn runtime without breaking ingress, policy, or subscriber contracts.

      [ ] 7.5.1.1 Subtask - Add coverage for the new coding-assistance wrapper family and compatibility `assist` alignment over the same public turn runtime.
      [ ] 7.5.1.2 Subtask - Add coverage for conversation-driver start-turn routing with preserved actor context, session identity, ingress ordering, and typed failure outcomes.
      [ ] 7.5.1.3 Subtask - Add coverage for replay-driven subscriber updates using the existing event contract rather than runtime-native payloads.

    [ ] 7.5.2 Task - Governed terminal projection scenarios
      Verify runtime turn progress and completion become durable product truth in the governed execution and review model.

      [ ] 7.5.2.1 Subtask - Add coverage for `turn_id` linkage from conversation ingress into work-item and run metadata.
      [ ] 7.5.2.2 Subtask - Add coverage for terminal turn summaries, artifacts, and review outputs projecting into governed `Run`, `Evidence`, `ChangeRequest`, and `Decision` records.
      [ ] 7.5.2.3 Subtask - Verify the product remains authoritative for operator-visible reports and review flows even while runtime execution remains in `jido_os`.
