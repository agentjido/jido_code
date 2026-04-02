# Phase 8 - Runtime Gateway Foundation and Capability Posture

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/runtime_service_overlay.spec.md`
- `../specs/coding_assistance_boundary.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.jido_os_runtime_service_overlay_adoption.md`
- `JidoCode.JidoOsRuntime`
- `JidoCode.CodingAssistance`
- public `Jido.Os.*` service facades

## Relevant Assumptions / Defaults
- Phases 1 through 7 are complete and already moved the product onto the managed-repo control plane plus the public coding-turn seam.
- `jido_os` now exposes a broader authority-backed runtime-services model with optional admitted services beyond coding turns alone.
- `jido_code` must preserve product-owned contracts and durable governance truth while integrating with those richer runtime services.

[ ] 8 Phase 8 - Runtime Gateway Foundation and Capability Posture
  Reframe product integration around runtime-service gateways instead of one-off runtime seams by introducing explicit product-owned gateway conventions, runtime capability posture reads, and typed admitted-service availability that product governance can understand.

  [x] 8.1 Section - Runtime Gateway Layer Baseline
    Establish the product-owned boundary pattern that all future `jido_os` runtime-service adoption should follow.

    [x] 8.1.1 Task - Define the product-owned runtime gateway convention
      Make runtime-service adoption in `jido_code` consistent so product code depends on stable product boundaries rather than raw runtime payloads or topology assumptions.

      [x] 8.1.1.1 Subtask - Introduce a clear module and naming pattern for product-owned gateways over public `Jido.Os.*` facades.
      [x] 8.1.1.2 Subtask - Keep `JidoCode.CodingAssistance` aligned to that gateway pattern without changing its caller-visible role as the coding entry boundary.
      [x] 8.1.1.3 Subtask - Document and enforce that UI, workbench, and control-plane flows do not bind to runtime pid, substrate, signal-bus, or private authority details.

    [x] 8.1.2 Task - Harden `JidoCode.JidoOsRuntime` as the runtime bootstrap and admission helper
      Move runtime bootstrap and service-admission introspection into one product-owned helper so later gateway work shares one canonical starting point.

      [x] 8.1.2.1 Subtask - Add typed helpers for instance readiness and admitted-service availability checks where public runtime APIs support them.
      [x] 8.1.2.2 Subtask - Keep development and test default seeding explicit and isolated from production runtime assumptions.
      [x] 8.1.2.3 Subtask - Preserve actor, request, correlation, session, project, and workspace context construction as product-owned behavior rather than scattering it across gateway callers.

  [x] 8.2 Section - Runtime Capability Posture and Typed Availability
    Make admitted-service state visible to the product as governed input instead of hidden incidental failure.

    [x] 8.2.1 Task - Add typed runtime capability posture reads
      Give the product a stable way to know whether runtime services are admitted, withheld, denied, unavailable, or degraded before higher-level flows guess from transport failures.

      [x] 8.2.1.1 Subtask - Define the product-local capability posture shape for runtime-service availability, rollout source, denial reason, and degraded-path evidence.
      [x] 8.2.1.2 Subtask - Source that posture from public runtime service outcomes or public admission surfaces rather than private runtime registries.
      [x] 8.2.1.3 Subtask - Ensure capability posture remains additive and typed even when a service is entirely absent for an instance.

    [x] 8.2.2 Task - Feed runtime capability posture into product governance
      Make runtime-service availability part of the factory’s governed understanding of repo readiness and operator trust.

      [x] 8.2.2.1 Subtask - Normalize capability posture into product observations, posture checks, or equivalent governance records where it affects repo readiness.
      [x] 8.2.2.2 Subtask - Preserve the distinction between product governance policy and runtime admission policy while still making their interaction legible.
      [x] 8.2.2.3 Subtask - Prepare operator-facing summaries so later dashboard and workbench work can surface admitted-service state without exposing runtime-native protocols.

  [ ] 8.3 Section - Phase 8 Integration Tests
    Validate the runtime-gateway baseline and capability-posture adoption before later live-delivery and integration-service work layers on more runtime complexity.

    [ ] 8.3.1 Task - Runtime gateway contract scenarios
      Verify product-owned gateways remain the only caller-facing runtime seam even as runtime capability posture becomes richer.

      [ ] 8.3.1.1 Subtask - Add integration coverage for runtime bootstrap, context construction, and admitted-service availability reads through product-owned helpers.
      [ ] 8.3.1.2 Subtask - Add coverage showing coding flows still route through product gateways rather than raw runtime topology.
      [ ] 8.3.1.3 Subtask - Add coverage for typed unavailable, withheld, denied, and degraded capability posture paths.

    [ ] 8.3.2 Task - Governance integration scenarios
      Verify runtime capability posture can inform product governance without collapsing product and runtime authority layers.

      [ ] 8.3.2.1 Subtask - Add coverage for posture or observation materialization from runtime capability state.
      [ ] 8.3.2.2 Subtask - Add coverage for actor-aware governance handling when runtime admission differs from product-side allowance.
      [ ] 8.3.2.3 Subtask - Verify spec and planning traceability remain aligned for the new runtime-gateway baseline.
