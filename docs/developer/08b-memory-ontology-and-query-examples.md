# 08b. Memory Ontology And Query Examples

<!-- covers: docs.product_foundation.memory_ontology_guide_present -->

This guide explains what is actually inside the repository-scoped `memory`
graph, how the coding-memory ontology is used there, and which questions are
good fits for bounded helper lookups versus explicit SPARQL.

Useful implementation sources:

- [`../../lib/jido_code/memory_graph.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph.ex)
- [`../../lib/jido_code/memory_graph/durable_memory_envelope.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/durable_memory_envelope.ex)
- [`../../lib/jido_code/memory_graph/durable_memory_writer.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/durable_memory_writer.ex)
- [`../../lib/jido_code/memory_graph/durable_memory_update_envelope.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/durable_memory_update_envelope.ex)
- [`../../lib/jido_code/memory_graph/durable_memory_update_writer.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/durable_memory_update_writer.ex)
- [`../../lib/jido_code/memory_graph/helper_queries.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/helper_queries.ex)
- [`../../lib/jido_code/memory_graph/product_service.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/product_service.ex)
- [`../../lib/jido_code/memory_graph/query.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/query.ex)
- [`../../priv/ontologies/jido-memory.ttl`](https://github.com/mikehostetler/jido_code/blob/main/priv/ontologies/jido-memory.ttl)
- [`../../priv/ontologies/jido-control-plane.ttl`](https://github.com/mikehostetler/jido_code/blob/main/priv/ontologies/jido-control-plane.ttl)

## Relationship To Guide 08

Guide `08` explains the boundary:

- there are two related repository-scoped graphs
- `memory` holds adopted durable knowledge
- `workflow_provenance` holds bounded operational history
- product callers should use product-owned services and workflow boundaries

This guide explains the `memory` graph content:

- which ontology files define the model
- which durable memory classes appear in practice
- which supporting evidence, freshness, and governed-reference nodes are
  written alongside memories
- what kinds of questions explicit memory queries can answer

## What Lives In `memory`

The canonical durable-memory target is:

- graph name: `memory`
- named graph IRI: `https://jido.run/graphs/memory`

Repository-local memory entities use a stable repo-scoped base IRI:

- `https://jido.run/managed_repos/<managed_repo_id>/memory#`

That base is used for:

- durable memory resources such as `fact/...`, `decision/...`, or
  `known_issue/...`
- classification and update evidence artifacts
- first-class tag resources

The graph is repository-scoped and queryable independently from
`workflow_provenance` and `source_code`.

That matters because explicit SPARQL against `memory` only sees the `memory`
named graph. If you need workflow-session details or exact source-code
structure, you query those sibling graphs separately or use product-owned
cross-link helpers.

## The Ontology Pair

`jido_code` uses two ontology layers together here:

| Prefix | Role | Typical facts |
|-------|------|---------------|
| `jido:` | coding-memory and workflow vocabulary | memory kinds, decision structure, freshness, evidence, code anchors |
| `jcp:` | governed control-plane vocabulary | managed repo, work item, run, evidence, decision record types |
| `prov:` | provenance vocabulary | attribution, derivation, activity/entity roles |

In practice:

- `jido:` defines the durable memory classes and most query predicates.
- `jcp:` matters when memories point back to governed product records.
- `prov:` matters for attribution and evidence lineage.

## What Gets Written When A Memory Is Adopted

Every durable memory entry is intentionally richer than one text blob.

At minimum, a recorded memory is written with:

- one specific durable class such as `jido:Fact`, `jido:Decision`,
  `jido:KnownIssue`, or `jido:Pattern`
- the shared base type `jido:Memory`
- `jido:content`
- `jido:timestamp`
- `jido:sourceSession`
- revision links such as `jido:observedAtRevision` and `jido:validForRevision`
- attribution such as `prov:wasAttributedTo` and `prov:wasDerivedFrom`

Depending on kind and capture input, it can also carry:

- source-code anchors:
  `jido:aboutRepository`, `jido:aboutFile`, `jido:aboutModule`,
  `jido:aboutFunction`, `jido:aboutTest`, `jido:aboutConfig`,
  `jido:affectsSymbol`
- governed links:
  `jido:aboutManagedRepo`, `jido:aboutObservation`,
  `jido:aboutAssessment`, `jido:aboutWorkItem`, `jido:aboutRun`,
  `jido:aboutEvidence`, `jido:aboutChangeRequest`, `jido:aboutDecision`
- evidence and confidence metadata:
  `jido:supportedBy`, `jido:evidenceArtifact`, `jido:confidenceSource`
- decision structure:
  `jido:rationale`, `jido:decisionStatus`, `jido:supersedes`,
  `jido:alternativeConsidered`, `jido:hasConsequence`
- tagging and relationships:
  `jido:hasTag`, `jido:relatedTo`

The main durable kinds currently supported by the envelope and writer are:

- `Fact`
- `Decision`
- `LessonLearned`
- `Invariant`
- `Convention`
- `KnownIssue`
- `OpenQuestion`
- `Pattern`
- `AntiPattern`

## What Update Operations Add Later

The initial durable-memory write is only part of the story.

Later validation, invalidation, and supersession writes can add or update:

- `jido:freshnessScore`
- `jido:lastValidatedAt`
- `jido:staleReason`
- `jido:invalidatedByRevision`
- `jido:validatedByTestRun`
- newer `jido:supportedBy` and `jido:evidenceArtifact` links

Those update operations also materialize supporting nodes such as:

- `jido:EvidenceArtifact`
- `jido:RepositoryRevision`
- `jido:TestRun`

So the `memory` graph is not only a memory inventory. It also accumulates the
lineage that explains why a memory is still current, stale, invalidated, or
superseded.

## What Kind Of Information The Graph Can Provide

### Durable Knowledge Inventory

The graph can answer:

- which durable memories exist for this repository
- what kinds dominate the memory set
- which memories are recent versus older

### Code-Anchored Knowledge

The graph can answer:

- which decisions are about a specific module or function
- which known issues affect a specific symbol
- which conventions or invariants are attached to one area of the codebase

### Decision Lineage

The graph can answer:

- which decisions are still accepted
- which decisions supersede older ones
- which alternatives or consequences were recorded

### Freshness And Trust

The graph can answer:

- which memories were validated recently
- which memories are stale or invalidated
- which test runs or evidence artifacts support a memory

### Governed Product Context

The graph can answer:

- which durable memories are tied to a work item, run, evidence record, or
  governed decision
- which semantic findings should rejoin governed product records

## What `jido_code` Already Exposes As Bounded Helpers

Product-facing code should start with bounded helpers instead of hand-writing
SPARQL.

| Need | Product boundary | Explicit workspace/action boundary |
|------|------------------|------------------------------------|
| list durable memories | `MemoryGraph.ProductService.memories/3` | `AgentWorkspace.query_memory_graph/4` with `graph_name: "memory"` |
| filter by governed records | `MemoryGraph.ProductService.memories_for_governed_references/4` | `AgentWorkspace.query_memory_graph/4` |
| inspect related code/governed/evidence links for one resource | `MemoryGraph.ProductService.cross_links/4` | `AgentWorkspace.query_memory_graph/4` |
| record a durable memory | product/governed adoption paths | `AgentWorkspace.record_memory_graph/4` |
| validate, invalidate, or recover | product-owned surfaces and services | `AgentWorkspace.validate_memory_graph/3`, `invalidate_memory_graph/3`, `recover_memory_graph/3` |

That split is intentional:

- product callers get shaped memory projections
- explicit SPARQL stays a repository-scoped action
- updates to freshness and supersession still go through the capture plane

## Query Conventions

When adapting the examples below:

- replace `<memory-base-iri>` with
  `https://jido.run/managed_repos/<managed_repo_id>/memory#`
- replace `<source-code-base-iri>` with
  `https://jido.run/managed_repos/<managed_repo_id>/source_code#`
- run the query against `graph_name: "memory"`
- do not add an explicit `GRAPH` clause

`JidoCode.MemoryGraph.Query` injects these prefixes automatically:

- `jido:`
- `prov:`
- `owl:`
- `xsd:`

Examples below still include explicit `PREFIX` lines because they are easier to
read in documentation.

If you need `jcp:` or `rdfs:` names in an explicit query, declare them in the
query text.

## Example Queries

### 1. List Recent Durable Memories

Use this when you want a semantic inventory of the memories the repository has
already adopted.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>

SELECT ?memory ?kind ?content ?timestamp
WHERE {
  VALUES ?kind {
    jido:Fact
    jido:Decision
    jido:LessonLearned
    jido:Invariant
    jido:Convention
    jido:KnownIssue
    jido:OpenQuestion
    jido:Pattern
    jido:AntiPattern
  }

  ?memory a ?kind ;
          jido:content ?content ;
          jido:timestamp ?timestamp .

  FILTER(STRSTARTS(STR(?memory), "<memory-base-iri>"))
}
ORDER BY DESC(?timestamp) ?memory
LIMIT 25
```

Bounded equivalent:

- `MemoryGraph.ProductService.memories/3`

### 2. Find Known Issues And Open Questions For One Module

Use this when you want the repository's preserved caveats for a specific module.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>

SELECT ?memory ?kind ?content ?freshness ?stale_reason
WHERE {
  VALUES ?kind { jido:KnownIssue jido:OpenQuestion }

  ?memory a ?kind ;
          jido:content ?content ;
          jido:aboutModule ?module .

  OPTIONAL { ?memory jido:freshnessScore ?freshness . }
  OPTIONAL { ?memory jido:staleReason ?stale_reason . }

  FILTER(
    STR(?module) =
      "<source-code-base-iri>JidoCode.MemoryGraph.ProductService"
  )
}
ORDER BY DESC(?freshness) ?memory
LIMIT 25
```

Bounded equivalent:

- `MemoryGraph.ProductService.memories/3` with
  `module_name: "JidoCode.MemoryGraph.ProductService"` and
  `kinds: [:known_issue, :open_question]`

### 3. Find Memories That Are Stale Or Explicitly Invalidated

Use this when you need to understand trust boundaries, not just content.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>

SELECT ?memory ?kind ?content ?stale_reason ?invalidated_revision ?last_validated_at
WHERE {
  VALUES ?kind {
    jido:Fact
    jido:Decision
    jido:LessonLearned
    jido:Invariant
    jido:Convention
    jido:KnownIssue
    jido:OpenQuestion
    jido:Pattern
    jido:AntiPattern
  }

  ?memory a ?kind ;
          jido:content ?content .

  OPTIONAL { ?memory jido:staleReason ?stale_reason . }
  OPTIONAL { ?memory jido:invalidatedByRevision ?invalidated_revision . }
  OPTIONAL { ?memory jido:lastValidatedAt ?last_validated_at . }

  FILTER(BOUND(?stale_reason) || BOUND(?invalidated_revision))
  FILTER(STRSTARTS(STR(?memory), "<memory-base-iri>"))
}
ORDER BY ?kind ?memory
LIMIT 50
```

### 4. Trace Decision Lineage

Use this when you care about architectural memory changing over time.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>

SELECT ?decision ?content ?status ?supersedes ?alternative ?consequence
WHERE {
  ?decision a jido:Decision ;
            jido:content ?content .

  OPTIONAL { ?decision jido:decisionStatus ?status . }
  OPTIONAL { ?decision jido:supersedes ?supersedes . }
  OPTIONAL { ?decision jido:alternativeConsidered ?alternative . }
  OPTIONAL { ?decision jido:hasConsequence ?consequence . }

  FILTER(STRSTARTS(STR(?decision), "<memory-base-iri>"))
}
ORDER BY ?decision
LIMIT 100
```

### 5. Find Memories Tied To Governed Work

Use this when you want the bridge between semantic memory and product records.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>

SELECT ?memory ?content ?work_item ?run ?decision
WHERE {
  ?memory a jido:Memory ;
          jido:content ?content .

  OPTIONAL { ?memory jido:aboutWorkItem ?work_item . }
  OPTIONAL { ?memory jido:aboutRun ?run . }
  OPTIONAL { ?memory jido:aboutDecision ?decision . }

  FILTER(BOUND(?work_item) || BOUND(?run) || BOUND(?decision))
  FILTER(STRSTARTS(STR(?memory), "<memory-base-iri>"))
}
ORDER BY ?memory
LIMIT 50
```

Bounded equivalent:

- `MemoryGraph.ProductService.memories_for_governed_references/4`

### 6. Inspect The Evidence Supporting One Memory

Use this when you already have a memory IRI and want to see what supports it.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?artifact ?label
WHERE {
  BIND(<memory-iri> AS ?memory)

  ?memory jido:supportedBy ?artifact .
  OPTIONAL { ?artifact rdfs:label ?label . }
}
ORDER BY ?artifact
```

Bounded starting point:

- `MemoryGraph.ProductService.cross_links/4`

## What To Keep In Mind

- Durable memory is curated knowledge, not a dump of prompt text, tool output,
  or conversation history.
- The `memory` graph stores links to sessions and revisions, but the full typed
  operational history lives in `workflow_provenance`.
- Freshness state is part of the semantic model, so stale or invalidated memory
  should be treated differently from recently validated memory.
- Governed product records remain the business system of record even when the
  memory graph provides strong supporting evidence.

## Read Next

Continue with
[`08c-workflow-provenance-ontology-and-query-examples.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08c-workflow-provenance-ontology-and-query-examples.md).
