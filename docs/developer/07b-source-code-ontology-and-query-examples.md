# 07b. Source Code Ontology And Query Examples

<!-- covers: docs.product_foundation.source_code_ontology_guide_present -->

This guide explains what is actually inside the repository-scoped source-code
graph once it is loaded, what the ontology layers mean, and what kinds of
questions are good fits for bounded helper lookups versus explicit SPARQL.

Useful implementation sources:

- [`../../lib/jido_code/source_code_graph.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/source_code_graph.ex)
- [`../../lib/jido_code/source_code_graph/analysis.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/source_code_graph/analysis.ex)
- [`../../lib/jido_code/source_code_graph/helper_queries.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/source_code_graph/helper_queries.ex)
- [`../../lib/jido_code/source_code_graph/query.ex`](https://github.com/mikehostetler/jido_code/blob/main/lib/jido_code/source_code_graph/query.ex)

## Relationship To Guide 07

Guide `07` explains the product boundary:

- repository-scoped graph
- explicit analyze/load/refresh/query lifecycle
- product-owned semantic service boundaries
- bounded operator and workflow adoption

This guide explains the graph content:

- which ontology schema files are loaded
- what repository facts become graph individuals
- which namespaces matter most in practice
- what kinds of questions the graph can answer

## What Gets Loaded Into `source_code`

`jido_code` loads one coherent semantic snapshot into the canonical
`source_code` named graph.

That snapshot contains both:

- ontology schema artifacts
- repository-derived individuals for the current workspace snapshot

The named graph identity is fixed:

- graph name: `source_code`
- named graph IRI: `https://jido.run/graphs/source_code`

Repository-specific entities use a stable repo-scoped base IRI:

- `https://jido.run/managed_repos/<managed_repo_id>/source_code#`

That base IRI is what lets the graph expose stable module, function, file, and
related entity anchors that sibling memory and workflow-provenance features can
link to later.

The schema files loaded into the graph are:

- `elixir-core.ttl`
- `elixir-structure.ttl`
- `elixir-otp.ttl`
- `elixir-evolution.ttl`
- `elixir-shapes.ttl`

## Current Analysis Defaults In `jido_code`

The current repo integration does not load the entire upstream feature surface
equally.

The important defaults are:

- `include_expressions: true`
- `include_source_text: false`
- `include_git_info: false`
- `exclude_tests: true`

That means the current source-code graph usually includes:

- full expression-level semantic structure for repository code
- modules, functions, clauses, guards, calls, patterns, control flow, and OTP
  modeling
- stable repository-scoped IRIs for source entities

It usually does not include:

- raw source text literals
- test files
- git-derived evolution individuals unless analysis is run with git information
  enabled explicitly

The `evo:` ontology is still loaded as schema, but the product path does not
assume commit and version facts are populated in normal operation.

## The Ontology Layers

The most useful namespaces in day-to-day `jido_code` work are:

| Prefix | Role | Typical facts |
|-------|------|---------------|
| `core:` | AST and expression semantics | literals, call expressions, control flow, pattern matching, guards |
| `struct:` | Elixir code structure | modules, functions, clauses, specs, protocols, behaviours, structs |
| `otp:` | OTP runtime patterns | GenServer, Supervisor, Agent, Task, ETS, callback modeling |
| `evo:` | change and provenance vocabulary | repository, version, changeset, commit concepts |
| `shapes:` | validation vocabulary | SHACL constraints over the ontology model |

In practice:

- `struct:` is the main entry point for repository browsing.
- `core:` matters when you need expression-level detail.
- `otp:` matters when you are tracing runtime patterns instead of only static
  module/function structure.
- `evo:` is mostly future-facing or explicitly enabled provenance detail in the
  current `jido_code` integration.
- `shapes:` is mostly useful when debugging validation or ontology completeness,
  not for normal product-facing queries.

## What Kind Of Information The Graph Can Provide

### Repository And File Structure

The graph can represent:

- source files
- modules and nested modules
- module attributes and directives
- repository-scoped IRIs for those entities

Typical questions:

- which modules exist in this repository?
- which file defines this module?
- which modules use or require another module?

### Function-Level Structure

The graph can represent:

- function names
- arities
- public vs private visibility
- ordered clauses
- parameters
- guards
- optional specs

Typical questions:

- which functions does this module define?
- which functions have multiple clauses?
- which functions rely on guards or pattern-matching-heavy heads?

### Expression-Level Semantics

Because `jido_code` enables full expression extraction, the graph can represent:

- local and remote calls
- anonymous functions and captures
- literals and operators
- `if`, `case`, `cond`, `with`, `receive`, and `try`
- pattern matching structures

Typical questions:

- which functions have a top-level `receive` body?
- which functions rely on guard expressions?
- which calls or control-flow forms appear in a specific area?

This is the main reason the current integration requires the full ontology
profile instead of a structural-only pass.

### OTP Runtime Patterns

The graph can represent:

- GenServer implementations
- supervisors and restart strategies
- child specifications
- agents and tasks
- ETS tables

Typical questions:

- which modules implement GenServer behavior?
- where are supervisor trees declared?
- which child specs or restart patterns appear in the repo?

### Type And Interface Structure

The graph can represent:

- protocols and protocol implementations
- behaviours and behaviour implementations
- structs and struct fields
- callback and type-related entities

Typical questions:

- which modules implement a behaviour?
- which protocols are defined or implemented?
- where are struct fields or callback-oriented surfaces concentrated?

### Impact And Cross-Linking

The graph can represent outgoing and incoming semantic edges around a stable
source entity IRI.

Typical questions:

- what predicates point outward from this module or function?
- which repo-scoped entities point back at it?
- what bounded semantic neighborhood should be turned into a governed finding?

This is the capability that the current `impact` helper wraps for product-owned
services.

## What `jido_code` Already Exposes As Bounded Helpers

Product-facing and workflow-facing code should start with the bounded helper
surfaces instead of hand-writing SPARQL.

| Need | Product boundary | Workspace boundary |
|------|------------------|-------------------|
| browse modules | `SourceCodeGraph.ProductService.modules/3` | `AgentWorkspace.find_source_code_graph_modules/3` |
| browse functions | `SourceCodeGraph.ProductService.functions/3` | `AgentWorkspace.find_source_code_graph_functions/3` |
| inspect OTP/runtime patterns | `SourceCodeGraph.ProductService.runtime_patterns/3` | `AgentWorkspace.find_source_code_graph_runtime_patterns/3` |
| trace semantic impact | `SourceCodeGraph.ProductService.impact/3` | `AgentWorkspace.trace_source_code_graph_impact/3` |
| explicit SPARQL | not exposed to product surfaces | `AgentWorkspace.query_source_code_graph/4` |

That split is intentional:

- product surfaces get bounded projections
- explicit SPARQL remains an explicit repo-scoped action
- the query surface automatically targets the repository-local `source_code`
  graph and rejects explicit `GRAPH` clauses

## Query Conventions

`JidoCode.SourceCodeGraph.Query` injects the `ElixirOntologies` prefix map, so
the standard prefixes are available automatically.

Examples in this guide still include explicit `PREFIX` lines because they are
easier to read in documentation.

When adapting the examples below:

- replace `<repo-base-iri>` with
  `https://jido.run/managed_repos/<managed_repo_id>/source_code#`
- do not add an explicit `GRAPH` clause
- scope repo-local queries with `STRSTARTS(STR(?subject), "<repo-base-iri>")`
  when you want only repository-derived individuals

## Example Queries

### 1. List Modules In The Repository

Use this when you want a simple semantic inventory of repo modules.

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module ?module_name
WHERE {
  ?module a struct:Module .
  OPTIONAL { ?module struct:moduleName ?module_name . }
  FILTER(STRSTARTS(STR(?module), "<repo-base-iri>"))
}
ORDER BY ?module_name ?module
LIMIT 25
```

Bounded equivalent:

- `AgentWorkspace.find_source_code_graph_modules/3`
- `SourceCodeGraph.ProductService.modules/3`

### 2. List Functions In A Specific Module

Use this when you already know the module and need a stable function inventory.

```sparql
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?function ?function_name ?arity
WHERE {
  ?module a struct:Module ;
          struct:moduleName "JidoCode.AgentWorkspace" ;
          struct:containsFunction ?function .
  ?function a struct:Function ;
            struct:functionName ?function_name ;
            struct:arity ?arity .
}
ORDER BY ?function_name ?arity
LIMIT 100
```

Bounded equivalent:

- `AgentWorkspace.find_source_code_graph_functions/3`
- `SourceCodeGraph.ProductService.functions/3`

### 3. Find Functions With Guards

Use this when you want pattern-matching or clause-selection complexity, not
just a flat function list.

```sparql
PREFIX core:   <https://w3id.org/elixir-code/core#>
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module_name ?function_name ?arity
WHERE {
  ?module a struct:Module ;
          struct:moduleName ?module_name ;
          struct:containsFunction ?function .
  ?function a struct:Function ;
            struct:functionName ?function_name ;
            struct:arity ?arity ;
            struct:hasClause ?clause .
  ?clause struct:hasHead ?head .
  ?head core:hasGuard ?guard .
  FILTER(STRSTARTS(STR(?module), "<repo-base-iri>"))
}
ORDER BY ?module_name ?function_name ?arity
LIMIT 100
```

This kind of query demonstrates why the full expression profile matters. A
plain structural-only module/function index would not give you guard-level
semantic detail.

### 4. Find Top-Level `receive` Bodies

Use this when you want concurrency-oriented code shapes rather than only OTP
behaviour tags.

```sparql
PREFIX core:   <https://w3id.org/elixir-code/core#>
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?module_name ?function_name ?arity
WHERE {
  ?module a struct:Module ;
          struct:moduleName ?module_name ;
          struct:containsFunction ?function .
  ?function a struct:Function ;
            struct:functionName ?function_name ;
            struct:arity ?arity ;
            struct:hasClause ?clause .
  ?clause struct:hasBody ?body .
  ?body a core:ReceiveExpression .
  FILTER(STRSTARTS(STR(?module), "<repo-base-iri>"))
}
ORDER BY ?module_name ?function_name ?arity
LIMIT 100
```

This is not currently one of the product-owned helper projections, but it is a
good example of the deeper questions explicit semantic tooling can answer.

### 5. Find GenServer Implementations

Use this when you want OTP behavior modeling instead of only static structure.

```sparql
PREFIX otp:    <https://w3id.org/elixir-code/otp#>
PREFIX struct: <https://w3id.org/elixir-code/structure#>

SELECT ?subject ?module_name
WHERE {
  ?subject a otp:GenServerImplementation ;
           otp:implementsOTPBehaviour otp:GenServer .
  OPTIONAL { ?subject struct:moduleName ?module_name . }
  FILTER(STRSTARTS(STR(?subject), "<repo-base-iri>"))
}
ORDER BY ?module_name ?subject
LIMIT 50
```

Bounded equivalent:

- `AgentWorkspace.find_source_code_graph_runtime_patterns/3`
- `SourceCodeGraph.ProductService.runtime_patterns/3`

The bounded runtime-pattern helper is broader than this exact query. It returns
repo-scoped subjects typed with any `otp:` class and is useful when you want a
quick runtime-pattern preview rather than a hand-tuned OTP query.

### 6. Trace Outgoing Impact From A Known Function IRI

Use this when you already have a stable subject IRI and want its immediate
semantic neighborhood.

```sparql
SELECT ?predicate ?target
WHERE {
  <https://jido.run/managed_repos/<managed_repo_id>/source_code#JidoCode.AgentWorkspace/source_code_graph_status/3>
    ?predicate ?target .
  FILTER(
    !isIRI(?target) ||
      STRSTARTS(STR(?target), "<repo-base-iri>") ||
      STRSTARTS(STR(?target), "https://w3id.org/elixir-code/")
  )
}
ORDER BY ?predicate ?target
LIMIT 50
```

Bounded equivalent:

- `AgentWorkspace.trace_source_code_graph_impact/3`
- `SourceCodeGraph.ProductService.impact/3`

This is a good fit when you are turning semantic neighborhood data into a
governed `Observation`, `Assessment`, `Evidence`, or work-item seed.

## When To Reach For Explicit SPARQL

Explicit SPARQL is a good fit when:

- the bounded helpers are too coarse
- you need a temporary exploratory query for review or explanation work
- you want expression-level structure that the current product helpers do not
  project directly
- you are testing ontology assumptions or checking whether a specific class or
  property is being emitted

Bounded helpers are a better fit when:

- product code needs stable shaped output
- operator surfaces need explainable degraded-state behavior
- the question is one of the common module/function/runtime-pattern/impact
  lookups already modeled in `ProductService`

## What To Keep In Mind

- The graph always mixes schema and project individuals in the same
  `source_code` named graph.
- Repo-derived entities should be scoped by the repository base IRI.
- `core:` and `struct:` are usually the most important namespaces.
- `otp:` becomes valuable once you care about runtime patterns, supervision, or
  callback structure.
- `evo:` vocabulary may be present even when git-derived facts are not
  populated.
- Product features should consume bounded projections first and turn meaningful
  findings back into governed records.

## Read Next

Continue with
[`08-memory-graph-and-workflow-provenance.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08-memory-graph-and-workflow-provenance.md).
