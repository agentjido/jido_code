# Phase 24 - Source Code Graph Product Service Foundation

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `../decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/source_code_graph/`
- `lib/jido_code/workbench/`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phases 20 through 23 have already established the repository-scoped SourceCodeGraphPod, full ontology load, query tools, and hardening behavior.
- The next step is product adoption, not deeper graph-runtime expansion.
- Managed-repository routes remain the canonical product host for semantic repository features.
- Product code should consume semantic capability through bounded product-owned services over `AgentWorkspace`.
- Semantic outputs only matter to factory behavior once they rejoin governed product records.

[ ] 24 Phase 24 - Source Code Graph Product Service Foundation
  Establish the product-owned semantic service and view-model boundaries that let managed-repository features consume source-code graph capability without leaking pod, SPARQL, or store internals.

  [ ] 24.1 Section - Product-Owned Semantic Service Boundary
    Create the product-layer service and shaping boundaries that sit between operator features and the repository-scoped semantic runtime capability.

    [ ] 24.1.1 Task - Introduce product-owned semantic service modules
      Define the product-facing service modules that wrap AgentWorkspace semantic entrypoints and return product-shaped semantic summaries.

      [ ] 24.1.1.1 Subtask - Add a repository-scoped semantic service boundary for modules, functions, runtime patterns, and bounded impact lookups.
      [ ] 24.1.1.2 Subtask - Ensure the service returns product-shaped maps and typed outcomes instead of raw SPARQL rows or pod metadata.
      [ ] 24.1.1.3 Subtask - Keep stale, degraded, and recovery-required states explicit in the service contract.

    [ ] 24.1.2 Task - Add semantic view-model shaping
      Introduce bounded semantic view-model helpers so LiveViews and widgets can render semantic repository data without reimplementing graph result shaping ad hoc.

      [ ] 24.1.2.1 Subtask - Define bounded projections for semantic repository summaries and result groups.
      [ ] 24.1.2.2 Subtask - Define freshness, stale-state, degraded, and recovery affordance shaping for operator-facing surfaces.
      [ ] 24.1.2.3 Subtask - Ensure semantic view-models remain repo-scoped and managed-repo-first in naming and identifiers.

  [ ] 24.2 Section - Governed Semantic Finding Materialization
    Define how semantic findings leave the runtime/service layer and rejoin governed product records when they matter to the factory.

    [ ] 24.2.1 Task - Introduce semantic finding materialization helpers
      Add product-owned helpers that can turn meaningful semantic results into governed observations, assessments, evidence, or work input.

      [ ] 24.2.1.1 Subtask - Define a bounded semantic-finding structure that records repository, revision, freshness, and query provenance.
      [ ] 24.2.1.2 Subtask - Define how semantic findings become Observation or Assessment records when they are operator-meaningful but not yet actionable work.
      [ ] 24.2.1.3 Subtask - Define how semantic findings become WorkItem seed input or Evidence when they should influence planning or review.

    [ ] 24.2.2 Task - Keep materialization governed and optional
      Ensure semantic findings never silently become durable business truth and only rejoin the control plane through explicit product actions.

      [ ] 24.2.2.1 Subtask - Require explicit product entrypoints for semantic-finding materialization.
      [ ] 24.2.2.2 Subtask - Preserve semantic freshness and degradation metadata on any materialized finding.
      [ ] 24.2.2.3 Subtask - Keep graph-local runtime facts separate from Ash-backed governed records unless materialization is requested.

  [ ] 24.3 Section - Phase 24 Integration Tests
    Verify the new product-owned semantic boundary is repository-scoped, bounded, and control-plane aligned before any browser surface begins depending on it.

    [ ] 24.3.1 Task - Product service boundary scenarios
      Prove semantic product services return product-shaped, bounded outcomes without leaking runtime internals.

      [ ] 24.3.1.1 Subtask - Add coverage proving module, function, runtime-pattern, and impact lookups return product-shaped semantic projections.
      [ ] 24.3.1.2 Subtask - Add coverage proving stale, degraded, and recovery-required states remain explicit at the product boundary.
      [ ] 24.3.1.3 Subtask - Add coverage proving direct pod or raw SPARQL access is not required by product-owned callers.

    [ ] 24.3.2 Task - Governed materialization scenarios
      Prove semantic findings only influence the factory after explicit materialization into governed records.

      [ ] 24.3.2.1 Subtask - Add coverage proving semantic findings can become bounded Observation or Assessment inputs.
      [ ] 24.3.2.2 Subtask - Add coverage proving semantic findings can become governed work or evidence inputs when explicitly requested.
      [ ] 24.3.2.3 Subtask - Verify the product and spec workspace remain coherent after adding the product semantic service layer.
