# Knowledge Graph Service Specification

## Overview

Knowledge Graph service for code understanding, providing SPARQL query capabilities
over code structure, relationships, and patterns.

## Requirements

### KG-1 Repository Code Indexing

The system must maintain a knowledge graph of:
- Files and their relationships (imports, dependencies)
- Functions and their callers/callees
- Modules and their composition
- Data structures and their usage
- Test coverage and relationships

### KG-2 SPARQL Query Interface

The system must provide SPARQL query capabilities:
- Query files by type, module, or pattern
- Find callers of a function
- Find dependencies between modules
- Trace data flow through the system
- Explore relationship chains

### KG-3 Knowledge Update

The system must update the KG when:
- Files are added, modified, or deleted
- Code is refactored
- Tests are added or modified
- Dependencies change

### KG-4 Code Model Integration

The knowledge model must integrate with:
- AST parsing for Elixir code
- Dependency analysis
- Cross-reference indexing
- Test-to-code mapping

## API Requirements

### Actions

#### KGQuery Action

```elixir
defmodule JidoCode.Actions.KGQuery do
  @moduledoc """
  SPARQL query action for querying the code knowledge graph.
  """

  use Jido.Action,
    name: "kg_query",
    description: "Query the code knowledge graph using SPARQL",
    schema: [
      query: [type: :string, required: true],
      limit: [type: :integer, default: 100]
    ]
end
```

#### KGUpdate Action

```elixir
defmodule JidoCode.Actions.KGUpdate do
  @moduledoc """
  Action for updating the code knowledge graph.
  """

  use Jido.Action,
    name: "kg_update",
    description: "Update the code knowledge graph with new code changes",
    schema: [
      file_paths: [type: {:list, :string}, required: true],
      operation: [type: :atom, default: :index]
    ]
end
```

#### KGExplore Action

```elixir
defmodule JidoCode.Actions.KGExplore do
  @moduledoc """
  Action for exploring relationships in the code knowledge graph.
  """

  use Jido.Action,
    name: "kg_explore",
    description: "Explore relationships in the code knowledge graph",
    schema: [
      start_node: [type: :string, required: true],
      direction: [type: :atom, default: :both],
      depth: [type: :integer, default: 3]
    ]
end
```

### Adapter Interface

```elixir
defmodule JidoCode.KG.Adapter do
  @moduledoc """
  Low-level adapter to the Knowledge Graph backend.
  """

  @callback query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  @callback update([String.t()], keyword()) :: :ok | {:error, term()}
  @callback explore(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
end
```

## Non-Functional Requirements

- **Performance**: SPARQL queries must return within 5 seconds for 1000 results
- **Scalability**: Must support repositories with 10k+ files
- **Incremental updates**: KG updates must complete within 10 seconds
- **Testability: Mock adapter for testing without full KG backend

## Scenarios

### KG-1 Planner queries for code context

**Given:** A planner agent needs to understand the codebase structure
**When:** Planning a new feature
**Then:** The planner can query the KG for:
- Which modules are affected by the proposed change
- What functions would be impacted
- What tests need to be updated
- Dependency chains to consider

### KG-2 Coder queries for usage patterns

**Given:** A coder agent is implementing a function
**When:** The agent needs to understand similar patterns
**Then:** The coder can query the KG for:
- How similar functions are implemented
- What patterns are used in this codebase
- Examples of function calls in context

### KG-3 Reviewer queries for impact analysis

**Given:** A reviewer agent is reviewing changes
**When:** Analyzing a pull request
**Then:** The reviewer can query the KG for:
- What other code would be affected
- Test coverage for changed code
- Whether the change breaks existing contracts

## Verification

- Unit tests for each KG action with mock adapter
- Integration tests with in-memory KG
- Performance benchmarks for query operations
- Accuracy tests against known code structures
