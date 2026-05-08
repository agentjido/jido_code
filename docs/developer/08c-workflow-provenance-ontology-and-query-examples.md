# 08c. Workflow Provenance Ontology And Query Examples

<!-- covers: docs.product_foundation.workflow_provenance_ontology_guide_present -->

This guide explains what is actually inside the repository-scoped
`workflow_provenance` graph, which ontology concepts show up there in practice,
and what kinds of explicit provenance questions are worth asking.

Useful implementation sources:

- [`../../lib/jido_code/memory_graph.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph.ex)
- [`../../lib/jido_code/memory_graph/capture_envelope.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/capture_envelope.ex)
- [`../../lib/jido_code/memory_graph/capture_writer.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/capture_writer.ex)
- [`../../lib/jido_code/memory_graph/helper_queries.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/helper_queries.ex)
- [`../../lib/jido_code/memory_graph/product_service.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/product_service.ex)
- [`../../lib/jido_code/memory_graph/workflow_service.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/workflow_service.ex)
- [`../../lib/jido_code/memory_graph/query.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/memory_graph/query.ex)
- [`../../priv/ontologies/jido-memory.ttl`](https://github.com/mikehostetler/jido_code/blob/main/priv/ontologies/jido-memory.ttl)
- [`../../priv/ontologies/jido-control-plane.ttl`](https://github.com/mikehostetler/jido_code/blob/main/priv/ontologies/jido-control-plane.ttl)

## Relationship To Guides 08 And 08b

Guide `08` explains why `workflow_provenance` exists at all.

Guide `08b` explains adopted durable knowledge in the `memory` graph.

This guide explains the sibling operational graph:

- which activity and artifact kinds are written into `workflow_provenance`
- how work sessions, runs, tools, plans, patches, and reviews relate
- which runtime, code, and governed anchors are preserved there
- what questions explicit provenance queries can answer well

## What Lives In `workflow_provenance`

The canonical workflow-provenance target is:

- graph name: `workflow_provenance`
- named graph IRI: `https://jido.run/graphs/workflow_provenance`

Repository-local provenance entities use a stable repo-scoped base IRI:

- `https://jido.run/managed_repos/<managed_repo_id>/workflow_provenance#`

Unlike the durable-memory graph, `workflow_provenance` stores first-class
typed operational nodes directly:

- `WorkSession`
- `AgentRun`
- `ToolInvocation`
- `PromptTurn`
- `Plan`
- `Patch`
- `Review`
- supporting `Actor`, `Model`, `Toolchain`, and `RepositoryRevision` nodes

This is the graph you query when you want to reconstruct bounded repository
work history rather than durable semantic knowledge.

## The Ontology Layers That Matter Here

The same ontology pair is in play, but different parts of it dominate.

| Prefix | Role | Typical facts |
|-------|------|---------------|
| `jido:` | workflow classes and relationships | sessions, runs, tools, plans, reviews, anchors, governed links |
| `prov:` | activity/entity lineage | start/end times, attribution, generated-by, informed-by, used |
| `jcp:` | governed control-plane vocabulary | work item, run, evidence, decision record types |

In day-to-day provenance work:

- `jido:` is the structural backbone.
- `prov:` carries the execution lineage.
- `jcp:` matters when work history needs to rejoin governed product records.

## What Gets Written At Capture Time

`CaptureWriter` writes bounded workflow history into this graph through typed
capture envelopes.

Every recorded work session includes:

- `jido:WorkSession`
- `jido:sessionId`
- `prov:startedAtTime`
- `jido:performedByActor`
- `jido:validForRevision`

It may also include:

- `jido:sessionGoal`
- `jido:sessionOutcome`
- `jido:branchName`
- `jido:usedModel`
- `jido:usedToolchain`

Child resources are attached through explicit links:

- `jido:hasAgentRun`
- `jido:hasToolInvocation`
- `jido:hasPromptTurn`
- `jido:hasPlan`
- `jido:hasPatch`
- `jido:hasReview`

The main kinds differ slightly in role:

| Kind | Mostly modeled as | Typical extra links |
|------|-------------------|---------------------|
| `WorkSession` | `prov:Activity` | actor, model, toolchain, revision, goal, outcome |
| `AgentRun` | `prov:Activity` | `prov:wasAssociatedWith`, `prov:wasInformedBy` |
| `ToolInvocation` | `prov:Activity` | actor, informed-by session or agent run |
| `PromptTurn` | `prov:Activity` | actor, informed-by session |
| `Plan` | `prov:Entity` | `prov:wasGeneratedBy` session or agent run |
| `Patch` | `prov:Entity` | `prov:wasGeneratedBy` session or agent run |
| `Review` | `prov:Activity` | actor, informed-by, optional `prov:used` patch |

The writer also adds:

- source-code anchors such as `jido:aboutModule` and `jido:aboutFunction`
- governed links such as `jido:aboutWorkItem`, `jido:aboutRun`, and
  `jido:aboutDecision`
- `jido:relatedTo` links to nearby semantic resources when the capture envelope
  includes them

## What Kind Of Information The Graph Can Provide

### Session Reconstruction

The graph can answer:

- which work sessions happened
- when they started
- which actor, model, and toolchain were involved
- what goal or outcome the session declared

### Execution Lineage

The graph can answer:

- which agent runs belonged to a session
- which tool invocations were informed by a run or session
- which plans, patches, and reviews were produced

### Code-Scoped Provenance

The graph can answer:

- which workflow events touched a module or function
- which review or patch artifacts relate to a symbol or file
- which operational history should be surfaced beside a semantic finding

### Governed Context

The graph can answer:

- which workflow events belong to a work item or governed run
- which review, patch, or session should be attached to evidence or decision
  records later

### Revision Scope

The graph can answer:

- which repository revision a session or resource belonged to
- whether the session history you are reading lines up with the current repo
  revision

## What `jido_code` Already Exposes As Bounded Helpers

As with durable memory, product-facing code should start with bounded helpers.

| Need | Product boundary | Explicit workspace/action boundary |
|------|------------------|------------------------------------|
| list workflow provenance | `MemoryGraph.ProductService.provenance/3` | `AgentWorkspace.query_memory_graph/4` with `graph_name: "workflow_provenance"` |
| filter by governed records | `MemoryGraph.ProductService.provenance_for_governed_references/4` | `AgentWorkspace.query_memory_graph/4` |
| inspect related code/governed/evidence links for one provenance resource | `MemoryGraph.ProductService.cross_links/4` | `AgentWorkspace.query_memory_graph/4` |
| get readiness and health | `MemoryGraph.ProductService.status/3`, `health/3`, `summary/3` | `AgentWorkspace.memory_graph_status/3`, `validate_memory_graph/3`, `recover_memory_graph/3` |
| request provenance-backed workflow context | `MemoryGraph.WorkflowService.plan/4`, `execute/4`, `review/4`, `explain/4` | explicit `memory:` options passed through the workflow boundary |

That split keeps:

- raw SPARQL out of product UI code
- workflow memory/provenance use explicit rather than ambient
- operational history queryable without flattening it into durable memory

## Query Conventions

When adapting the examples below:

- replace `<workflow-base-iri>` with
  `https://jido.run/managed_repos/<managed_repo_id>/workflow_provenance#`
- replace `<source-code-base-iri>` with
  `https://jido.run/managed_repos/<managed_repo_id>/source_code#`
- run the query against `graph_name: "workflow_provenance"`
- do not add an explicit `GRAPH` clause

`JidoCode.MemoryGraph.Query` injects `jido:`, `prov:`, `owl:`, and `xsd:`
automatically. Examples still include explicit `PREFIX` lines for clarity.

## Example Queries

### 1. List Recent Work Sessions

Use this when you want a concise view of repository work history.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?session ?session_id ?started_at ?goal ?outcome ?branch ?actor_label ?model_label ?toolchain_label
WHERE {
  ?session a jido:WorkSession ;
           jido:sessionId ?session_id ;
           prov:startedAtTime ?started_at ;
           jido:performedByActor ?actor .

  OPTIONAL { ?session jido:sessionGoal ?goal . }
  OPTIONAL { ?session jido:sessionOutcome ?outcome . }
  OPTIONAL { ?session jido:branchName ?branch . }
  OPTIONAL { ?actor rdfs:label ?actor_label . }
  OPTIONAL {
    ?session jido:usedModel ?model .
    OPTIONAL { ?model rdfs:label ?model_label . }
  }
  OPTIONAL {
    ?session jido:usedToolchain ?toolchain .
    OPTIONAL { ?toolchain rdfs:label ?toolchain_label . }
  }

  FILTER(STRSTARTS(STR(?session), "<workflow-base-iri>"))
}
ORDER BY DESC(?started_at) ?session
LIMIT 25
```

Bounded equivalent:

- `MemoryGraph.ProductService.provenance/3` with `kinds: [:work_session]`

### 2. Find Agent Runs And Tool Invocations For One Session

Use this when you want the operational spine of one session.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?kind_label ?resource ?label ?started_at ?ended_at
WHERE {
  BIND(<work-session-iri> AS ?session)

  {
    ?session jido:hasAgentRun ?resource .
    BIND("AgentRun" AS ?kind_label)
  }
  UNION
  {
    ?session jido:hasToolInvocation ?resource .
    BIND("ToolInvocation" AS ?kind_label)
  }

  OPTIONAL { ?resource rdfs:label ?label . }
  OPTIONAL { ?resource prov:startedAtTime ?started_at . }
  OPTIONAL { ?resource prov:endedAtTime ?ended_at . }
}
ORDER BY ?kind_label ?resource
```

### 3. Find Reviews And The Patches They Used

Use this when you want review lineage instead of only patch existence.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?review ?review_label ?patch ?patch_label ?work_item
WHERE {
  ?review a jido:Review ;
          prov:used ?patch .

  OPTIONAL { ?review rdfs:label ?review_label . }
  OPTIONAL { ?patch rdfs:label ?patch_label . }
  OPTIONAL { ?review jido:aboutWorkItem ?work_item . }

  FILTER(STRSTARTS(STR(?review), "<workflow-base-iri>"))
}
ORDER BY ?review
LIMIT 25
```

### 4. Find Provenance Attached To One Module

Use this when you want bounded work history for one code area.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX prov: <http://www.w3.org/ns/prov#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?resource ?kind ?label ?started_at ?ended_at ?module ?function
WHERE {
  VALUES ?kind {
    jido:AgentRun
    jido:ToolInvocation
    jido:PromptTurn
    jido:Plan
    jido:Patch
    jido:Review
  }

  ?resource a ?kind .
  OPTIONAL { ?resource rdfs:label ?label . }
  OPTIONAL { ?resource prov:startedAtTime ?started_at . }
  OPTIONAL { ?resource prov:endedAtTime ?ended_at . }
  OPTIONAL { ?resource jido:aboutModule ?module . }
  OPTIONAL { ?resource jido:aboutFunction ?function . }

  FILTER(
    STR(?module) =
      "<source-code-base-iri>JidoCode.MemoryGraph.ProductService"
  )
}
ORDER BY DESC(?started_at) ?resource
LIMIT 50
```

Bounded equivalent:

- `MemoryGraph.ProductService.provenance/3`
- `MemoryGraph.ProductService.cross_links/4`

### 5. Find Provenance Linked To Governed Work

Use this when you want the operational history around a work item, run, or
governed decision.

```sparql
PREFIX jido: <https://jido.run/ontology/memory#>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

SELECT ?resource ?kind ?label ?governed
WHERE {
  VALUES ?kind {
    jido:WorkSession
    jido:AgentRun
    jido:ToolInvocation
    jido:PromptTurn
    jido:Plan
    jido:Patch
    jido:Review
  }

  ?resource a ?kind .
  OPTIONAL { ?resource rdfs:label ?label . }

  {
    ?resource jido:aboutWorkItem ?governed .
  }
  UNION
  {
    ?resource jido:aboutRun ?governed .
  }
  UNION
  {
    ?resource jido:aboutDecision ?governed .
  }

  FILTER(STRSTARTS(STR(?resource), "<workflow-base-iri>"))
}
ORDER BY ?kind ?resource
LIMIT 50
```

Bounded equivalent:

- `MemoryGraph.ProductService.provenance_for_governed_references/4`

## What To Keep In Mind

- `workflow_provenance` is bounded operational history, not durable product
  truth and not the same thing as adopted memory.
- The graph stores labels, comments, timing, attribution, and links, but it is
  not a substitute for exact patch diffs, raw tool stdout, or current source
  text.
- Explicit memory queries target one named graph at a time, so cross-graph
  reasoning still happens through separate queries or product-owned navigation.
- If a provenance finding matters to the product, it still has to rejoin
  governed records such as `Observation`, `Assessment`, `WorkItem`, `Evidence`,
  or governed `Decision`.

## Read Next

Continue with
[`09-frontend-and-product-surfaces.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/09-frontend-and-product-surfaces.md).
