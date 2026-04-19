# Phase 55 - Memory Rollout And Governed Surfaces

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history -->
<!-- covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.dashboard_and_governed_surfaces_host_bounded_memory_context -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.cross_graph_navigation_stays_consistent_across_surfaces -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.memory_aware_workflow_and_governed_follow_up_use_product_projections -->
<!-- covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.spec/planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_graph_workflow_and_operator_expansion.spec.md`
- `../specs/memory_graph_surface_rollout_and_governance_actions.spec.md`
- `../specs/memory_ontology.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_graph_workflow_and_operator_expansion.md`
- `../decisions/jido_code.memory_graph_surface_rollout_and_governance_actions.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/governance/`
- `lib/jido_code/operations/`
- `lib/jido_code_web/live/`
- `lib/jido_code_web/components/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 32 through 34 established repository-detail memory inspection, governed run-detail memory context, product-owned memory actions, and bounded dashboard summaries, but the canonical governed route family is still incomplete because work items, evidence, and decisions do not yet have their own memory-aware product surfaces.
- The remaining proposed memory subjects are now narrower than the earlier rollout plans: most service and action boundaries are already implemented, so this phase is about finishing canonical governed route adoption, keeping navigation and follow-up product-shaped, and then promoting those subjects out of proposal-only status.
- Existing Phase 55 integration coverage already uses `55.6.*` numbering for ontology and governed-reference verification, so this plan keeps Section 55.6 as the final integration section instead of renumbering the shipped coverage.

[ ] 55 Phase 55 - Memory Rollout And Governed Surfaces
  Finish the remaining memory rollout by giving work-item, evidence, and decision records canonical memory-aware governed routes, reusing the product-owned memory action boundary on those routes, promoting the final proposed memory specs to active current truth, and aligning integration coverage with the shipped Phase 55 narrative.

  [x] 55.1 Section - Planning And Chronology Alignment
    Make the phase explicit in the planning workspace so contributors, specs, and higher-numbered coverage all point at the same rollout story before the implementation expands further.

    [x] 55.1.1 Task - Add the missing Phase 55 plan and index entry
      Introduce the current-truth Phase 55 planning document, place it in the planning index, and describe the exact governed-surface rollout that remains after Phases 33, 34, and 54.

      [x] 55.1.1.1 Subtask - Add a Phase 55 planning document with section, task, and subtask structure that follows the shared planning conventions.
      [x] 55.1.1.2 Subtask - Register Phase 55 in the planning index with a short summary that points at governed-surface completion rather than generic memory rollout.
      [x] 55.1.1.3 Subtask - Repair the chronology note so existing `55.6.*` coverage is described as part of this phase instead of as a planning gap.

  [x] 55.2 Section - Canonical Governed Route Foundation
    Establish real canonical product routes for work items, evidence, and decisions so memory-backed governed navigation stops depending on run-detail anchors as its primary route contract.

    [x] 55.2.1 Task - Extend governed routing and typed reference resolution
      Teach the governed-reference and governed-surface helpers how to build canonical routes for work items, evidence, and decisions without falling back to run-detail anchors when a first-class route exists.

      [x] 55.2.1.1 Subtask - Extend governed reference route helpers so work-item, evidence, and decision references resolve to canonical product routes.
      [x] 55.2.1.2 Subtask - Update governed surface context shaping so cross-graph navigation prefers those canonical routes while keeping bounded fallback labels where no route exists.
      [x] 55.2.1.3 Subtask - Preserve repository-scoped route construction and keep run-detail anchors only as explicit fallback behavior where older context still requires them.

    [x] 55.2.2 Task - Add routed LiveView entrypoints for governed detail surfaces
      Introduce the routed LiveView surfaces that will host the new bounded memory context and operator actions for work items, evidence, and decisions.

      [x] 55.2.2.1 Subtask - Add authenticated router entries for canonical work-item, evidence, and decision routes under the managed-repository route family.
      [x] 55.2.2.2 Subtask - Create the initial governed detail LiveViews with canonical loading, not-found handling, and route-local page framing.
      [x] 55.2.2.3 Subtask - Keep route naming, page titles, and fallback messaging aligned with current controlled vocabulary for managed repositories and governed records.

  [x] 55.3 Section - Work-Item Memory Surface Adoption
    Project bounded memory and workflow-provenance context onto the canonical work-item surface so governed work no longer depends on run detail as the only memory-backed operator route.

    [x] 55.3.1 Task - Add product-owned work-item memory context shaping
      Reuse existing memory product services and governed loaders to present bounded work-item memory context through a dedicated work-item route instead of a run-detail section.

      [x] 55.3.1.1 Subtask - Add work-item detail loaders that gather canonical work-item data, related governed run history, and bounded memory context through product-owned services.
      [x] 55.3.1.2 Subtask - Reuse shared memory surface components so work-item memory links, freshness state, and related-governed navigation match the existing product contract.
      [x] 55.3.1.3 Subtask - Keep the work-item route product-owned and explainable when memory is missing, stale, invalidated, or recovering.

    [x] 55.3.2 Task - Reuse bounded memory actions on the work-item route
      Make validation, invalidation, supersession, and promotion available from work-item detail without introducing a route-specific mutation boundary.

      [x] 55.3.2.1 Subtask - Wire work-item memory actions through the existing AgentWorkspace and governed memory action helpers.
      [x] 55.3.2.2 Subtask - Preserve follow-up previews, provenance feedback, and governed adoption metadata on the work-item route.
      [x] 55.3.2.3 Subtask - Keep action feedback and state refresh consistent with the existing run-detail memory interaction model.

  [x] 55.4 Section - Evidence And Decision Memory Surface Adoption
    Finish the governed rollout by giving evidence and decision records their own bounded memory-aware surfaces, consistent navigation, and product-owned operator actions.

    [x] 55.4.1 Task - Add bounded evidence and decision memory context
      Present the same explainable memory, provenance, and related-governed context on evidence and decision routes that operators already see in run detail.

      [x] 55.4.1.1 Subtask - Add product-owned evidence detail loaders that shape evidence, related work, and bounded memory context for the canonical evidence route.
      [x] 55.4.1.2 Subtask - Add product-owned decision detail loaders that shape decision history, related evidence, and bounded memory context for the canonical decision route.
      [x] 55.4.1.3 Subtask - Keep cross-graph navigation repository-scoped and consistent across work-item, evidence, and decision routes.

    [x] 55.4.2 Task - Reuse bounded memory actions and governed follow-up on evidence and decision routes
      Expose the same product-owned memory action boundary and follow-up affordances from the new evidence and decision routes rather than keeping those interactions run-detail-only.

      [x] 55.4.2.1 Subtask - Wire validate, invalidate, supersede, and promote interactions through the shared product-owned memory action path.
      [x] 55.4.2.2 Subtask - Preserve governed follow-up previews and post-action feedback on evidence and decision surfaces.
      [x] 55.4.2.3 Subtask - Keep the route contract canonical and governed instead of introducing graph-first views or raw RDF detail.

  [x] 55.5 Section - Spec And Contributor Convergence
    Bring the remaining proposed subjects and adjacent guidance into alignment once the governed memory surfaces actually exist in the product.

    [x] 55.5.1 Task - Promote the remaining memory rollout specs to current truth
      Reclassify the final proposed memory rollout subjects to active status and update their summaries or verification references so they describe the shipped governed-surface behavior accurately.

      [x] 55.5.1.1 Subtask - Update `memory_graph_workflow_and_operator_expansion` to reflect canonical governed routes and shipped bounded operator memory actions.
      [x] 55.5.1.2 Subtask - Update `memory_graph_surface_rollout_and_governance_actions` to reflect dashboard plus governed-surface rollout as active product behavior.
      [x] 55.5.1.3 Subtask - Keep verification targets aligned with the final route modules, shared components, and Phase 55 coverage.

    [x] 55.5.2 Task - Align planning and contributor guidance with the completed rollout
      Update the planning index and any adjacent contributor-facing guidance so future work sees the governed memory route family as canonical current truth.

      [x] 55.5.2.1 Subtask - Remove or rewrite planning notes that still frame canonical work-item, evidence, and decision memory routes as missing after Phase 55 lands.
      [x] 55.5.2.2 Subtask - Update contributor-facing guidance that references the remaining proposed status of those memory rollout subjects.
      [x] 55.5.2.3 Subtask - Verify planning, specs, and route vocabulary converge on one canonical governed-memory story.

  [x] 55.6 Section - Phase 55 Integration Tests
    Verify the completed rollout through both the existing ontology coverage and new governed-surface route coverage so the phase closes with implementation, docs, and tests aligned.

    [x] 55.6.1 Task - Preserve and align shipped ontology coverage with the Phase 55 narrative
      Keep the existing Phase 55 ontology and governed-reference verification as part of the phase while ensuring the new plan explicitly acknowledges it.

      [x] 55.6.1.1 Subtask - Keep the existing `55.6.*` ontology and governed-reference integration coverage in place as the final phase verification section.
      [x] 55.6.1.2 Subtask - Add any missing assertions needed to keep governed-reference routing coherent once canonical work-item, evidence, and decision routes exist.
      [x] 55.6.1.3 Subtask - Verify the phase narrative and integration file numbering stay aligned after the plan is introduced.

    [x] 55.6.2 Task - Add governed-surface LiveView and integration coverage
      Prove the new work-item, evidence, and decision routes host bounded memory context and product-owned actions without regressing the existing route family.

      [x] 55.6.2.1 Subtask - Add LiveView coverage for canonical work-item, evidence, and decision memory surfaces, including bounded navigation and not-found behavior.
      [x] 55.6.2.2 Subtask - Add coverage proving memory actions on those routes still flow through shared product-owned boundaries and preserve follow-up metadata.
      [x] 55.6.2.3 Subtask - Verify the final proposed memory specs, planning docs, and governed routes now tell the same current-truth story.
