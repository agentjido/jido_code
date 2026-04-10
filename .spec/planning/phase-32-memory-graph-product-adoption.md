# Phase 32 - Memory Graph Product Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/frontend_architecture.spec.md`
- `../specs/package.spec.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/workbench/`
- `lib/jido_code_web/live/`
- `lib/jido_code_web/components/`
- `test/jido_code/`
- `test/jido_code_web/live/`

## Relevant Assumptions / Defaults
- Phases 28 through 31 have established the runtime memory-graph foundation, capture plane, durable memory adoption, and product-safe recovery behavior.
- The remaining work is to adopt durable memory and workflow provenance into canonical product-owned services, managed-repository surfaces, and governed workflow follow-up paths.
- Memory and provenance must remain bounded, explainable, freshness-aware, and cross-linked to `source_code` and governed product records without exposing raw graph internals.

[x] 32 Phase 32 - Memory Graph Product Adoption
  Adopt the repository-scoped memory and workflow-provenance graphs into canonical managed-repository product services and operator surfaces so durable memory becomes explorable, actionable, and product-owned.

  [x] 32.1 Section - Product-Owned Memory Service And Cross-Graph Navigation Foundation
    Establish the product-owned service, feedback, and view-model boundary that turns memory-graph capability into a reusable product service instead of a runtime-only helper.

    [x] 32.1.1 Task - Add the bounded memory product service surface
      Introduce canonical product-facing service helpers over AgentWorkspace for repository memory status, memory recall, provenance recall, and bounded recovery behavior.

      [x] 32.1.1.1 Subtask - Add a product-owned memory service boundary that exposes bounded recall, status, and recovery entrypoints over AgentWorkspace.
      [x] 32.1.1.2 Subtask - Add memory and provenance view-model shaping that hides raw graph-engine details from product callers.
      [x] 32.1.1.3 Subtask - Keep freshness, validation, invalidation, stale, and latest-failure metadata explicit in the bounded product service response.

    [x] 32.1.2 Task - Add bounded cross-graph navigation support
      Let product services move safely among durable memory, workflow provenance, source-code entities, and governed product records.

      [x] 32.1.2.1 Subtask - Add bounded cross-graph navigation helpers for moving from memory or provenance to repository code anchors.
      [x] 32.1.2.2 Subtask - Add bounded cross-graph navigation helpers for moving from memory or provenance to governed product records when available.
      [x] 32.1.2.3 Subtask - Ensure cross-graph navigation remains repository-scoped and explainable under stale or degraded dependency state.

  [x] 32.2 Section - Managed-Repository Operator Surface Adoption
    Adopt memory history, decision history, validation state, and workflow provenance into canonical managed-repository operator surfaces without creating a separate graph browser application.

    [x] 32.2.1 Task - Add repo detail memory and provenance inspection
      Extend canonical managed-repository routes so operators can inspect bounded repository memory and provenance through product-owned projections.

      [x] 32.2.1.1 Subtask - Add managed-repository memory inspection regions for durable memory classes such as decisions, conventions, known issues, and lessons learned.
      [x] 32.2.1.2 Subtask - Add bounded workflow-provenance inspection regions for sessions, reviews, plans, patches, and validation history.
      [x] 32.2.1.3 Subtask - Keep LiveView as the route shell while using bounded hybrid regions only where richer timeline or cross-graph exploration is clearly useful.

    [x] 32.2.2 Task - Harden operator memory affordances
      Make the product-facing memory experience safe and explainable when memory state is stale, invalidated, degraded, or recovering.

      [x] 32.2.2.1 Subtask - Standardize memory freshness, validation, invalidation, and recovery messaging across operator surfaces.
      [x] 32.2.2.2 Subtask - Expose bounded operator actions for recovery, refresh, and governed follow-up without leaking raw graph internals.
      [x] 32.2.2.3 Subtask - Ensure multi-repository product surfaces keep memory and provenance isolated even when multiple repositories are open in one session.

  [x] 32.3 Section - Workflow And Governed Follow-Up Adoption
    Let planning, review, explanation, and governed workflow paths request memory context explicitly and turn bounded memory findings into canonical product follow-up.

    [x] 32.3.1 Task - Add explicit memory-aware workflow entrypoints
      Extend product-owned workflow boundaries so they can request durable memory and provenance context intentionally rather than assuming it ambiently.

      [x] 32.3.1.1 Subtask - Add explicit options for planning, review, and explanation flows to request memory context.
      [x] 32.3.1.2 Subtask - Ensure workflow consumers receive bounded memory/provenance projections instead of raw graph query output.
      [x] 32.3.1.3 Subtask - Keep workflow behavior safe when memory state is stale, invalidated, unavailable, or recovering.

    [x] 32.3.2 Task - Adopt memory findings into governed product action paths
      Give operators and workflow services a canonical way to act on durable memory and provenance findings through governed product records.

      [x] 32.3.2.1 Subtask - Add bounded governed-adoption helpers that can turn memory findings into observation, assessment, work, evidence, or decision inputs.
      [x] 32.3.2.2 Subtask - Preserve freshness, validation, invalidation, and provenance metadata when memory findings rejoin governed product records.
      [x] 32.3.2.3 Subtask - Ensure durable memory remains a semantic support layer rather than an alternate product system of record.

  [x] 32.4 Section - Phase 32 Integration Tests
    Verify the product-facing memory-graph adoption remains bounded, explainable, and cross-linked across product services, operator surfaces, workflow entrypoints, and governed follow-up.

    [x] 32.4.1 Task - Product service and operator-surface scenarios
      Prove memory and provenance inspection work through canonical managed-repository surfaces without exposing raw graph internals.

      [x] 32.4.1.1 Subtask - Add coverage proving bounded memory and provenance projections appear through product-owned service and route boundaries.
      [x] 32.4.1.2 Subtask - Add coverage proving freshness, invalidation, degradation, and recovery remain explicit in operator memory surfaces.
      [x] 32.4.1.3 Subtask - Add coverage proving cross-graph navigation between memory, provenance, and source-code anchors remains repository-scoped and explainable.

    [x] 32.4.2 Task - Workflow and governed-follow-up scenarios
      Prove memory context and memory-derived follow-up actions re-enter the product safely and explicitly.

      [x] 32.4.2.1 Subtask - Add coverage proving planning, review, and explanation request memory context only when explicitly asked.
      [x] 32.4.2.2 Subtask - Add coverage proving governed follow-up preserves memory freshness and provenance metadata.
      [x] 32.4.2.3 Subtask - Verify the full spec workspace remains coherent after memory product adoption is added to the roadmap.
