# Product Foundation Docs

<!-- current_truth.reconciled_with_branch: contributor-facing product orientation remains aligned with the branch-wide setup, graph, and workflow surface changes, including README and CONTRIBUTING guidance that now names repo detail as the canonical conversation host, keeps runtime readiness plus degraded continuity visible in the routed shell, and explicitly describes `/welcome`, `/setup`, `/dashboard`, and `/settings/auth` as the current routed entry model. -->

This subject defines the repository-facing docs that orient contributors to what
`Jido.Code` is, how to run it, and where the durable architecture record now lives.

```spec-meta
id: docs.product_foundation
kind: feature
status: active
summary: Jido.Code keeps a quickstart-oriented top-level README, including the approved frontend-stack, repo-owned `mix server` start path, semantic source-code and memory-graph orientation, verification guidance for contributors, the current `/welcome` to `/setup` to `/dashboard` and `/settings/auth` route ownership model, and the repo-owned onboarding reset commands used during local bootstrap iteration, while durable architecture and product-shaping guidance live in the repo-local `.spec` workspace and adjacent contributor guides, including a derived developer architecture guide set under `docs/developer/` that starts with Spec Led Development orientation, points back to `.spec` as current truth, keeps the source-code graph boundary overview separate from a follow-on ontology-and-query explainer for contributors, keeps the memory-graph boundary overview separate from follow-on durable-memory and workflow-provenance ontology explainers for contributors, and reflects the semantic product verification expectations now carried in `CONTRIBUTING.md` and `AGENTS.md`.
decisions:
  - jido_code.compatibility_era_removal_and_canonical_cutover
  - jido_code.internal_domain_and_execution_canonicalization
  - jido_code.namespace_and_control_naming
  - jido_code.local_developer_workflow
  - jido_code.canonical_repo_surface
  - jido_code.internal_cleanup_and_ui_convergence_foundation
  - jido_code.live_vue_frontend_adoption
  - jido_code.jido_os_deprecation
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
  - jido_code.source_code_graph_product_adoption
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  - README.md
  - CONTRIBUTING.md
  - AGENTS.md
  - docs/developer/README.md
  - docs/developer/
  - .spec/README.md
  - .spec/decisions/jido_code.factory_control_plane.md
  - .spec/decisions/jido_code.internal_cleanup_and_ui_convergence_foundation.md
  - .spec/decisions/jido_code.live_vue_frontend_adoption.md
  - .spec/decisions/jido_code.jido_os_deprecation.md
  - .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  - .spec/decisions/jido_code.source_code_graph_product_adoption.md
  - .spec/decisions/jido_code.runic_execution_model.md
  - .spec/decisions/jido_code.vsm_recursion_and_scope.md
  - tauri/README.md
```

## Requirements

```spec-requirements
- id: docs.product_foundation.readme_quickstart_present
  statement: The top-level README shall give contributors a quickstart for the normal host-Postgres Phoenix workflow.
  priority: must
  stability: evolving

- id: docs.product_foundation.product_summary_present
  statement: The top-level README shall explain what Jido.Code currently contains and frame the repo as the primary implementation surface.
  priority: must
  stability: evolving

- id: docs.product_foundation.readme_frontend_stack_orientation_present
  statement: The top-level README shall explain the approved LiveView-plus-LiveVue browser stack and the repo-owned frontend verification path in contributor terms.
  priority: should
  stability: evolving

- id: docs.product_foundation.readme_source_graph_orientation_present
  statement: The top-level README shall explain the repository-scoped semantic source-code graph capability, its explicit analyze/load/refresh/query lifecycle, and the repo-owned verification path for that stack in contributor terms.
  priority: should
  stability: evolving

- id: docs.product_foundation.durable_architecture_record_in_spec_workspace
  statement: Durable architecture and product-shaping decisions shall live in the repo-local `.spec` workspace rather than in a separate root `docs/` tree.
  priority: must
  stability: evolving

- id: docs.product_foundation.docs_index_present
  statement: The repository shall expose the adjacent contributor and explanatory developer guides through the top-level README, including the repo-local spec workflow, the derived `docs/developer/` guide set, the separate desktop packaging guide, and the direct Mix-based CLI surfaces.
  priority: must
  stability: stable

- id: docs.product_foundation.spec_led_intro_guide_present
  statement: The derived `docs/developer/` guide set shall begin with a guide that explains the repo-local `spec_led_ex` workflow, the `.spec` workspace structure, and drift-control expectations while keeping `.spec/planning/` explicitly optional for contributors.
  priority: should
  stability: evolving

- id: docs.product_foundation.source_code_ontology_guide_present
  statement: The derived `docs/developer/` guide set shall include a follow-on guide after the source-code graph boundary overview that explains the ontology layers loaded into the repository-scoped `source_code` graph, the kinds of repository facts normally present there, and example bounded-helper or explicit-SPARQL queries contributors can use to inspect that semantic content.
  priority: should
  stability: evolving

- id: docs.product_foundation.memory_ontology_guide_present
  statement: The derived `docs/developer/` guide set shall include a follow-on guide after the memory-graph boundary overview that explains the coding-memory ontology used for the repository-scoped `memory` graph, the durable memory, freshness, evidence, and governed-link content normally present there, and example bounded-helper or explicit-SPARQL queries contributors can use to inspect that semantic content.
  priority: should
  stability: evolving

- id: docs.product_foundation.workflow_provenance_ontology_guide_present
  statement: The derived `docs/developer/` guide set shall include a follow-on guide after the memory-graph boundary overview that explains the ontology concepts used for the repository-scoped `workflow_provenance` graph, the kinds of session, run, tool, artifact, and governed-link facts normally present there, and example bounded-helper or explicit-SPARQL queries contributors can use to inspect that provenance content.
  priority: should
  stability: evolving
```

## Scenarios

```spec-scenarios
- id: docs.product_foundation.scenario.new_contributor_reads_foundation
  covers:
    - docs.product_foundation.readme_quickstart_present
    - docs.product_foundation.product_summary_present
    - docs.product_foundation.readme_frontend_stack_orientation_present
    - docs.product_foundation.readme_source_graph_orientation_present
    - docs.product_foundation.durable_architecture_record_in_spec_workspace
  given:
    - A contributor wants to understand what Jido.Code is trying to build before editing implementation code.
  when:
    - The contributor reads the repo-facing guides.
  then:
    - The contributor gets a fast local startup path from the README and can follow links into the repo-local spec workspace for the durable architecture record without requiring code spelunking.

- id: docs.product_foundation.scenario.docs_are_discoverable
  covers:
    - docs.product_foundation.docs_index_present
  given:
    - A contributor starts from the repository README.
  when:
    - The contributor looks for the adjacent contributor and architecture guides.
  then:
    - The README links the spec workspace, contributor guide, derived developer architecture guide set, and separate desktop runtime guide directly.

- id: docs.product_foundation.scenario.developer_guides_start_with_spec_led_orientation
  covers:
    - docs.product_foundation.spec_led_intro_guide_present
  given:
    - A contributor starts from the developer guide set instead of from the top-level README.
  when:
    - The contributor follows the documented reading order.
  then:
    - The first guide explains the repo-local Spec Led Development workflow, the `.spec` workspace layout, and the anti-drift loop without making `.spec/planning/` mandatory.

- id: docs.product_foundation.scenario.source_code_graph_guides_cover_boundary_and_content
  covers:
    - docs.product_foundation.source_code_ontology_guide_present
  given:
    - A contributor wants to understand the repository-scoped source-code graph after learning the high-level architecture.
  when:
    - The contributor follows the developer guide reading order through the source-code graph section.
  then:
    - One guide explains the repo-scoped boundary, lifecycle, and product-owned service surface.
    - A follow-on guide explains the loaded ontology layers, the semantic content available in the graph, and concrete query examples.

- id: docs.product_foundation.scenario.memory_graph_guides_cover_boundary_and_content
  covers:
    - docs.product_foundation.memory_ontology_guide_present
    - docs.product_foundation.workflow_provenance_ontology_guide_present
  given:
    - A contributor wants to understand repository memory and workflow provenance after learning the high-level architecture.
  when:
    - The contributor follows the developer guide reading order through the memory-graph section.
  then:
    - One guide explains the shared repo-scoped boundary, lifecycle, and product-owned service surface.
    - A follow-on guide explains the durable-memory ontology, durable-memory content, freshness/evidence structure, and concrete query examples for the `memory` graph.
    - A second follow-on guide explains the workflow-provenance ontology, session/run/artifact content, and concrete query examples for the `workflow_provenance` graph.
```

## Verification

```spec-verification
- kind: source_file
  target: README.md
  covers:
    - docs.product_foundation.readme_quickstart_present
    - docs.product_foundation.product_summary_present
    - docs.product_foundation.readme_frontend_stack_orientation_present
    - docs.product_foundation.readme_source_graph_orientation_present
    - docs.product_foundation.docs_index_present

- kind: source_file
  target: .spec/README.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.runic_execution_model.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.factory_control_plane.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.internal_cleanup_and_ui_convergence_foundation.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.live_vue_frontend_adoption.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.jido_os_deprecation.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_product_adoption.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: .spec/decisions/jido_code.vsm_recursion_and_scope.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace

- kind: source_file
  target: docs/developer/00-spec-led-development-and-drift-control.md
  covers:
    - docs.product_foundation.spec_led_intro_guide_present

- kind: source_file
  target: docs/developer/README.md
  covers:
    - docs.product_foundation.spec_led_intro_guide_present
    - docs.product_foundation.source_code_ontology_guide_present
    - docs.product_foundation.memory_ontology_guide_present
    - docs.product_foundation.workflow_provenance_ontology_guide_present

- kind: source_file
  target: docs/developer/07-source-code-graph-and-semantic-services.md
  covers:
    - docs.product_foundation.source_code_ontology_guide_present

- kind: source_file
  target: docs/developer/07b-source-code-ontology-and-query-examples.md
  covers:
    - docs.product_foundation.source_code_ontology_guide_present

- kind: source_file
  target: docs/developer/08-memory-graph-and-workflow-provenance.md
  covers:
    - docs.product_foundation.memory_ontology_guide_present
    - docs.product_foundation.workflow_provenance_ontology_guide_present

- kind: source_file
  target: docs/developer/08b-memory-ontology-and-query-examples.md
  covers:
    - docs.product_foundation.memory_ontology_guide_present

- kind: source_file
  target: docs/developer/08c-workflow-provenance-ontology-and-query-examples.md
  covers:
    - docs.product_foundation.workflow_provenance_ontology_guide_present
```
