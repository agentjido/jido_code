# Product Foundation Docs

This subject defines the repository-facing docs that orient contributors to what
`Jido.Code` is, how to run it, and where the durable architecture record now lives.

```spec-meta
id: docs.product_foundation
kind: feature
status: active
summary: Jido.Code keeps a quickstart-oriented top-level README, including the approved frontend-stack, repo-owned `mix server` start path, and verification orientation for contributors, while durable architecture and product-shaping guidance live in the repo-local `.spec` workspace and adjacent contributor guides.
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
surface:
  - .spec/decisions/jido_code.compatibility_era_removal_and_canonical_cutover.md
  - .spec/decisions/jido_code.internal_domain_and_execution_canonicalization.md
  - README.md
  - CONTRIBUTING.md
  - .spec/README.md
  - .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
  - .spec/decisions/jido_code.internal_cleanup_and_ui_convergence_foundation.md
  - .spec/decisions/jido_code.live_vue_frontend_adoption.md
  - .spec/decisions/jido_code.jido_os_deprecation.md
  - .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
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

- id: docs.product_foundation.durable_architecture_record_in_spec_workspace
  statement: Durable architecture and product-shaping decisions shall live in the repo-local `.spec` workspace rather than in a separate root `docs/` tree.
  priority: must
  stability: evolving

- id: docs.product_foundation.docs_index_present
  statement: The repository shall expose the adjacent contributor guides through the top-level README, including the repo-local spec workflow, the separate desktop packaging guide, and the direct Mix-based CLI surfaces.
  priority: must
  stability: stable
```

## Scenarios

```spec-scenarios
- id: docs.product_foundation.scenario.new_contributor_reads_foundation
  covers:
    - docs.product_foundation.readme_quickstart_present
    - docs.product_foundation.product_summary_present
    - docs.product_foundation.readme_frontend_stack_orientation_present
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
    - The README links the spec workspace, contributor guide, and separate desktop runtime guide directly.
```

## Verification

```spec-verification
- kind: source_file
  target: README.md
  covers:
    - docs.product_foundation.readme_quickstart_present
    - docs.product_foundation.product_summary_present
    - docs.product_foundation.readme_frontend_stack_orientation_present
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
  target: .spec/decisions/jido_code.factory_control_plane_and_runtime_overlay.md
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
  target: .spec/decisions/jido_code.vsm_recursion_and_scope.md
  covers:
    - docs.product_foundation.durable_architecture_record_in_spec_workspace
```
