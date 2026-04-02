# Phase 11 - Runtime Evidence, Posture, and Rollout Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_service_overlay.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/repo_posture.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.jido_os_runtime_service_overlay_adoption.md`
- `JidoCode.Governance`
- `JidoCode.Governance.PostureBridge`
- `JidoCode.Governance.RunGovernanceBridge`
- `JidoCode.Control.CompatibilityRollout`
- operator-facing dashboard and run-detail surfaces

## Relevant Assumptions / Defaults
- Phases 8 through 10 have introduced runtime gateways, capability posture, live-delivery adoption, and the product-owned integration gateway.
- Runtime outcomes should inform the product’s trust and governance model without making the runtime overlay itself the durable truth store.
- Operator surfaces need explainable rollout and degraded-path evidence rather than runtime-native transport details.

[ ] 11 Phase 11 - Runtime Evidence, Posture, and Rollout Convergence
  Converge coding and integration runtime evidence into product-owned posture, evidence, and operator surfaces so runtime-service rollout, denial, degraded behavior, and operator review become governed factory inputs instead of scattered operational trivia.

  [x] 11.1 Section - Runtime Evidence Materialization
    Capture the runtime-service facts that matter to governance and make them durable product evidence rather than transient UI state.

    [x] 11.1.1 Task - Materialize runtime-service rollout and degraded-path evidence
      Make runtime capability state legible to the factory in the same durable evidence model used for runs, review, and decisions.

      [x] 11.1.1.1 Subtask - Normalize rollout, denial, degraded-path, and detached-path runtime evidence from coding and integration gateways into product evidence or observation records.
      [x] 11.1.1.2 Subtask - Preserve joinable actor, repo, work-item, run, session, turn, and provider references where they affect governance review.
      [x] 11.1.1.3 Subtask - Keep provider-neutral runtime evidence bounded and product-readable without exposing raw runtime-native transport payloads.

    [x] 11.1.2 Task - Connect runtime evidence to posture and decision-making
      Ensure runtime-service quality and rollout state can actually influence how the factory supervises and approves work.

      [x] 11.1.2.1 Subtask - Feed runtime-service evidence into posture, trust, or approval heuristics where appropriate.
      [x] 11.1.2.2 Subtask - Preserve explicit separation between product review decisions and runtime admission or rollout authority.
      [x] 11.1.2.3 Subtask - Keep `Jido.Runic` and governed `Run` records as the execution authority even when runtime evidence becomes richer.

  [ ] 11.2 Section - Operator Surface and Rollout Narrative Convergence
    Make the newer runtime-service model understandable to operators without leaking internal runtime architecture into the product UX.

    [ ] 11.2.1 Task - Surface runtime capability posture and evidence in operator-facing product views
      Give operators a governed, explainable view of runtime-service readiness and degraded behavior where it affects repo supervision.

      [ ] 11.2.1.1 Subtask - Add dashboard or workbench summaries for admitted-service posture, rollout status, and degraded-path evidence.
      [ ] 11.2.1.2 Subtask - Add run- or repo-detail visibility for relevant operator-review joins and runtime evidence when it affects execution trust.
      [ ] 11.2.1.3 Subtask - Keep UI language product-oriented and policy-oriented rather than exposing substrate or authority-topology jargon.

    [ ] 11.2.2 Task - Retire stale narrow runtime-overlay assumptions from product docs and rollout narratives
      Finish the architectural refresh by aligning operator and contributor narratives with the newer runtime-service model.

      [ ] 11.2.2.1 Subtask - Update rollout and compatibility narratives to distinguish product truth from runtime-service posture explicitly.
      [ ] 11.2.2.2 Subtask - Remove remaining doc or UI assumptions that describe `jido_os` only as a coding-turn helper if broader runtime-service adoption is now live.
      [ ] 11.2.2.3 Subtask - Preserve clear rollback and recovery procedures when runtime-service rollout affects ordinary operator workflows.

  [ ] 11.3 Section - Phase 11 Integration Tests
    Validate the final convergence of runtime evidence, posture, and operator-facing rollout behavior so the architecture refresh is complete end to end.

    [ ] 11.3.1 Task - Evidence and posture convergence scenarios
      Verify coding and integration runtime evidence actually rejoin governed product records and trust signals.

      [ ] 11.3.1.1 Subtask - Add coverage for runtime degraded-path and rollout evidence materializing into product evidence or posture records.
      [ ] 11.3.1.2 Subtask - Add coverage for repo-level trust or readiness changes driven by runtime capability posture.
      [ ] 11.3.1.3 Subtask - Add coverage ensuring runtime evidence remains bounded and provider-neutral at the product surface.

    [ ] 11.3.2 Task - Operator-surface and rollout scenarios
      Verify the newer runtime-service model is explainable and safe in operator-facing product behavior.

      [ ] 11.3.2.1 Subtask - Add coverage for dashboard or repo-detail presentation of runtime capability posture and rollout evidence.
      [ ] 11.3.2.2 Subtask - Add coverage for rollback-safe behavior when runtime-service rollout blocks or degrades expected operator workflows.
      [ ] 11.3.2.3 Subtask - Verify planning, spec, and operator-surface traceability close cleanly for the runtime-service overlay implementation roadmap.
