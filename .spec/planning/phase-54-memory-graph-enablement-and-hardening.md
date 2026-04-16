# Phase 54 - Memory Graph Enablement and Hardening

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs -->
<!-- covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_graph.spec.md`
- `../specs/memory_graph_product_adoption.spec.md`
- `../specs/memory_capture_plane.spec.md`
- `../decisions/jido_code.memory_capture_plane_and_insertion_seams.md`
- `../decisions/jido_code.memory_graph_product_adoption.md`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/agents/`
- `lib/jido_code/actions/`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/conversations/runtime.ex`

## Relevant Assumptions / Defaults
- Phases 28 through 38 have established the MemoryGraphPod contract, memory capture plane, durable memory storage, and product service boundaries.
- Current memory graph operations lack timeout protection, retry mechanisms, resource limits, and health monitoring.
- Memory graph is disabled by default and requires production hardening before safe enablement.
- Memory graph involves multiple named graphs (memory, workflow_provenance) and cross-graph navigation.

[ ] 54 Phase 54 - Memory Graph Enablement and Hardening
  Enable the memory graph capability for development use and add production-hardening including timeouts, retry mechanisms, resource limits, health monitoring, and graceful degradation for memory capture, storage, and retrieval operations.

  [ ] 54.1 Section - Timeout Configurations
    Add configurable timeout protections for all memory graph store operations, queries, and validation to prevent indefinite hangs during TripleStore operations, RDF parsing, and cross-graph navigation.

    [ ] 54.1.1 Task - Create memory graph configuration module
      Define a centralized configuration module for timeout settings, retry policies, and resource limits that mirrors the source code graph configuration pattern.

      [ ] 54.1.1.1 Subtask - Define store_timeout_ms config for TripleStore operations (default: 30 seconds)
      [ ] 54.1.1.2 Subtask - Define query_timeout_ms config for SPARQL queries (default: 60 seconds)
      [ ] 54.1.1.3 Subtask - Define validation_timeout_ms config for ontology validation (default: 120 seconds)
      [ ] 54.1.1.4 Subtask - Define recovery_timeout_ms config for recovery operations (default: 300 seconds)

    [ ] 54.1.2 Task - Add timeout to memory store operations
      Wrap TripleStore open, close, and load operations with Task.async and timeout protection.

      [ ] 54.1.2.1 Subtask - Wrap TripleStore.open/3 with timeout in store.ex
      [ ] 54.1.2.2 Subtask - Wrap TripleStore.load_graph/3 with timeout in durable_memory_writer.ex
      [ ] 54.1.2.3 Subtask - Return {:error, :timeout} with timeout_ms in diagnostics

    [ ] 54.1.3 Task - Add timeout to memory query operations
      Wrap SPARQL query execution with timeout protection.

      [ ] 54.1.3.1 Subtask - Add timeout to TripleStore.query/2 in query.ex
      [ ] 54.1.3.2 Subtask - Add timeout to cross-graph navigation operations
      [ ] 54.1.3.3 Subtask - Handle timeout with degraded query results

  [ ] 54.2 Section - Retry Mechanisms
    Add exponential backoff retry for transient failures in memory store operations, RDF parsing, and cross-graph queries to handle temporary I/O errors, file locks, and network issues.

    [ ] 54.2.1 Task - Create memory graph retry policy module
      Define retry policy that handles transient failures specific to memory graph operations.

      [ ] 54.2.1.1 Subtask - Define retryable errors for memory operations (:econnrefused, :enoent, :timeout, :enospc)
      [ ] 54.2.1.2 Subtask - Implement exponential backoff with configurable base delay (default: 1000ms)
      [ ] 54.2.1.3 Subtask - Add max_retries config (default: 3) with separate limit for write operations (default: 2)

    [ ] 54.2.2 Task - Add retry to memory store operations
      Wrap TripleStore operations and ontology loading with retry policy.

      [ ] 54.2.2.1 Subtask - Add retry to load_ontology_graph/2 in store.ex
      [ ] 54.2.2.2 Subtask - Add retry to durable memory write operations
      [ ] 54.2.2.3 Subtask - Track attempt count in error diagnostics

    [ ] 54.2.3 Task - Add retry to cross-graph navigation
      Wrap source code graph queries in cross-graph navigation with retry.

      [ ] 54.2.3.1 Subtask - Add retry to build/3 in cross_graph_navigation.ex
      [ ] 54.2.3.2 Subtask - Handle source code graph unavailability gracefully
      [ ] 54.2.3.3 Subtask - Log retry attempts for cross-graph operations

  [ ] 54.3 Section - Resource Limits and Validation
    Add pre-flight checks for memory graph size, disk space, and operation limits to prevent resource exhaustion during memory capture and storage.

    [ ] 54.3.1 Task - Create memory graph resource limits module
      Define validation module for memory graph resource constraints.

      [ ] 54.3.1.1 Subtask - Implement validate_graph_size/2 for pre-write size checks
      [ ] 54.3.1.2 Subtask - Implement validate_disk_space/3 for store operations
      [ ] 54.3.1.3 Subtask - Implement validate_concurrent_operations/1 for write throttling

    [ ] 54.3.2 Task - Add memory graph size limits
      Define and enforce limits on memory graph growth.

      [ ] 54.3.2.1 Subtask - Add max_graph_size_mb config (default: 10,000 MB)
      [ ] 54.3.2.2 Subtask - Check graph size before durable memory writes
      [ ] 54.3.2.3 Subtask - Return graceful degradation when size exceeded

    [ ] 54.3.3 Task - Add query result limits
      Limit the size of query results to prevent excessive memory usage.

      [ ] 54.3.3.1 Subtask - Add max_query_results config (default: 10,000)
      [ ] 54.3.3.2 Subtask - Enforce limit in SPARQL query operations
      [ ] 54.3.3.3 Subtask - Return partial results with warning when limit exceeded

  [ ] 54.4 Section - Health Monitoring
    Add health checks, integrity checks, and metrics for the memory graph to provide operational visibility into store health, graph freshness, and performance.

    [ ] 54.4.1 Task - Create memory graph health module
      Define health monitoring for memory graph stores.

      [ ] 54.4.1.1 Subtask - Implement check/1 for both memory and workflow_provenance graphs
      [ ] 54.4.1.2 Subtask - Add TripleStore integrity check for each graph
      [ ] 54.4.1.3 Subtask - Implement summary/1 for simple health status

    [ ] 54.4.2 Task - Add memory graph metrics
      Track performance and usage metrics for operational monitoring.

      [ ] 54.4.2.1 Subtask - Track last write time and write count
      [ ] 54.4.2.2 Subtask - Track query latency and error rate
      [ ] 54.4.2.3 Subtask - Track graph size in bytes and triple count

    [ ] 54.4.3 Task - Integrate health into product boundary
      Expose health status through ProductService.

      [ ] 54.4.3.1 Subtask - Add health/3 to ProductService
      [ ] 54.4.3.2 Subtask - Add ViewModel.health/2 for health shaping
      [ ] 54.4.3.3 Subtask - Include health in status responses

  [ ] 54.5 Section - Error Handling and Graceful Degradation
    Add fallback behavior when memory graph operations fail, ensuring conversations and workflows continue functioning without memory context.

    [ ] 54.5.1 Task - Add fallback from memory workflow mode
      Update Runtime to fall back from :memory_workflow to :workspace or :workspace_with_semantic.

      [ ] 54.5.1.1 Subtask - Implement invoke_memory_workflow_with_fallback/3
      [ ] 54.5.1.2 Subtask - Handle disabled, not_ready, and write_failed errors
      [ ] 54.5.1.3 Subtask - Log degradation events with warning level

    [ ] 54.5.2 Task - Add fallback in WorkflowService
      Handle memory graph unavailability in workflow operations.

      [ ] 54.5.2.1 Subtask - Wrap memory operations with error handling
      [ ] 54.5.2.2 Subtask - Include degradation_reason in workflow results
      [ ] 54.5.2.3 Subtask - Preserve workflow execution without memory context

    [ ] 54.5.3 Task - Add cross-graph navigation fallback
      Handle source code graph unavailability in cross-graph queries.

      [ ] 54.5.3.1 Subtask - Return memory-only results when source code graph unavailable
      [ ] 54.5.3.2 Subtask - Log cross-graph degradation events
      [ ] 54.5.3.3 Subtask - Include cross_graph_status in results

  [ ] 54.6 Section - Configuration Defaults
    Enable memory graph in development with environment variable support for production.

    [ ] 54.6.1 Task - Enable in development config
      Add memory_graph_enabled: true to dev.exs with all timeout and limit configs.

      [ ] 54.6.1.1 Subtask - Add all timeout configs to dev.exs
      [ ] 54.6.1.2 Subtask - Add all resource limit configs to dev.exs
      [ ] 54.6.1.3 Subtask - Document each config value with inline comments

    [ ] 54.6.2 Task - Add environment variable support
      Allow production configuration via environment variables.

      [ ] 54.6.2.1 Subtask - Add MEMORY_GRAPH_ENABLED env var support
      [ ] 54.6.2.2 Subtask - Add optional timeout env vars (MEMORY_GRAPH_*_TIMEOUT_MS)
      [ ] 54.6.2.3 Subtask - Keep default: disabled in production

  [ ] 54.7 Section - Documentation and Contributor Guidance
    Add operational documentation and update existing guidance for the enabled memory graph feature.

    [ ] 54.7.1 Task - Create memory graph operations guide
      Create comprehensive operations documentation.

      [ ] 54.7.1.1 Subtask - Document all configuration options with examples
      [ ] 54.7.1.2 Subtask - Add troubleshooting guide for common issues
      [ ] 54.7.1.3 Subtask - Add performance tuning guidelines
      [ ] 54.7.1.4 Subtask - Add production deployment checklist

    [ ] 54.7.2 Task - Update existing documentation
      Integrate memory graph operations into existing docs.

      [ ] 54.7.2.1 Subtask - Update developer README with operations guide link
      [ ] 54.7.2.2 Subtask - Update memory graph and workflow provenance doc
      [ ] 54.7.2.3 Subtask - Cross-reference with source code graph operations

  [ ] 54.8 Section - Integration Tests and Verification
    Verify the hardened memory graph capability works end-to-end with graceful degradation.

    [ ] 54.8.1 Task - Timeout and retry scenarios
      Prove timeout and retry mechanisms prevent indefinite hangs and handle transient failures.

      [ ] 54.8.1.1 Subtask - Add coverage proving timeout returns error without hanging
      [ ] 54.8.1.2 Subtask - Add coverage proving retry succeeds on transient failures
      [ ] 54.8.1.3 Subtask - Add coverage proving max retries is enforced

    [ ] 54.8.2 Task - Resource limit scenarios
      Prove resource limits prevent exhaustion while allowing legitimate operations.

      [ ] 54.8.2.1 Subtask - Add coverage proving graph size limit is enforced
      [ ] 54.8.2.2 Subtask - Add coverage proving disk space validation works
      [ ] 54.8.2.3 Subtask - Add coverage proving query result limit is enforced

    [ ] 54.8.3 Task - Graceful degradation scenarios
      Prove workflows continue functioning when memory graph is unavailable.

      [ ] 54.8.3.1 Subtask - Add coverage proving memory workflow falls back to workspace
      [ ] 54.8.3.2 Subtask - Add coverage proving cross-graph navigation falls back gracefully
      [ ] 54.8.3.3 Subtask - Add coverage proving degradation is logged appropriately
