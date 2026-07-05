# Embedded TripleStore Control Plane

This directory contains the phased plan for replacing the current Ash/Postgres
data plane with an embedded `triple_store` control-plane store.

The plan is intentionally greenfield:

- no existing Ash/Postgres records are migrated
- no long-lived dual-write compatibility layer is introduced
- no product surface should keep direct Ash resource or Ecto repo dependencies
- the canonical product store becomes an embedded quad store with named graphs
- legacy `Forge` is treated as an execution-runtime implementation substrate:
  keep useful sandbox, runner, sprite, and redaction pieces only where needed,
  and remove its Ash/Postgres data-plane resources instead of preserving Forge
  as a product domain

## Phases

1. [Phase 1 - Ontology And Graph Topology Foundation](./phase-01-ontology-and-graph-topology-foundation.md)
2. [Phase 2 - Embedded Store Runtime And Transaction Boundary](./phase-02-embedded-store-runtime-and-transaction-boundary.md)
3. [Phase 3 - Product Store Contract And Projection Codecs](./phase-03-product-store-contract-and-projection-codecs.md)
4. [Phase 4 - Identity, Setup, And Security Data Plane](./phase-04-identity-setup-and-security-data-plane.md)
5. [Phase 5 - Control, Operations, Governance, And Orchestration Data Plane](./phase-05-control-operations-governance-and-orchestration-data-plane.md)
6. [Phase 6 - Conversations And Execution Runtime Data Plane](./phase-06-conversations-and-execution-runtime-data-plane.md)
7. [Phase 7 - Product Surface Cutover And Ash/Postgres Removal](./phase-07-product-surface-cutover-and-ash-postgres-removal.md)
8. [Phase 8 - Verification, Recovery, And Contributor Convergence](./phase-08-verification-recovery-and-contributor-convergence.md)

## Shared Conventions

- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes.
- Description requirement:
  - Every phase, section, and task starts with a short description paragraph.
- Integration-test requirement:
  - Every phase ends with a final integration-test section.
- Greenfield storage rule:
  - If a product path still needs an Ash resource or `JidoCode.Repo` after
    Phase 7, it is incomplete unless explicitly documented as a temporary test
    fixture dependency.

## Named Graph Targets

- `https://jido.run/graphs/control_plane`
- `https://jido.run/graphs/control_plane_events`
- `https://jido.run/graphs/auth`
- `https://jido.run/graphs/security`
- `https://jido.run/graphs/conversations`
- `https://jido.run/graphs/execution_runtime`
- `https://jido.run/graphs/memory`
- `https://jido.run/graphs/workflow_provenance`
- `https://jido.run/graphs/source_code`
