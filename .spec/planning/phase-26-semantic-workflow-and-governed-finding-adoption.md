# Phase 26 - Semantic Workflow And Governed Finding Adoption

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/factory_control_plane.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `../specs/run_governance.spec.md`
- `../decisions/jido_code.source_code_graph_product_adoption.md`
- `lib/jido_code/source_code_graph/`
- `lib/jido_code/operations/`
- `lib/jido_code/governance/`
- `lib/jido_code/workbench/`
- `lib/jido_code/agent_workspace.ex`
- `test/jido_code/`

## Relevant Assumptions / Defaults
- Phase 24 provides product-owned semantic services and explicit semantic finding materialization helpers.
- Phase 25 makes semantic repository inspection visible on operator surfaces.
- Planning, review, and explanation flows may benefit from semantic context, but only when explicitly requested.
- Any semantic finding that changes product behavior must rejoin governed records.

[ ] 26 Phase 26 - Semantic Workflow And Governed Finding Adoption
  Adopt the source-code graph into planning, review, and governed work creation flows so semantic findings can inform the factory without becoming an alternate truth system.

  [ ] 26.1 Section - Explicit Semantic Workflow Inputs
    Add bounded semantic inputs to product-owned workflow entrypoints so planning, review, and explanation can opt into graph-backed context explicitly.

    [ ] 26.1.1 Task - Add semantic context options to workflow entrypoints
      Extend product-owned workflow surfaces to request graph preparation and bounded semantic projections intentionally.

      [ ] 26.1.1.1 Subtask - Add explicit semantic options to planning flows.
      [ ] 26.1.1.2 Subtask - Add explicit semantic options to review and explanation flows.
      [ ] 26.1.1.3 Subtask - Ensure non-semantic workflow calls remain valid and do not depend on ambient graph state.

    [ ] 26.1.2 Task - Shape workflow semantic inputs as bounded product data
      Keep workflow-facing semantic inputs understandable and decoupled from graph-engine internals.

      [ ] 26.1.2.1 Subtask - Define workflow semantic input maps for modules, functions, runtime patterns, and impact traces.
      [ ] 26.1.2.2 Subtask - Include graph freshness, stale, or degraded metadata in workflow semantic inputs.
      [ ] 26.1.2.3 Subtask - Prevent workflow callers from depending on raw SPARQL or pod-native result shapes.

  [ ] 26.2 Section - Governed Semantic Finding Adoption
    Materialize meaningful semantic outcomes into durable control-plane records when they should influence follow-up work or review.

    [ ] 26.2.1 Task - Add semantic finding to work conversion flows
      Let operators and product workflows turn semantic findings into governed work or review inputs explicitly.

      [ ] 26.2.1.1 Subtask - Add bounded conversion from semantic findings into WorkItem seed input.
      [ ] 26.2.1.2 Subtask - Add bounded conversion from semantic findings into Evidence or review support material.
      [ ] 26.2.1.3 Subtask - Preserve semantic provenance and freshness on all converted outputs.

    [ ] 26.2.2 Task - Keep semantic adoption under product governance
      Ensure semantic finding adoption is visible, reviewable, and compatible with the managed-repository control loop.

      [ ] 26.2.2.1 Subtask - Route semantic-derived work creation through normal product intake and work synthesis paths where appropriate.
      [ ] 26.2.2.2 Subtask - Keep semantic-derived evidence visible alongside other governed run and review artifacts.
      [ ] 26.2.2.3 Subtask - Prevent graph-local findings from mutating governed records without explicit product actions.

  [ ] 26.3 Section - Phase 26 Integration Tests
    Verify semantic context and semantic-finding adoption improve product workflows through explicit, governed paths only.

    [ ] 26.3.1 Task - Explicit workflow semantic context scenarios
      Prove planning, review, and explanation flows only receive semantic inputs when they ask for them and that those inputs remain bounded.

      [ ] 26.3.1.1 Subtask - Add coverage proving planning flows can opt into semantic repository context explicitly.
      [ ] 26.3.1.2 Subtask - Add coverage proving review and explanation flows can use semantic context without direct graph coupling.
      [ ] 26.3.1.3 Subtask - Add coverage proving non-semantic workflow calls remain free of hidden graph dependencies.

    [ ] 26.3.2 Task - Governed semantic finding scenarios
      Prove semantic findings only influence product behavior after explicit adoption into governed records.

      [ ] 26.3.2.1 Subtask - Add coverage proving semantic findings can become governed work input explicitly.
      [ ] 26.3.2.2 Subtask - Add coverage proving semantic findings can become review evidence with provenance and freshness retained.
      [ ] 26.3.2.3 Subtask - Verify the control-plane and source-graph specs remain coherent after workflow adoption.
