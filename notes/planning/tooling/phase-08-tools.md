# Phase 8: Elixir Ontology Code Exploration Tools (TripleStore)

This phase implements LLM-facing tools for exploring Elixir source code through the knowledge graph ontology defined in `~/code/elixir-ontologies/ontology/` using **TripleStore with named graphs**. These tools enable an LLM agent to navigate, understand, and analyze Elixir codebases using semantic queries over RDF triples representing code structure, OTP patterns, and evolution history.

> **STATUS:** Implementation blocked until TripleStore named graph refactor completes.

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  TripleStore Instance (per project)                             │
├─────────────────────────────────────────────────────────────────┤
│  Default Graph: Jido + Elixir Ontology (read-only reference)    │
│    - ~/code/elixir-ontologies/ontology/*.ttl loaded at startup  │
│  Named Graph 1: urn:jido:graph:memory:{project_id} (Phase 7)    │
│  Named Graph 2: urn:jido:graph:code:{project_id}                │
│    - Parsed Elixir source code structure                        │
└─────────────────────────────────────────────────────────────────┘
```

## Handler Pattern Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                           │
│  e.g., {"name": "code_find_function", "arguments": {...}}       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Handler.execute/2 validates and processes                      │
│  - Uses HandlerHelpers for session context                      │
│  - Validates module/function names                              │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  TripleStoreManager.get_project_context/1                       │
│  - Returns context with db, code_graph_iri                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  CodeStore (SPARQL-based operations)                            │
│  - find_function/2, get_module/2, call_graph/2                 │
│  - All operations use SPARQL with GRAPH clause                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Result formatted as JSON for LLM                               │
│  - Module details, function signatures                          │
│  - Call graphs, dependency trees                                │
│  - Source code snippets with line numbers                       │
└─────────────────────────────────────────────────────────────────┘
```

## Ontology Foundation

The Elixir source code ontology is defined in 5 TTL files:

| TTL File | Purpose | Key Classes |
|----------|---------|-------------|
| `elixir-core.ttl` | AST, expressions, patterns, operators | `AST`, `Expression`, `Pattern`, `Operator`, `Keyword`, `Atom` |
| `elixir-structure.ttl` | Modules, functions, types, behaviours | `Module`, `Function`, `FunctionClause`, `FunctionSpec`, `Typespec`, `Protocol` |
| `elixir-otp.ttl` | OTP patterns, supervision, processes | `GenServer`, `Supervisor`, `Agent`, `Task`, `ETS`, `OTPBehaviour` |
| `elixir-evolution.ttl` | Git history, commits, versioning | `Commit`, `CodeVersion`, `ChangeSet`, `CommitDiff` |
| `elixir-shapes.ttl` | SHACL validation shapes | Shape definitions for validation |

### Key Ontology Concepts

**Function Identity**: In Elixir, a function is uniquely identified by `{Module, Name, Arity}`. The ontology models this as:
- `structure:Module` contains many `structure:Function`
- Each `structure:Function` has `structure:functionName` and `structure:arity`
- Functions can have multiple `structure:FunctionClause` for pattern matching

**Relationships**:
- `structure:containsFunction` - Module → Function
- `structure:belongsTo` - Function → Module
- `structure:callsFunction` - Function → Function (call graph)
- `structure:hasSpec` - Function → FunctionSpec (typespecs)
- `otp:implementsBehaviour` - Module → OTPBehaviour

## Tools in This Phase

| Tool | Priority | Purpose | Status |
|------|----------|---------|--------|
| `code_find_function` | P0 | Find functions by Module.function/arity | ⬜ Initial |
| `code_get_module` | P0 | Get full module details with docs and functions | ⬜ Initial |
| `code_function_definition` | P0 | Get function source with clauses and specs | ⬜ Initial |
| `code_list_modules` | P0 | List all modules in project with filtering | ⬜ Initial |
| `code_call_graph` | P1 | Find callers/callees of a function | ⬜ Initial |
| `code_module_graph` | P1 | Module dependency graph | ⬜ Initial |
| `code_find_usages` | P1 | Find all references to function/module | ⬜ Initial |
| `code_get_typespec` | P1 | Get typespecs and dialyzer info | ⬜ Initial |
| `code_otp_tree` | P2 | Supervision tree discovery | ⬜ Initial |
| `code_behaviour_implementations` | P2 | Find behaviour implementations | ⬜ Initial |
| `code_macro_expansions` | P2 | Understand macro usage | ⬜ Initial |
| `code_protocol_implementations` | P2 | Protocol/implementation discovery | ⬜ Initial |
| `code_complexity_analysis` | P3 | Code complexity metrics | ⏸️ Deferred |
| `code_sparql_query` | P3 | Raw SPARQL for power users | ⏸️ Deferred |
| `code_evolution` | P3 | Git-based history analysis | ⏸️ Deferred |
| `code_knowledge_gap` | P3 | Unknown/unexplored areas | ⏸️ Deferred |

> **Note:** P0-P2 tools (12 total) will be implemented initially. P3 tools are deferred for a later phase.

---

## Section 8.0: Foundation Layer

### 8.0.1 CodeStore Module

**Status:** ⬜ Initial

Create a wrapper module for code graph operations using SPARQL.

#### Tasks

- [ ] 8.0.1.1 Create `lib/jido_code/code_store.ex`
  - [ ] Implement `find_function/2` - SELECT with MFA filters
  - [ ] Implement `get_module/2` - CONSTRUCT for full module details
  - [ ] Implement `call_graph/5` - SELECT with callsFunction property paths
  - [ ] Implement `module_graph/4` - SELECT with use/alias/import relationships
  - [ ] Implement `find_usages/3` - SELECT for references
  - [ ] Implement `get_typespec/3` - SELECT for @spec definitions
  - [ ] Implement `otp_tree/3` - SELECT for supervisor children
  - [ ] Implement `behaviour_implementations/3` - SELECT with implementsBehaviour
  - [ ] Implement `protocol_implementations/3` - SELECT for defimpl
  - [ ] Implement `macro_expansions/3` - SELECT for defmacro/expand

- [ ] 8.0.1.2 Create unit tests for CodeStore
  - [ ] Test find_function generates valid SPARQL
  - [ ] Test GRAPH clause includes correct code_graph_iri
  - [ ] Test filters are correctly applied
  - [ ] Test property paths for call graph traversal

### 8.0.2 Code SPARQL Queries Module

**Status:** ⬜ Initial

Create a module with reusable SPARQL query templates for code exploration.

#### Tasks

- [ ] 8.0.2.1 Create `lib/jido_code/code/sparql_queries.ex`
  - [ ] Implement `find_function_query/4` template with MFA filters
  - [ ] Implement `get_module_query/2` template with OPTIONAL clauses
  - [ ] Implement `call_graph_query/5` template with property paths
  - [ ] Implement `module_graph_query/4` template
  - [ ] Implement `find_usages_query/4` template
  - [ ] Implement `get_typespec_query/3` template
  - [ ] Implement `otp_tree_query/3` template
  - [ ] Implement `behaviour_implementations_query/3` template
  - [ ] Implement `protocol_implementations_query/3` template

- [ ] 8.0.2.2 Add unit tests for Code SPARQL queries
  - [ ] Test queries generate valid SPARQL
  - [ ] Test structure: prefix is used
  - [ ] Test GRAPH clause is included
  - [ ] Test property paths are correct

### 8.0.3 Ontology Loading

**Status:** ⬜ Initial

Load Elixir ontology TTL files into TripleStore default graph.

#### Tasks

- [ ] 8.0.3.1 Create `lib/jido_code/code/ontology_loader.ex`
  - [ ] Implement `load_elixir_ontology/1` to load all 5 TTL files
  - [ ] Use `TripleStore.load/2` for each file
  - [ ] Track loaded ontology version
  - [ ] Return count of triples loaded

- [ ] 8.0.3.2 Add to TripleStore.Project initialization
  - [ ] Load ontology after opening TripleStore
  - [ ] Skip if ontology already loaded
  - [ ] Emit telemetry on ontology load

---

## Section 8.1: code_find_function Tool (P0)

**Status:** ⬜ Initial

Find functions by their MFA (Module, Function, Arity) identity. This is the primary entry point for function discovery.

### 8.1.1 Tool Definition

- [ ] Create `lib/jido_code/tools/definitions/code_exploration.ex`
- [ ] Define schema:
  ```elixir
  %{
    name: "code_find_function",
    description: "Find Elixir functions by module, name, and optionally arity. Returns matching functions with their location and basic metadata.",
    parameters: [
      %{name: "module", type: :string, required: false,
        description: "Module name (e.g., 'MyApp.User') or pattern (e.g., 'MyApp.*')"},
      %{name: "function_name", type: :string, required: false,
        description: "Function name (e.g., 'get_by_id') or pattern"},
      %{name: "arity", type: :integer, required: false,
        description: "Exact arity to match"},
      %{name: "include_private", type: :boolean, required: false,
        description: "Include private functions (default: false)"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results (default: 20, max: 100)"}
    ]
  }
  ```
- [ ] Register in `CodeExploration.all/0`

### 8.1.2 Handler Implementation

- [ ] Create `lib/jido_code/tools/handlers/code_exploration.ex`
- [ ] Add `CodeFindFunction` handler module
- [ ] Validate at least one of module or function_name is provided
- [ ] Get project_id from context
- [ ] Call `TripleStoreManager.get_project_context/1`
- [ ] Call `CodeStore.find_function/2` with SPARQL query
- [ ] Support pattern matching with FILTER CONTAINS
- [ ] Return list of matching functions with metadata
- [ ] Emit telemetry `[:jido_code, :code, :find_function]`

**SPARQL Query Template:**
```sparql
PREFIX structure: <http://elixir-ontologies.org/ontology/structure#>

SELECT ?func ?module ?name ?arity ?visibility ?file ?line
WHERE {
  GRAPH <urn:jido:graph:code:{project_id}> {
    ?func a structure:Function ;
          structure:functionName ?name ;
          structure:arity ?arity ;
          structure:belongsTo ?module ;
          structure:visibility ?visibility ;
          structure:definedIn ?file ;
          structure:startLine ?line .
    FILTER(CONTAINS(LCASE(STR(?module)), "{module_lc}"))
    FILTER(CONTAINS(LCASE(STR(?name)), "{name_lc}"))
    {optional_filters}
  }
}
LIMIT {limit}
```

### 8.1.3 Unit Tests

- [ ] Test finds function by exact module and name
- [ ] Test finds all functions in a module
- [ ] Test finds functions by name across modules
- [ ] Test respects arity filter
- [ ] Test include_private option
- [ ] Test pattern matching with wildcards
- [ ] Test returns empty for no matches
- [ ] Test respects limit parameter
- [ ] Test validates input parameters
- [ ] Test telemetry emission

---

## Section 8.2: code_get_module Tool (P0)

**Status:** ⬜ Initial

Get comprehensive information about a module including documentation, all functions, types, and behaviours.

### 8.2.1 Tool Definition

- [ ] Add `code_get_module/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_get_module",
    description: "Get complete information about an Elixir module including documentation, functions, types, and implemented behaviours.",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Full module name (e.g., 'MyApp.Accounts.User')"},
      %{name: "include_source", type: :boolean, required: false,
        description: "Include full module source code (default: false)"},
      %{name: "include_private", type: :boolean, required: false,
        description: "Include private functions in listing (default: false)"}
    ]
  }
  ```

### 8.2.2 Handler Implementation

- [ ] Add `CodeGetModule` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.get_module/2`
- [ ] Query for module metadata:
  - Module documentation (@moduledoc)
  - Source file path and line range
  - All public functions with arities
  - All types defined
  - Behaviours implemented (GenServer, etc.)
  - Modules used/aliased/imported
- [ ] Format as structured JSON with sections
- [ ] Optionally include full source if requested
- [ ] Emit telemetry `[:jido_code, :code, :get_module]`

**SPARQL Query Template:**
```sparql
PREFIX structure: <http://elixir-ontologies.org/ontology/structure#>
PREFIX otp: <http://elixir-ontologies.org/ontology/otp#>

CONSTRUCT {
  ?s ?p ?o
}
WHERE {
  GRAPH <urn:jido:graph:code:{project_id}> {
    ?module structure:moduleName "{module_name}" .
    ?s ?p ?o .
    { ?module structure:hasFunction ?func }
    UNION
    { ?module structure:hasType ?type }
    UNION
    { ?module otp:implementsBehaviour ?behaviour }
  }
}
```

### 8.2.3 Unit Tests

- [ ] Test retrieves module with functions
- [ ] Test includes moduledoc when present
- [ ] Test lists behaviours implemented
- [ ] Test lists types defined
- [ ] Test include_source option
- [ ] Test include_private option
- [ ] Test handles non-existent module
- [ ] Test handles module with no documentation
- [ ] Test telemetry emission

---

## Section 8.3: code_function_definition Tool (P0)

**Status:** ⬜ Initial

Get the complete definition of a function including all clauses, guards, specs, and documentation.

### 8.3.1 Tool Definition

- [ ] Add `code_function_definition/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_function_definition",
    description: "Get complete function definition including all clauses, pattern matching, guards, typespecs, and documentation.",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Module containing the function"},
      %{name: "function", type: :string, required: true,
        description: "Function name"},
      %{name: "arity", type: :integer, required: false,
        description: "Specific arity (omit to get all arities)"},
      %{name: "include_callers", type: :boolean, required: false,
        description: "Include list of functions that call this one (default: false)"},
      %{name: "include_callees", type: :boolean, required: false,
        description: "Include list of functions this one calls (default: false)"}
    ]
  }
  ```

### 8.3.2 Handler Implementation

- [ ] Add `CodeFunctionDefinition` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore` for function details:
  - All clauses with pattern matching
  - Guards for each clause
  - @doc documentation
  - @spec typespec
  - Source code with line numbers
  - Visibility (public/private)
- [ ] For multi-clause functions, show all clauses in order
- [ ] Optionally include caller/callee information via call_graph
- [ ] Emit telemetry `[:jido_code, :code, :function_definition]`

### 8.3.3 Unit Tests

- [ ] Test retrieves single-clause function
- [ ] Test retrieves multi-clause function
- [ ] Test includes guards
- [ ] Test includes typespec
- [ ] Test includes @doc
- [ ] Test handles function without spec
- [ ] Test arity filter
- [ ] Test include_callers option
- [ ] Test include_callees option
- [ ] Test handles non-existent function
- [ ] Test telemetry emission

---

## Section 8.4: code_list_modules Tool (P0)

**Status:** ⬜ Initial

List all modules in the project with filtering by namespace, behaviour, or other criteria.

### 8.4.1 Tool Definition

- [ ] Add `code_list_modules/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_list_modules",
    description: "List all modules in the project with optional filtering by namespace, behaviour, or pattern.",
    parameters: [
      %{name: "namespace", type: :string, required: false,
        description: "Filter to modules under this namespace (e.g., 'MyApp.Accounts')"},
      %{name: "implements_behaviour", type: :string, required: false,
        description: "Filter to modules implementing this behaviour (e.g., 'GenServer')"},
      %{name: "pattern", type: :string, required: false,
        description: "Regex pattern for module name"},
      %{name: "include_count", type: :boolean, required: false,
        description: "Include function count for each module (default: true)"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results (default: 50, max: 500)"}
    ]
  }
  ```

### 8.4.2 Handler Implementation

- [ ] Add `CodeListModules` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.list_modules/2` with SPARQL
- [ ] Query for all modules with filtering
- [ ] Support namespace prefix matching via FILTER STARTSWITH
- [ ] Support behaviour filtering via otp:implementsBehaviour
- [ ] Return sorted list with optional function counts
- [ ] Emit telemetry `[:jido_code, :code, :list_modules]`

### 8.4.3 Unit Tests

- [ ] Test lists all modules
- [ ] Test filters by namespace prefix
- [ ] Test filters by behaviour
- [ ] Test pattern matching
- [ ] Test respects limit
- [ ] Test include_count option
- [ ] Test returns empty for no matches
- [ ] Test combination of filters
- [ ] Test telemetry emission

---

## Section 8.5: code_call_graph Tool (P1)

**Status:** ⬜ Initial

Discover the call graph around a function - who calls it and what it calls.

### 8.5.1 Tool Definition

- [ ] Add `code_call_graph/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_call_graph",
    description: "Get the call graph for a function: what functions call it (callers) and what functions it calls (callees).",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Module containing the function"},
      %{name: "function", type: :string, required: true,
        description: "Function name"},
      %{name: "arity", type: :integer, required: false,
        description: "Specific arity"},
      %{name: "direction", type: :string, required: false,
        description: "Direction: 'callers', 'callees', or 'both' (default: 'both')"},
      %{name: "depth", type: :integer, required: false,
        description: "Traversal depth (default: 1, max: 5)"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results per direction (default: 20)"}
    ]
  }
  ```

### 8.5.2 Handler Implementation

- [ ] Add `CodeCallGraph` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.call_graph/5`
- [ ] Query using `structure:callsFunction` relationship
- [ ] Support bidirectional traversal
- [ ] Support depth with property paths: `structure:callsFunction{1,depth}`
- [ ] Group results by caller/callee category
- [ ] Emit telemetry `[:jido_code, :code, :call_graph]`

**SPARQL Query Template:**
```sparql
PREFIX structure: <http://elixir-ontologies.org/ontology/structure#>

SELECT ?caller ?caller_module ?caller_name ?caller_arity
WHERE {
  GRAPH <urn:jido:graph:code:{project_id}> {
    ?target structure:belongsTo ?target_mod ;
             structure:functionName "{function_name}" ;
             structure:arity {arity} .

    ?caller structure:callsFunction* ?target ;
            structure:belongsTo ?caller_mod ;
            structure:functionName ?caller_name ;
            structure:arity ?caller_arity .
  }
}
LIMIT {limit}
```

### 8.5.3 Unit Tests

- [ ] Test finds direct callers
- [ ] Test finds direct callees
- [ ] Test both direction
- [ ] Test depth traversal
- [ ] Test respects limit
- [ ] Test handles function with no callers
- [ ] Test handles function with no callees
- [ ] Test arity filtering
- [ ] Test telemetry emission

---

## Section 8.6: code_module_graph Tool (P1)

**Status:** ⬜ Initial

Discover module-level dependencies - which modules depend on which.

### 8.6.1 Tool Definition

- [ ] Add `code_module_graph/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_module_graph",
    description: "Get module dependency graph: which modules use/alias/import this module, and which modules this module depends on.",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Module to analyze"},
      %{name: "direction", type: :string, required: false,
        description: "Direction: 'dependents', 'dependencies', or 'both' (default: 'both')"},
      %{name: "include_stdlib", type: :boolean, required: false,
        description: "Include Elixir/Erlang stdlib modules (default: false)"},
      %{name: "depth", type: :integer, required: false,
        description: "Traversal depth (default: 1, max: 3)"}
    ]
  }
  ```

### 8.6.2 Handler Implementation

- [ ] Add `CodeModuleGraph` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.module_graph/4`
- [ ] Track use/alias/import relationships
- [ ] Support filtering out stdlib via FILTER NOT EXISTS
- [ ] Support depth traversal
- [ ] Emit telemetry `[:jido_code, :code, :module_graph]`

### 8.6.3 Unit Tests

- [ ] Test finds dependent modules
- [ ] Test finds dependencies
- [ ] Test both direction
- [ ] Test include_stdlib filter
- [ ] Test depth traversal
- [ ] Test handles isolated module
- [ ] Test handles cyclic dependencies
- [ ] Test telemetry emission

---

## Section 8.7: code_find_usages Tool (P1)

**Status:** ⬜ Initial

Find all places where a function or module is referenced.

### 8.7.1 Tool Definition

- [ ] Add `code_find_usages/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_find_usages",
    description: "Find all references to a function or module throughout the codebase.",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Module name"},
      %{name: "function", type: :string, required: false,
        description: "Function name (omit for module-level usages)"},
      %{name: "arity", type: :integer, required: false,
        description: "Specific arity"},
      %{name: "include_definition", type: :boolean, required: false,
        description: "Include the definition location (default: true)"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results (default: 50)"}
    ]
  }
  ```

### 8.7.2 Handler Implementation

- [ ] Add `CodeFindUsages` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.find_usages/3`
- [ ] Find call sites for functions via structure:callsFunction
- [ ] Find alias/import/use sites for modules
- [ ] Return with file and line number context
- [ ] Emit telemetry `[:jido_code, :code, :find_usages]`

### 8.7.3 Unit Tests

- [ ] Test finds function calls
- [ ] Test finds module aliases
- [ ] Test finds module imports
- [ ] Test finds module uses
- [ ] Test respects limit
- [ ] Test include_definition option
- [ ] Test handles no usages
- [ ] Test telemetry emission

---

## Section 8.8: code_get_typespec Tool (P1)

**Status:** ⬜ Initial

Get typespecs and Dialyzer information for a function.

### 8.8.1 Tool Definition

- [ ] Add `code_get_typespec/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_get_typespec",
    description: "Get typespec and Dialyzer information for a function including @spec, parameter types, and return type.",
    parameters: [
      %{name: "module", type: :string, required: true,
        description: "Module containing the function"},
      %{name: "function", type: :string, required: true,
        description: "Function name"},
      %{name: "arity", type: :integer, required: false,
        description: "Specific arity"},
      %{name: "include_related_types", type: :boolean, required: false,
        description: "Include custom type definitions used (default: true)"}
    ]
  }
  ```

### 8.8.2 Handler Implementation

- [ ] Add `CodeGetTypespec` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.get_typespec/3`
- [ ] Query for @spec definitions via structure:hasSpec
- [ ] Parse and format type information
- [ ] Optionally include related @type definitions
- [ ] Emit telemetry `[:jido_code, :code, :get_typespec]`

### 8.8.3 Unit Tests

- [ ] Test retrieves simple typespec
- [ ] Test retrieves complex typespec
- [ ] Test handles function without spec
- [ ] Test includes related types
- [ ] Test multiple arities
- [ ] Test handles custom types
- [ ] Test telemetry emission

---

## Section 8.9: code_otp_tree Tool (P2)

**Status:** ⬜ Initial

Discover the OTP supervision tree structure.

### 8.9.1 Tool Definition

- [ ] Add `code_otp_tree/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_otp_tree",
    description: "Discover the OTP supervision tree structure starting from a supervisor module.",
    parameters: [
      %{name: "supervisor", type: :string, required: false,
        description: "Starting supervisor (default: Application supervisor)"},
      %{name: "depth", type: :integer, required: false,
        description: "Maximum depth to traverse (default: 3)"},
      %{name: "include_workers", type: :boolean, required: false,
        description: "Include worker processes in tree (default: true)"}
    ]
  }
  ```

### 8.9.2 Handler Implementation

- [ ] Add `CodeOtpTree` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.otp_tree/3`
- [ ] Query for supervisor/child relationships using `otp:supervises`
- [ ] Build tree structure
- [ ] Include restart strategies and child specs
- [ ] Emit telemetry `[:jido_code, :code, :otp_tree]`

### 8.9.3 Unit Tests

- [ ] Test finds supervision tree
- [ ] Test respects depth limit
- [ ] Test include_workers option
- [ ] Test handles dynamic supervisors
- [ ] Test handles no supervisors
- [ ] Test nested supervisors
- [ ] Test telemetry emission

---

## Section 8.10: code_behaviour_implementations Tool (P2)

**Status:** ⬜ Initial

Find all modules implementing a specific behaviour.

### 8.10.1 Tool Definition

- [ ] Add `code_behaviour_implementations/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_behaviour_implementations",
    description: "Find all modules that implement a specific behaviour (GenServer, Supervisor, custom behaviours).",
    parameters: [
      %{name: "behaviour", type: :string, required: true,
        description: "Behaviour name (e.g., 'GenServer', 'MyApp.CustomBehaviour')"},
      %{name: "include_callbacks", type: :boolean, required: false,
        description: "Include which callbacks each module implements (default: true)"},
      %{name: "namespace", type: :string, required: false,
        description: "Filter to modules under this namespace"}
    ]
  }
  ```

### 8.10.2 Handler Implementation

- [ ] Add `CodeBehaviourImplementations` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.behaviour_implementations/3`
- [ ] Query using `otp:implementsBehaviour` relationship
- [ ] List implemented callbacks for each module
- [ ] Support namespace filtering
- [ ] Emit telemetry `[:jido_code, :code, :behaviour_implementations]`

### 8.10.3 Unit Tests

- [ ] Test finds GenServer implementations
- [ ] Test finds Supervisor implementations
- [ ] Test finds custom behaviour implementations
- [ ] Test include_callbacks option
- [ ] Test namespace filtering
- [ ] Test handles no implementations
- [ ] Test telemetry emission

---

## Section 8.11: code_macro_expansions Tool (P2)

**Status:** ⬜ Initial

Understand macro usage in the codebase.

### 8.11.1 Tool Definition

- [ ] Add `code_macro_expansions/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_macro_expansions",
    description: "Find and understand macro usage: where macros are defined and where they are used.",
    parameters: [
      %{name: "module", type: :string, required: false,
        description: "Module to search for macro usage"},
      %{name: "macro_name", type: :string, required: false,
        description: "Specific macro to find usages of"},
      %{name: "list_definitions", type: :boolean, required: false,
        description: "List all macro definitions (default: false)"}
    ]
  }
  ```

### 8.11.2 Handler Implementation

- [ ] Add `CodeMacroExpansions` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.macro_expansions/3`
- [ ] Query for defmacro definitions
- [ ] Find macro usage sites
- [ ] Show expansion context
- [ ] Emit telemetry `[:jido_code, :code, :macro_expansions]`

### 8.11.3 Unit Tests

- [ ] Test finds macro definitions
- [ ] Test finds macro usages
- [ ] Test list_definitions option
- [ ] Test specific macro search
- [ ] Test handles no macros
- [ ] Test telemetry emission

---

## Section 8.12: code_protocol_implementations Tool (P2)

**Status:** ⬜ Initial

Discover protocols and their implementations.

### 8.12.1 Tool Definition

- [ ] Add `code_protocol_implementations/0` to definitions
- [ ] Define schema:
  ```elixir
  %{
    name: "code_protocol_implementations",
    description: "Find protocol definitions and their implementations for various types.",
    parameters: [
      %{name: "protocol", type: :string, required: false,
        description: "Protocol name to find implementations for"},
      %{name: "for_type", type: :string, required: false,
        description: "Find all protocol implementations for this type"},
      %{name: "list_protocols", type: :boolean, required: false,
        description: "List all defined protocols (default: false)"}
    ]
  }
  ```

### 8.12.2 Handler Implementation

- [ ] Add `CodeProtocolImplementations` handler module
- [ ] Get project_id from context
- [ ] Call `CodeStore.protocol_implementations/3`
- [ ] Query for `defprotocol` definitions
- [ ] Query for `defimpl` implementations
- [ ] Map protocols to implementing types
- [ ] Emit telemetry `[:jido_code, :code, :protocol_implementations]`

### 8.12.3 Unit Tests

- [ ] Test finds protocol definitions
- [ ] Test finds implementations for protocol
- [ ] Test finds implementations for type
- [ ] Test list_protocols option
- [ ] Test handles protocol with no implementations
- [ ] Test handles built-in protocols
- [ ] Test telemetry emission

---

## Section 8.13: Integration Tests

**Status:** ⬜ Initial

### 8.13.1 Handler Integration

- [ ] Create `test/jido_code/integration/tools_phase8_test.exs`
- [ ] Test all tools execute through Executor → Handler chain
- [ ] Test project context propagation
- [ ] Test telemetry events are emitted for all tools

### 8.13.2 Code Discovery Lifecycle

- [ ] Test: code_list_modules → code_get_module → code_function_definition
- [ ] Test: code_find_function → code_call_graph → code_find_usages
- [ ] Test: code_list_modules(implements: "GenServer") → code_otp_tree
- [ ] Test: code_get_module → code_get_typespec for functions

### 8.13.3 Cross-Tool Integration

- [ ] Test code_call_graph results match code_find_usages
- [ ] Test code_module_graph dependencies align with code_find_usages
- [ ] Test code_behaviour_implementations consistent with code_get_module
- [ ] Test code_protocol_implementations consistent with code_get_module

### 8.13.4 Performance Tests

- [ ] Test large module list performance
- [ ] Test deep call graph traversal
- [ ] Test many-result queries respect limits

---

## Section 8.14: Code Graph Indexer

**Status:** ⬜ Initial

A separate component is needed to parse Elixir source code and populate the code graph.

### 8.14.1 Indexer Architecture

- [ ] Create `lib/jido_code/code/indexer.ex`
  - [ ] Scan project directory for .ex files
  - [ ] Parse each file with Elixir's Code.Formatter
  - [ ] Extract: modules, functions, macros, types, specs
  - [ ] Convert to RDF triples using ontology
  - [ ] Insert into code graph via TripleStore

### 8.14.2 Incremental Updates

- [ ] Track file modification times
- [ ] Re-index only changed files
- [ ] Support full re-index command

---

## Section 8.15: Phase 8 Success Criteria

| Criterion | Priority | Status |
|-----------|----------|--------|
| **CodeStore**: SPARQL-based operations | P0 | ⬜ |
| **code_find_function**: Find by MFA pattern | P0 | ⬜ |
| **code_get_module**: Full module details | P0 | ⬜ |
| **code_function_definition**: Source + clauses + specs | P0 | ⬜ |
| **code_list_modules**: Filtered module listing | P0 | ⬜ |
| **code_call_graph**: Caller/callee discovery | P1 | ⬜ |
| **code_module_graph**: Module dependencies | P1 | ⬜ |
| **code_find_usages**: Reference discovery | P1 | ⬜ |
| **code_get_typespec**: Type information | P1 | ⬜ |
| **code_otp_tree**: Supervision tree | P2 | ⬜ |
| **code_behaviour_implementations**: Behaviour lookup | P2 | ⬜ |
| **code_macro_expansions**: Macro discovery | P2 | ⬜ |
| **code_protocol_implementations**: Protocol lookup | P2 | ⬜ |
| **Code Indexer**: Populate code graph | P0 | ⬜ |
| **Test coverage**: Minimum 80% | - | ⬜ |
| **code_complexity_analysis**: Metrics | P3 | ⏸️ Deferred |
| **code_sparql_query**: Raw SPARQL | P3 | ⏸️ Deferred |
| **code_evolution**: Git history | P3 | ⏸️ Deferred |
| **code_knowledge_gap**: Unknown areas | P3 | ⏸️ Deferred |

---

## Section 8.16: Phase 8 Critical Files

### Files to CREATE

| File | Purpose |
|------|---------|
| `lib/jido_code/code_store.ex` | Code graph operations wrapper |
| `lib/jido_code/code/sparql_queries.ex` | SPARQL query templates for code |
| `lib/jido_code/code/ontology_loader.ex` | Loads Elixir ontology TTL files |
| `lib/jido_code/code/indexer.ex` | Parses .ex files and populates code graph |
| `lib/jido_code/tools/definitions/code_exploration.ex` | All code exploration tool definitions |
| `lib/jido_code/tools/handlers/code_exploration.ex` | All code exploration handlers |
| `test/jido_code/tools/handlers/code_exploration_test.exs` | Handler unit tests |
| `test/jido_code/integration/tools_phase8_test.exs` | Integration tests |

### Files to MODIFY

| File | Changes |
|------|---------|
| `lib/jido_code/tools/definitions.ex` | Register code exploration tools |
| `lib/jido_code/triple_store/project.ex` | Load Elixir ontology on init |

### Reference Files (read-only)

| File | Purpose |
|------|---------|
| `~/code/elixir-ontologies/ontology/elixir-core.ttl` | AST ontology |
| `~/code/elixir-ontologies/ontology/elixir-structure.ttl` | Structure ontology |
| `~/code/elixir-ontologies/ontology/elixir-otp.ttl` | OTP ontology |
| `~/code/elixir-ontologies/ontology/elixir-evolution.ttl` | Evolution ontology |
| `~/code/elixir-ontologies/ontology/elixir-shapes.ttl` | SHACL shapes |

---

## Dependencies

**Blocking:** TripleStore named graph refactor must complete before implementation begins.

**Prerequisites:**
- Phase 7 foundation layer (TripleStoreManager, ProjectRegistry) must be complete
- Elixir ontology TTL files from `~/code/elixir-ontologies/ontology/`

**External:**
- `:triple_store` dependency added to mix.exs
- TripleStore library must support named graphs (GRAPH clauses, INSERT with GRAPH)

---

## Implementation Order

### Phase 8A: Foundation + P0 Tools
1. Create `CodeStore` module with SPARQL queries
2. Create `CodeSPARQLQueries` module
3. Create `OntologyLoader` for Elixir TTL files
4. Create code exploration definitions
5. Create code exploration handlers
6. Implement `code_find_function` (P0)
7. Implement `code_get_module` (P0)
8. Implement `code_function_definition` (P0)
9. Implement `code_list_modules` (P0)
10. Unit tests for all P0 handlers
11. Basic integration tests

### Phase 8B: Navigation Tools (P1)
1. Implement `code_call_graph` (P1)
2. Implement `code_module_graph` (P1)
3. Implement `code_find_usages` (P1)
4. Implement `code_get_typespec` (P1)
5. Tests for P1 handlers

### Phase 8C: OTP & Pattern Tools (P2)
1. Implement `code_otp_tree` (P2)
2. Implement `code_behaviour_implementations` (P2)
3. Implement `code_macro_expansions` (P2)
4. Implement `code_protocol_implementations` (P2)
5. Full integration tests

### Phase 8D: Code Indexer (Prerequisite)
1. Implement code graph indexer
2. Implement incremental updates
3. Test on real Elixir projects

### Phase 8E: Advanced Tools (P3 - Deferred)
1. Add `code_complexity_analysis` - code metrics
2. Add `code_sparql_query` - raw SPARQL access
3. Add `code_evolution` - git history analysis
4. Add `code_knowledge_gap` - unexplored areas
5. Advanced integration tests

---

## Design Decisions

1. **Tool Naming**: Use `code_*` prefix for all tools (clear distinction from `knowledge_*` tools)

2. **Function Identity**: Use the Elixir convention of Module.function/arity as the canonical identifier

3. **Initial Scope**: All P0-P2 tools (12 tools total)
   - P0: `code_find_function`, `code_get_module`, `code_function_definition`, `code_list_modules`
   - P1: `code_call_graph`, `code_module_graph`, `code_find_usages`, `code_get_typespec`
   - P2: `code_otp_tree`, `code_behaviour_implementations`, `code_macro_expansions`, `code_protocol_implementations`
   - P3 tools deferred

4. **Ontology Source**: TTL files in `~/code/elixir-ontologies/ontology/` are the canonical source

5. **SPARQL Backend**: Use TripleStore with SPARQL for semantic queries over code graph

6. **Named Graph**: Code triples stored in `urn:jido:graph:code:{project_id}` separate from memory graph

7. **Code Indexer**: Separate component to parse .ex files and populate the code graph (prerequisite for queries)
