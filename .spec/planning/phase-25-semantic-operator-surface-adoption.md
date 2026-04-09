# Phase 25 - Semantic Operator Surface Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `../decisions/jido_code.live_vue_frontend_adoption.md`
- `lib/jido_code/source_code_graph/`
- `lib/jido_code/workbench/`
- `lib/jido_code_web/live/`
- `lib/jido_code_web/components/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phase 24 provides the product-owned semantic service and view-model layer needed by browser surfaces.
- Managed-repository routes remain the canonical host for semantic inspection.
- LiveView remains the routed shell, while `live_vue` may power richer semantic inspection regions where it adds value.
- Product surfaces must show semantic freshness, degradation, and recovery explicitly.

[ ] 25 Phase 25 - Semantic Operator Surface Adoption
  Adopt the source-code graph into managed-repository operator surfaces so operators can inspect semantic repository structure and bounded impact through normal product routes.

  [ ] 25.1 Section - Managed-Repository Semantic Inspection Surfaces
    Add semantic inspection to the canonical managed-repository operator experience rather than creating a separate graph-only UI.

    [ ] 25.1.1 Task - Add semantic repository summary surfaces
      Introduce semantic summary regions for repository structure and runtime patterns inside managed-repository operator routes.

      [ ] 25.1.1.1 Subtask - Add bounded semantic summaries to the repository detail surface.
      [ ] 25.1.1.2 Subtask - Add semantic freshness, stale-state, and failure messaging to the same route.
      [ ] 25.1.1.3 Subtask - Add explicit recovery actions owned by the product surface rather than raw graph maintenance controls.

    [ ] 25.1.2 Task - Add richer semantic exploration regions where justified
      Use bounded LiveView-hosted `live_vue` regions when richer semantic inspection materially improves the operator experience.

      [ ] 25.1.2.1 Subtask - Add a bounded semantic exploration region for module/function browsing or impact exploration.
      [ ] 25.1.2.2 Subtask - Keep the LiveView shell authoritative for route state, auth, and server-authored data.
      [ ] 25.1.2.3 Subtask - Ensure fallback behavior remains product-oriented when richer semantic delivery degrades.

  [ ] 25.2 Section - Cross-Surface Semantic Operator Consistency
    Align semantic repository behavior across dashboard, workbench, and repo detail so operators do not encounter conflicting graph state or action patterns.

    [ ] 25.2.1 Task - Reuse semantic freshness and recovery presentation
      Standardize how semantic readiness and degraded state are shown across the product’s operator surfaces.

      [ ] 25.2.1.1 Subtask - Reuse shared operator-state patterns for semantic freshness, stale, degraded, and recovery-required views.
      [ ] 25.2.1.2 Subtask - Ensure semantic summaries do not invent alternate route or identifier vocabulary.
      [ ] 25.2.1.3 Subtask - Keep semantic inspection bounded to managed-repository product surfaces rather than global product dashboards unless explicitly repo-scoped.

    [ ] 25.2.2 Task - Keep semantic UI bounded and explainable
      Prevent semantic inspection from leaking graph-engine concepts or becoming a second product truth lane.

      [ ] 25.2.2.1 Subtask - Avoid exposing raw SPARQL, TripleStore handles, or pod internals in operator UI.
      [ ] 25.2.2.2 Subtask - Present semantic results as bounded product concepts such as modules, functions, runtime patterns, and impact groupings.
      [ ] 25.2.2.3 Subtask - Keep any semantic action affordances tied to explicit managed-repository context and visible graph freshness.

  [ ] 25.3 Section - Phase 25 Integration Tests
    Verify semantic operator adoption through canonical managed-repository routes, with bounded hybrid behavior and explicit semantic health state.

    [ ] 25.3.1 Task - Managed-repository semantic inspection scenarios
      Prove operators can inspect semantic repository data through normal product routes without graph-only side channels.

      [ ] 25.3.1.1 Subtask - Add coverage proving repo detail hosts bounded semantic summaries and recovery affordances.
      [ ] 25.3.1.2 Subtask - Add coverage proving semantic freshness and stale-state remain visible and accurate on those surfaces.
      [ ] 25.3.1.3 Subtask - Add coverage proving semantic UI uses managed-repository routes and product-owned identifiers only.

    [ ] 25.3.2 Task - Hybrid semantic region scenarios
      Prove richer semantic exploration can use bounded `live_vue` regions without displacing the LiveView host shell.

      [ ] 25.3.2.1 Subtask - Add coverage proving semantic exploration regions mount through the product-owned LiveVue boundary.
      [ ] 25.3.2.2 Subtask - Add coverage proving degraded frontend delivery falls back safely to LiveView-owned behavior.
      [ ] 25.3.2.3 Subtask - Verify the frontend and product specs remain coherent after semantic operator-surface adoption.
