# Phase 27 - Semantic Product Hardening And Contributor Convergence

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/product_foundation_docs.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `README.md`
- `CONTRIBUTING.md`
- `AGENTS.md`
- `lib/jido_code/source_code_graph/`
- `lib/jido_code_web/live/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 24 through 26 have adopted semantic graph capability into product services, operator surfaces, and explicit workflow paths.
- The remaining work is hardening, documentation, and contributor convergence around those product-facing semantic features.
- Semantic product behavior must remain explainable, bounded, and operationally maintainable.

[ ] 27 Phase 27 - Semantic Product Hardening And Contributor Convergence
  Harden the product-facing semantic graph adoption so operator behavior, contributor workflows, and verification surfaces remain durable and understandable.

  [ ] 27.1 Section - Product Hardening And Recovery Convergence
    Strengthen product-facing semantic behavior so operator surfaces and workflow entrypoints stay trustworthy under stale, degraded, and recovery-heavy conditions.

    [ ] 27.1.1 Task - Harden operator-facing recovery and fallback behavior
      Make recovery and degraded semantic behavior consistent across managed-repository surfaces and semantic workflows.

      [ ] 27.1.1.1 Subtask - Standardize semantic stale, degraded, and recovery-required messaging across product surfaces.
      [ ] 27.1.1.2 Subtask - Ensure semantic actions fail safely when graph state is unavailable or stale beyond allowed bounds.
      [ ] 27.1.1.3 Subtask - Ensure operator recovery actions remain product-owned and repo-scoped.

    [ ] 27.1.2 Task - Harden semantic projection and evidence consistency
      Keep semantic product behavior explainable even as more surfaces and workflows reuse the same capability.

      [ ] 27.1.2.1 Subtask - Standardize semantic projection shapes reused across UI and workflow boundaries.
      [ ] 27.1.2.2 Subtask - Standardize provenance and freshness presentation for semantic-derived work and evidence.
      [ ] 27.1.2.3 Subtask - Ensure semantic product behavior remains coherent across multiple repositories with isolated graph state.

  [ ] 27.2 Section - Contributor Workflow And Documentation Convergence
    Align contributor-facing docs and verification paths so the new semantic product capability is maintainable and discoverable.

    [ ] 27.2.1 Task - Update contributor guidance for semantic product features
      Document how contributors should reason about product-owned semantic services, semantic UI, and semantic workflow adoption.

      [ ] 27.2.1.1 Subtask - Update README guidance for product-facing semantic inspection and workflow usage.
      [ ] 27.2.1.2 Subtask - Update contributor instructions for semantic verification expectations and boundaries.
      [ ] 27.2.1.3 Subtask - Clarify when semantic behavior should remain a bounded enhancement rather than a required product dependency.

    [ ] 27.2.2 Task - Align verification surfaces with the semantic product stack
      Make the repo-owned checks and test grouping reflect the new product-facing semantic adoption.

      [ ] 27.2.2.1 Subtask - Add or update repo-owned verification aliases for semantic product surfaces where needed.
      [ ] 27.2.2.2 Subtask - Keep semantic UI, workflow, and governed-finding tests discoverable in contributor guidance.
      [ ] 27.2.2.3 Subtask - Ensure semantic product checks remain compatible with the existing repo quality flow.

  [ ] 27.3 Section - Phase 27 Integration Tests
    Verify the final product-facing semantic adoption remains safe, explainable, and maintainable across operator surfaces, workflow paths, and contributor verification.

    [ ] 27.3.1 Task - Product hardening scenarios
      Prove the semantic product experience remains bounded and recoverable when repository graph state is stale, degraded, or recovering.

      [ ] 27.3.1.1 Subtask - Add coverage proving semantic operator surfaces remain legible under stale or degraded graph conditions.
      [ ] 27.3.1.2 Subtask - Add coverage proving semantic workflow entrypoints fail safely and preserve explicit freshness metadata.
      [ ] 27.3.1.3 Subtask - Add coverage proving multi-repository semantic product behavior stays isolated and consistent.

    [ ] 27.3.2 Task - Contributor and verification convergence scenarios
      Prove the semantic product capability is documented and verifiable through normal repo-owned contributor workflows.

      [ ] 27.3.2.1 Subtask - Add coverage proving semantic product surfaces are included in the intended verification paths.
      [ ] 27.3.2.2 Subtask - Add coverage proving contributor guidance matches the final semantic product architecture.
      [ ] 27.3.2.3 Subtask - Verify the full spec workspace remains coherent after the semantic product-adoption roadmap is complete.
