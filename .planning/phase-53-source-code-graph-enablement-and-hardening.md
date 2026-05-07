# Phase 53 - Source Code Graph Enablement and Hardening

<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `../specs/source_code_graph_product_adoption.spec.md`
- `../specs/source_code_graph_pod.spec.md`
- `lib/jido_code/source_code_graph/config.ex`
- `lib/jido_code/source_code_graph/health.ex`
- `lib/jido_code/source_code_graph/resource_limits.ex`
- `lib/jido_code/conversations/runtime.ex`
- `config/dev.exs`
- `config/runtime.exs`

## Relevant Assumptions / Defaults
- Phases 20-24 have established the source code graph capability but it remains disabled by default
- ElixirOntologies and TripleStore are git dependencies with commit pins
- No timeouts, retry mechanisms, or resource limits exist
- No health monitoring or graceful degradation

[x] 53 Phase 53 - Source Code Graph Enablement and Hardening
  Enable the source code graph feature for development use and add production-hardening including timeouts, retries, resource limits, health monitoring, and graceful degradation.

  [x] 53.1 Section - Add Timeout Configurations
    Add configurable timeouts for analysis, load, and query operations to prevent indefinite hangs.

    [x] 53.1.1 Task - Create configuration module
      Create `SourceCodeGraph.Config` module for centralized timeout and limit configuration.

      [x] 53.1.1.1 Subtask - Define `analysis_timeout_ms` config (default: 5 minutes)
      [x] 53.1.1.2 Subtask - Define `load_timeout_ms` config (default: 2 minutes)
      [x] 53.1.1.3 Subtask - Define `query_timeout_ms` config (default: 30 seconds)

    [x] 53.1.2 Task - Add timeout to analysis operations
      Wrap ElixirOntologies.analyze_project calls with Task.async and timeout.

      [x] 53.1.2.1 Subtask - Use Task.yield/2 with timeout
      [x] 53.1.2.2 Subtask - Return `{:error, :timeout}` on timeout
      [x] 53.1.2.3 Subtask - Include timeout_ms in error diagnostics

    [x] 53.1.3 Task - Add timeout to load operations
      Wrap TripleStore load operations with timeout.

      [x] 53.1.3.1 Subtask - Add timeout to build_staged_store/4
      [x] 53.1.3.2 Subtask - Use Task.yield/2 with timeout
      [x] 53.1.3.3 Subtask - Handle timeout with staged store cleanup

  [x] 53.2 Section - Add Retry Mechanisms
    Add exponential backoff retry for transient failures.

    [x] 53.2.1 Task - Create retry policy module
      Create `SourceCodeGraph.RetryPolicy` module with configurable retry behavior.

      [x] 53.2.1.1 Subtask - Define retryable errors (:econnrefused, :enoent, :timeout, etc.)
      [x] 53.2.1.2 Subtask - Implement exponential backoff calculation
      [x] 53.2.1.3 Subtask - Add max_retries config (default: 3)

    [x] 53.2.2 Task - Add retry to analysis operations
      Wrap ElixirOntologies.analyze_project with retry policy.

      [x] 53.2.2.1 Subtask - Use RetryPolicy.retry/2 for analysis
      [x] 53.2.2.2 Subtask - Track attempt count in error diagnostics
      [x] 53.2.2.3 Subtask - Log retry attempts

    [x] 53.2.3 Task - Add retry to store operations
      Wrap TripleStore operations with retry policy.

      [x] 53.2.3.1 Subtask - Add retry to load_schema_artifacts/3
      [x] 53.2.3.2 Subtask - Add retry to load_graph operations
      [x] 53.2.3.3 Subtask - Use separate retry limit (2) for store operations

  [x] 53.3 Section - Add Resource Limits and Validation
    Add pre-flight checks for file counts, disk space, and graph size.

    [x] 53.3.1 Task - Create resource limits module
      Create `SourceCodeGraph.ResourceLimits` module for validation.

      [x] 53.3.1.1 Subtask - Implement validate_file_count/2
      [x] 53.3.1.2 Subtask - Implement validate_disk_space/3
      [x] 53.3.1.3 Subtask - Implement validate_workspace/1

    [x] 53.3.2 Task - Add max_file_count config
      Limit analysis to reasonable file counts (default: 10,000).

      [x] 53.3.2.1 Subtask - Add source file counting
      [x] 53.3.2.2 Subtask - Exclude deps/, _build/, node_modules/
      [x] 53.3.2.3 Subtask - Return error on limit exceeded

    [x] 53.3.3 Task - Add disk space validation
      Check available disk space before loading graph.

      [x] 53.3.3.1 Subtask - Estimate graph size from file count
      [x] 53.3.3.2 Subtask - Use df command to check available space
      [x] 53.3.3.3 Subtask - Require 2x estimated size for safety

  [x] 53.4 Section - Add Health Monitoring
    Add health checks and metrics for operational visibility.

    [x] 53.4.1 Task - Create health monitoring module
      Create `SourceCodeGraph.Health` module for health checks.

      [x] 53.4.1.1 Subtask - Implement check/1 function with health status
      [x] 53.4.1.2 Subtask - Add TripleStore integrity check
      [x] 53.4.1.3 Subtask - Implement summary/1 for simple status

    [x] 53.4.2 Task - Integrate health into ProductService
      Expose health through product-owned boundary.

      [x] 53.4.2.1 Subtask - Add health/3 function to ProductService
      [x] 53.4.2.2 Subtask - Add ViewModel.health/2 for shaping
      [x] 53.4.2.3 Subtask - Merge health status with AgentWorkspace status

  [x] 53.5 Section - Improve Error Handling and Graceful Degradation
    Add fallback to non-semantic mode on semantic failure.

    [x] 53.5.1 Task - Add fallback to workspace mode
      Update Runtime to fall back from :workspace_with_semantic to :workspace.

      [x] 53.5.1.1 Subtask - Implement invoke_workspace_with_semantic_fallback/3
      [x] 53.5.1.2 Subtask - Handle disabled, not_ready, and analysis_failed errors
      [x] 53.5.1.3 Subtask - Log degradation events

    [x] 53.5.2 Task - Add fallback for semantic workflows
      Update Runtime to fall back from :semantic_workflow to workspace.

      [x] 53.5.2.1 Subtask - Implement invoke_semantic_workflow_with_fallback/3
      [x] 53.5.2.2 Subtask - Handle plan, review, explain workflows
      [x] 53.5.2.3 Subtask - Preserve functionality on semantic failure

  [x] 53.6 Section - Add Configuration Defaults
    Enable feature in dev with environment variable support.

    [x] 53.6.1 Task - Enable in development config
      Add source_code_graph_enabled: true to dev.exs.

      [x] 53.6.1.1 Subtask - Add all timeout and limit configs to dev.exs
      [x] 53.6.1.2 Subtask - Use conservative defaults for safety
      [x] 53.6.1.3 Subtask - Document each config value

    [x] 53.6.2 Task - Add environment variable support
      Allow production configuration via environment variables.

      [x] 53.6.2.1 Subtask - Add SOURCE_CODE_GRAPH_ENABLED env var
      [x] 53.6.2.2 Subtask - Add timeout env vars (optional)
      [x] 53.6.2.3 Subtask - Keep default: disabled in production

  [x] 53.7 Section - Update Documentation
    Add operational documentation for the enabled feature.

    [x] 53.7.1 Task - Create operations guide
      Create comprehensive operations documentation.

      [x] 53.7.1.1 Subtask - Document all configuration options
      [x] 53.7.1.2 Subtask - Add troubleshooting guide
      [x] 53.7.1.3 Subtask - Add performance tuning guidelines
      [x] 53.7.1.4 Subtask - Add production deployment checklist

    [x] 53.7.2 Task - Update developer documentation
      Integrate new docs into existing documentation structure.

      [x] 53.7.2.1 Subtask - Add to developer README index
      [x] 53.7.2.2 Subtask - Cross-reference with semantic services doc
      [x] 53.7.2.3 Subtask - Update current truth references
