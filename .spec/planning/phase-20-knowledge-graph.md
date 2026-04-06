# Phase 20: Knowledge Graph Service

Implement the Knowledge Graph service for code understanding, providing SPARQL query
capabilities over code structure, relationships, and patterns.

## Goals

1. Create actions for querying and updating the code knowledge graph
2. Implement Elixir code parsing and indexing
3. Build SPARQL query interface over the indexed code
4. Integrate KG tools into AI agents for enhanced code understanding
5. Provide knowledge exploration capabilities for code navigation

## Sections

  [x] 20.1 Section - KG Backend and Adapter
    Define the adapter interface and implement an in-memory KG backend.

    [x] 20.1.1 Task - Create KG adapter interface
      Define the behavior that all KG backends must implement.

    [x] 20.1.2 Task - Implement in-memory KG backend
      Create an ETS-based in-memory store for code knowledge.

    [x] 20.1.3 Task - Create mock adapter for testing
      Implement a mock KG adapter for unit testing.

  [x] 20.2 Section - KG Actions
    Implement Jido.Action modules for KG operations.

    [x] 20.2.1 Task - Implement KGQuery action
      Create `JidoCode.Actions.KGQuery` for SPARQL queries.

    [x] 20.2.2 Task - Implement KGUpdate action
      Create `JidoCode.Actions.KGUpdate` for updating the KG.

    [x] 20.2.3 Task - Implement KGExplore action
      Create `JidoCode.Actions.KGExplore` for exploring relationships.

  [x] 20.3 Section - Code Indexing
    Implement parsing and indexing of Elixir code into the KG.

    [x] 20.3.1 Task - Implement AST-based code parser
      Create parser for Elixir AST extraction (functions, modules, calls).

    [x] 20.3.2 Task - Implement code indexer
      Create indexer that builds the KG from parsed AST data.

    [x] 20.3.3 Task - Implement incremental index updates
      Update KG when files change (detected by RepoMonitor).

  [x] 20.4 Section - KG Tool Integration
    Add KG tools to AI agents that need code understanding.

    [x] 20.4.1 Task - Add KG tools to Planner
      Update Planner agent to use KGQuery and KGExplore.

    [x] 20.4.2 Task - Add KG tools to Coder
      Update Coder agent to use KGQuery for pattern discovery.

    [x] 20.4.3 Task - Add KG tools to Reviewer
      Update Reviewer agent to use KGQuery for impact analysis.

  [x] 20.5 Section - KG Integration Tests
    Verify KG functionality with end-to-end scenarios.

    [x] 20.5.1 Task - KG query tests
      Test SPARQL queries against known code structures.

    [x] 20.5.2 Task - KG update tests
      Verify incremental updates when code changes.

    [x] 20.5.3 Task - Agent integration tests
      Verify agents can use KG tools effectively.
