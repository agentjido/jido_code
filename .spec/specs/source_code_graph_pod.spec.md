# Source Code Graph Pod

This subject defines the repository-scoped semantic analysis pod that uses
Elixir-aware ontology extraction plus local RDF storage for source-code graph
ingestion and query.

<!-- covers: package.jido_code.spec_led_workspace -->

```spec-meta
id: architecture.source_code_graph_pod
kind: feature
status: proposed
summary: Jido.Code provides a repository-scoped SourceCodeGraphPod that analyzes a managed repository with ElixirOntologies in full mode, stages ontology schema plus extracted project individuals as one semantic snapshot, loads that snapshot into the canonical `source_code` named graph of a local TripleStore quad store, preserves bounded repository-scoped readiness and stale-revision status through AgentWorkspace, exposes both explicit SPARQL query actions and compiled semantic helper actions for pod-local specialists, and grants selected coding specialists explicit semantic lookup tools only through bounded composition.
decisions:
  - jido_code.jido_agent_os_integration
  - jido_code.source_code_graph_pod_and_named_graph_ingestion
surface:
  - .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  - .spec/specs/agent_os_integration.spec.md
  - lib/jido_code/agent_workspace.ex
  - lib/jido_code/pods/
  - lib/jido_code/agents/
  - lib/jido_code/actions/
  - test/jido_code/agent_os/
```

## Requirements

```spec-requirements
- id: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  statement: When semantic source-code analysis is enabled for a managed repository, Jido.Code shall provide a repository-scoped SourceCodeGraphPod within that repository's AgentOS kernel rather than a cross-repository singleton service.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  statement: Source-code graph analysis shall use ElixirOntologies full extraction mode, including expression-level detail, instead of the light structural-only profile.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  statement: The persisted backing store for the source-code graph shall be a local TripleStore database configured for named-graph storage so repository-scoped graph data remains durable and isolated.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  statement: The canonical named graph for repository source-code semantics shall be exactly `source_code`.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  statement: The source-code graph load shall include both ontology/schema material and repository-derived individuals in the `source_code` named graph so pod queries operate on one coherent semantic view.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  statement: Source-code graph behavior shall be exposed through explicit Jido.Action tools for analyze, load, refresh, and query operations rather than hidden ambient helper calls.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  statement: After the `source_code` graph is loaded, pod-local graph queries shall use the `sparql` library as the canonical SPARQL query surface for agents.
  priority: must
  stability: proposed

- id: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  statement: Refreshing the source-code graph shall replace or rebuild the `source_code` named graph coherently so mixed ontology/project revisions are not exposed to subsequent pod queries.
  priority: should
  stability: proposed
```

## Scenarios

```spec-scenarios
- id: architecture.source_code_graph_pod.scenario_initial_repository_analysis_populates_source_code_graph
  covers:
    - architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
    - architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  given:
    - A managed repository has a workspace path and semantic source-code analysis is enabled.
  when:
    - The SourceCodeGraphPod analyzes and loads the repository for the first time.
  then:
    - ElixirOntologies runs in full mode.
    - A local TripleStore named-graph store is used.
    - Ontology/schema material and project individuals are loaded into the `source_code` named graph.

- id: architecture.source_code_graph_pod.scenario_agents_query_loaded_source_code_graph
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  given:
    - A managed repository already has a loaded `source_code` named graph.
  when:
    - A pod-local specialist agent asks a SPARQL question about modules, functions, runtime patterns, or evolution facts.
  then:
    - The query goes through an explicit query action.
    - The action uses the `sparql` library as the canonical query surface.
    - The agent receives structured query results rather than raw store internals.

- id: architecture.source_code_graph_pod.scenario_selected_coding_agents_receive_explicit_semantic_tools
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  given:
    - A managed repository has semantic source-code graph capability enabled.
  when:
    - Planning, review, or explanation specialists need semantic graph context.
  then:
    - Only explicitly selected coding specialists receive semantic graph tools.
    - Those tools remain the same bounded query and helper actions used by the pod-local semantic specialists.
    - Semantic lookup remains an explicit tool call rather than an ambient hidden dependency.

- id: architecture.source_code_graph_pod.scenario_helper_actions_compile_to_explicit_queries
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  given:
    - A managed repository already has a loaded `source_code` named graph.
  when:
    - Pod-local or product-owned callers ask for modules, functions, runtime patterns, or bounded impact lookups through helper actions.
  then:
    - The helper action compiles to an explicit SPARQL query.
    - The helper still routes through the canonical query surface.
    - Empty or failed results remain typed and bounded.

- id: architecture.source_code_graph_pod.scenario_graph_refresh_replaces_previous_snapshot
  covers:
    - architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  given:
    - A repository's `source_code` graph was previously loaded.
  when:
    - The pod refreshes the graph after source changes or an explicit re-analysis request.
  then:
    - The `source_code` named graph is rebuilt or replaced coherently.
    - Later queries observe one semantic snapshot rather than a mixed old/new graph.
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/decisions/jido_code.source_code_graph_pod_and_named_graph_ingestion.md
  covers:
    - architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
    - architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
    - architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently

- kind: source_file
  target: lib/jido_code/source_code_graph.ex
  covers:
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target

- kind: source_file
  target: lib/jido_code/source_code_graph/analysis.ex
  covers:
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/source_code_graph/store.ex
  covers:
    - architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
    - architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
    - architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently

- kind: source_file
  target: lib/jido_code/pods/source_code_graph_pod.ex
  covers:
    - architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod

- kind: source_file
  target: lib/jido_code/agents/source_code_graph_analyzer.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/agents/source_code_graph_loader.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/agents/source_code_graph_querier.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface

- kind: source_file
  target: lib/jido_code/agents/planner.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/agents/reviewer.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/agents/explainer.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/actions/analyze_source_code_graph.ex
  covers:
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/actions/load_source_code_graph.ex
  covers:
    - architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/actions/query_source_code_graph.ex
  covers:
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/source_code_graph/query.ex
  covers:
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/source_code_graph/helper_queries.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: lib/jido_code/actions/find_source_code_graph_modules.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface

- kind: source_file
  target: lib/jido_code/actions/find_source_code_graph_functions.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface

- kind: source_file
  target: lib/jido_code/actions/find_source_code_graph_runtime_patterns.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface

- kind: source_file
  target: lib/jido_code/actions/trace_source_code_graph_impact.ex
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface

- kind: source_file
  target: lib/jido_code/actions/refresh_source_code_graph.ex
  covers:
    - architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_integration_test.exs
  covers:
    - architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: test/jido_code/agent_os/phase_twenty_one_integration_test.exs
  covers:
    - architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
    - architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
    - architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
    - architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
    - architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently

- kind: source_file
  target: test/jido_code/source_code_graph_actions_test.exs
  covers:
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: test/jido_code/agent_os/pods_test.exs
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query

- kind: source_file
  target: test/jido_code/agent_os/source_code_graph_agent_adoption_test.exs
  covers:
    - architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
    - architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
```
