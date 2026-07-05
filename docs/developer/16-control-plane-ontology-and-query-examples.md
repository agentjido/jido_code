# 16. Control-Plane Ontology And Query Examples

<!-- covers: docs.product_foundation.control_plane_ontology_guide_present -->

The embedded control-plane store is the product data plane for governed records.
It stores product facts as RDF quads in named graphs, with map-level product
helpers and codecs shielding normal callers from raw store details.

## Main Boundaries

| Boundary | Use it for |
| --- | --- |
| `JidoCode.ControlPlane.RecordStore` | Generic map-level create, upsert, update, get, list, and decode helpers. |
| Product stores such as `JidoCode.Control.ManagedRepoStore`, `JidoCode.Operations.RecordStore`, `JidoCode.Governance.RecordStore`, `JidoCode.Conversations.RecordStore`, and `JidoCode.ExecutionRuntime.RecordStore` | Normal product reads and writes. Prefer these from web, setup, workflow, and runtime code. |
| `JidoCode.ControlPlane.StoreQuery` | Bounded product projections and diagnostic SPARQL with graph allow-lists, limits, timeouts, and redaction. |
| `JidoCode.ControlPlane.Diagnostics` and `mix control_plane.query` | Contributor and support inspection. Safe named queries should be the first choice. |
| `JidoCode.ControlPlane.StoreCommand` and `StoreServer` | Low-level store implementation. Use these inside the control-plane implementation and focused tests only. |

## Ontology And Identity

The ontology source lives at `priv/ontologies/jido-control-plane.ttl`.

The primary namespace is:

```text
https://jido.run/ontology/control-plane#
```

Canonical subjects are generated from `JidoCode.ControlPlane.SemanticIdentity`.
Examples:

```text
https://jido.run/control/managed-repos/{id}
https://jido.run/control/source-repos/{id}
https://jido.run/control/managed-repos/{managed_repo_id}/work-items/{id}
https://jido.run/control/managed-repos/{managed_repo_id}/runs/{id}
https://jido.run/control/users/{id}
https://jido.run/control/secret-refs/{id}
```

Each promoted record type has a codec in
`JidoCode.ControlPlane.Codecs.Registry`. Codecs define the RDF class, named
graph, subject IRI, projected fields, and identity queries for that record.
Codec coverage is guarded by `test/jido_code/embedded_store_removal_gate_test.exs`.

## Named Graphs

| Graph name | IRI | Main content |
| --- | --- | --- |
| `:control_plane` | `https://jido.run/graphs/control_plane` | Managed repos, source repos, work items, runs, governance records, setup records, and most product records. |
| `:control_plane_events` | `https://jido.run/graphs/control_plane_events` | Append-heavy control-plane event records and webhook deliveries. |
| `:auth` | `https://jido.run/graphs/auth` | Users, identities, API key metadata, tokens, and provider config. |
| `:security` | `https://jido.run/graphs/security` | Secret references and secret lifecycle audit metadata. |
| `:conversations` | `https://jido.run/graphs/conversations` | Conversation records, events, and snapshots. |
| `:execution_runtime` | `https://jido.run/graphs/execution_runtime` | Execution workflows, sandbox sessions, runtime events, checkpoints, exec sessions, and sprite specs. |
| `:memory` | `https://jido.run/graphs/memory` | Durable memory graph facts linked to governed product records. |
| `:workflow_provenance` | `https://jido.run/graphs/workflow_provenance` | Workflow provenance facts linked to governed product records. |
| `:source_code` | `https://jido.run/graphs/source_code` | Repository source-code graph facts linked to governed product records. |

Auth and security graphs are omitted from default control-plane exports. Their
projections also exclude secret material, credential hashes, bearer tokens,
webhook secrets, and private keys.

## Product Query Helpers First

Use product helpers when application behavior needs product records:

```elixir
JidoCode.Control.ManagedRepoStore.get_by_id("repo-id")
JidoCode.Operations.RecordStore.list_work_by_managed_repo("repo-id")
JidoCode.Governance.RecordStore.upsert_decision(%{id: "decision-id", managed_repo_id: "repo-id"})
JidoCode.ControlPlane.RecordStore.list(:managed_repo)
```

Use `StoreQuery` when the product helper does not yet expose the bounded shape
you need:

```elixir
JidoCode.ControlPlane.StoreQuery.get_by_id(:managed_repo, "repo-id")
JidoCode.ControlPlane.StoreQuery.list_by_class(:work_item, limit: 25)
JidoCode.ControlPlane.StoreQuery.list_by_repo(:run, "repo-id", limit: 25)
```

Use safe diagnostics when you are inspecting store state:

```bash
mix control_plane.query --named health
mix control_plane.query --named graph-counts
mix control_plane.query --named list-records --record-type managed_repo --limit 25 --json
```

## Raw SPARQL

Raw SPARQL is a diagnostic tool, not the default application boundary. Use it
when you need to answer a bounded graph question during development or support,
and always provide an explicit allow-list, limit, and timeout.

List managed repository subjects:

```bash
mix control_plane.query \
  --sparql 'SELECT ?s WHERE { GRAPH <https://jido.run/graphs/control_plane> { ?s a <https://jido.run/ontology/control-plane#ManagedRepo> } }' \
  --allow-raw \
  --graph control_plane \
  --limit 25 \
  --timeout 5000 \
  --json
```

Inspect one subject by IRI:

```bash
mix control_plane.query \
  --sparql 'SELECT ?p ?o WHERE { GRAPH <https://jido.run/graphs/control_plane> { <https://jido.run/control/managed-repos/repo-id> ?p ?o } }' \
  --allow-raw \
  --graph control_plane \
  --limit 50 \
  --json
```

Avoid raw SPARQL from LiveViews, product services, and workflow modules. If a
query becomes product behavior, promote it to a product helper or bounded
`StoreQuery` function so graph allow-lists, redaction, pagination, and error
shaping stay consistent.
