# Phase 10 - External Runtime Integration Service Adoption

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_service_overlay.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/policy_layers.spec.md`
- `../decisions/jido_code.jido_os_runtime_service_overlay_adoption.md`
- `JidoCode.Control.RepoBridge`
- `JidoCode.Operations.Ingress`
- `JidoCode.Operations.Synthesis`
- public `Jido.Os.Integration.Service`

## Relevant Assumptions / Defaults
- Phase 8 has established a runtime gateway convention and capability-posture model.
- Product control truth remains in managed-repo records, not in external connector or runtime substrate state.
- External SaaS runtime behavior should be additive and repo-scoped rather than becoming a second product control plane.

[ ] 10 Phase 10 - External Runtime Integration Service Adoption
  Introduce repo-scoped external SaaS runtime behavior through a product-owned gateway over `Jido.Os.Integration.Service` and normalize those runtime outcomes back into the managed-repo factory loop instead of scattering connector-specific logic across product setup and UI seams.

  [x] 10.1 Section - Product-Owned Integration Gateway Baseline
    Establish a product boundary over the canonical runtime integration service before any workflow or operator flow depends on it.

    [x] 10.1.1 Task - Add a product-owned integration gateway over public `Jido.Os.Integration.Service`
      Make external runtime integration use the same gateway pattern as coding assistance so product code does not consume raw runtime payloads directly.

      [x] 10.1.1.1 Subtask - Introduce a `jido_code` boundary for install lifecycle, binding reads or writes, provider operation discovery, and invocation.
      [x] 10.1.1.2 Subtask - Preserve explicit actor, project, request, correlation, and workspace context across every runtime integration call.
      [x] 10.1.1.3 Subtask - Keep product callers insulated from connector-native identifiers, adapter details, and substrate-facing runtime shapes.

    [x] 10.1.2 Task - Align runtime integration with managed-repo identity and governance
      Ensure runtime integration behavior is repo-scoped and governed by the same managed-repo model as the rest of the factory.

      [x] 10.1.2.1 Subtask - Resolve managed-repo and transitional project identity into the explicit project-scoped binding context required by the runtime integration boundary.
      [x] 10.1.2.2 Subtask - Preserve typed ambiguity, missing-binding, and unavailable-service behavior at the product boundary.
      [x] 10.1.2.3 Subtask - Keep runtime integration availability and binding health visible as capability posture rather than hidden setup-only state.

  [x] 10.2 Section - Control-Loop Normalization for Integration Outcomes
    Make runtime integration results rejoin the governed factory loop rather than living as detached setup or UI side effects.

    [x] 10.2.1 Task - Normalize integration lifecycle and invocation outcomes into managed-repo control records
      Let external runtime behavior influence the factory through the same durable ingress and interpretation model as other signals.

      [x] 10.2.1.1 Subtask - Translate install, binding, and invocation outcomes into `Observation`, `Intake`, `Event`, or related control records where appropriate.
      [x] 10.2.1.2 Subtask - Preserve actor attribution, repo correlation, provider identity, and typed degraded or denied-path evidence across that normalization.
      [x] 10.2.1.3 Subtask - Avoid inventing product-local shadow connector state when runtime and external substrate already own the execution truth.

    [x] 10.2.2 Task - Connect integration capability posture to repo governance and operator flows
      Make external runtime integration part of governed readiness, not just one-off setup success.

      [x] 10.2.2.1 Subtask - Feed integration capability posture, binding state, and denied-path evidence into repo posture or equivalent governance records.
      [x] 10.2.2.2 Subtask - Prepare operator-facing summaries for integration-backed repo readiness and degraded-path behavior.
      [x] 10.2.2.3 Subtask - Preserve the distinction between runtime integration admission and product-side governance policy decisions.

  [ ] 10.3 Section - Phase 10 Integration Tests
    Validate the new integration gateway and control-loop normalization before external runtime behavior becomes part of ordinary managed-repo operations.

    [ ] 10.3.1 Task - Integration gateway scenarios
      Verify repo-scoped external runtime behavior routes through the new product-owned boundary and preserves typed context.

      [ ] 10.3.1.1 Subtask - Add coverage for install-session, binding, and invocation calls through the product-owned gateway.
      [ ] 10.3.1.2 Subtask - Add coverage for explicit project-scoped identity, alias/default behavior, and typed ambiguity outcomes.
      [ ] 10.3.1.3 Subtask - Add coverage ensuring connector-native identifiers do not become product contracts.

    [ ] 10.3.2 Task - Control-loop and governance scenarios
      Verify runtime integration outcomes are normalized into the managed-repo factory loop and governance state cleanly.

      [ ] 10.3.2.1 Subtask - Add coverage for observation or event synthesis from runtime integration outcomes.
      [ ] 10.3.2.2 Subtask - Add coverage for integration capability posture informing repo readiness or posture.
      [ ] 10.3.2.3 Subtask - Verify planning, spec, and integration test traceability for the new integration-service adoption path.
