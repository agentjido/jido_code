# 13. Source Code Graph Operations Guide

This guide covers operational aspects of the source code graph capability, including configuration, monitoring, troubleshooting, and production deployment.

## Overview

The source code graph feature extracts semantic information from Elixir codebases using `ElixirOntologies`, storing results in a local TripleStore for semantic-aware planning, review, and explanation workflows.

**Useful Sources:**
- [`../../.planning/phase-20-source-code-graph-pod-foundation.md`](https://github.com/mikehostetler/jido_code/blob/main/.planning/phase-20-source-code-graph-pod-foundation.md)
- [`../../.planning/phase-21-full-ontology-analysis-and-named-graph-load.md`](https://github.com/mikehostetler/jido_code/blob/main/.planning/phase-21-full-ontology-analysis-and-named-graph-load.md)
- [`../../lib/jido_code/source_code_graph/`](https://github.com/mikehostetler/jido_code/tree/main/lib/jido_code/source_code_graph)

## Configuration

### Enable/Disable

**Development:** Enabled by default in `config/dev.exs`
```elixir
config :jido_code, source_code_graph_enabled: true
```

**Production:** Disabled by default, enable via environment variable:
```bash
export SOURCE_CODE_GRAPH_ENABLED=true
```

### Timeout Configuration

| Config | Default | Description |
|--------|---------|-------------|
| `source_code_graph_analysis_timeout_ms` | 300000 (5 min) | Maximum time for ElixirOntologies analysis |
| `source_code_graph_load_timeout_ms` | 120000 (2 min) | Maximum time for TripleStore load operations |
| `source_code_graph_query_timeout_ms` | 30000 (30 sec) | Maximum time for SPARQL queries |

### Resource Limits

| Config | Default | Description |
|--------|---------|-------------|
| `source_code_graph_max_file_count` | 10000 | Maximum source files to analyze |
| `source_code_graph_max_graph_size_mb` | 500 | Maximum graph size in megabytes |
| `source_code_graph_max_retries` | 3 | Maximum retry attempts for transient failures |
| `source_code_graph_retry_backoff_ms` | 1000 | Base backoff for retry (exponential) |
| `source_code_graph_allow_partial_results` | false | Whether to allow partial results on failure |

### Save-Triggered Refresh

The graph can observe source saves and enqueue a debounced background refresh.
Human editor saves are detected by the repository-scoped file watcher when it is
enabled. Product-managed LLM or tool writes should call
`AgentWorkspace.notify_workspace_source_changed/4` after the write succeeds so
local, remote, and virtual write paths converge on the same normalized event.

| Config | Default | Description |
|--------|---------|-------------|
| `source_code_graph_file_watcher_enabled` | false (`true` in dev) | Enables local filesystem observation for managed repository workspaces |
| `source_code_graph_file_watcher_debounce_ms` | 500 | Quiet window for editor write bursts and atomic-save rename patterns |
| `source_code_graph_file_watcher_max_pending_paths` | 500 | Maximum changed paths carried in one watcher observation |
| `source_code_graph_auto_refresh_enabled` | false (`true` in dev) | Enqueues background refresh work from normalized source-change events |
| `source_code_graph_refresh_debounce_ms` | 250 | Quiet window before the refresh scheduler starts graph work |
| `source_code_graph_refresh_max_coalesce_ms` | 2500 | Upper bound before queued save bursts are flushed into refresh work |
| `source_code_graph_refresh_max_pending_paths` | 500 | Maximum changed paths carried in one scheduler request |
| `source_code_graph_auto_refresh_missing_graph_policy` | `:skip` | `:skip` leaves missing graphs not-ready; `:load` loads missing graphs from save events |
| `source_code_graph_auto_refresh_max_attempts` | 1 | Bounded attempts for one scheduled refresh request |

Background refresh always routes through `AgentWorkspace.refresh_source_code_graph/3`
or, when explicitly configured, `AgentWorkspace.load_source_code_graph/3`. It does
not write directly to TripleStore.

## Operational Requirements

### Dependencies

The source code graph requires:
- `elixir_ontologies` - Git dependency for Elixir semantic extraction
- `triple_store` - Git dependency for local RDF storage
- `sparql` ~ 0.3.11 - SPARQL query library
- RocksDB - Native dependency for TripleStore storage

### Disk Space

Each repository creates a graph at `.jido_code/source_code_graph/triple_store`. Estimated size:
- Small projects (< 100 files): ~1-5 MB
- Medium projects (100-1000 files): ~5-50 MB
- Large projects (1000-10000 files): ~50-500 MB

**Tip:** The graph is repository-local and does not persist across git operations.

### Memory Usage

Analysis requires approximately:
- Base: 100-200 MB
- Per 1000 files: Additional 50-100 MB
- TripleStore operations: 50-100 MB

## Health Monitoring

### Checking Health Status

```elixir
# Via ProductService
{:ok, health} = JidoCode.SourceCodeGraph.ProductService.health(
  managed_repo_id,
  workspace_path
)

# Health status includes:
# - summary: "healthy" | "stale" | "not_ready" | "corrupted"
# - ready?: Boolean
# - stale?: Boolean
# - corrupted?: Boolean
# - last_analysis_at: DateTime | nil
# - graph_size_mb: Integer | nil
```

Source graph status projections also include `graph.refresh` with
`auto_refresh_enabled?`, `last_source_change_at`, `last_refresh_started_at`,
`last_refresh_completed_at`, `refresh_queued?`, `refresh_in_flight?`, and
`last_failure`. These fields explain background activity while the existing
ready, stale, degraded, failed, and disabled graph states remain authoritative.

### Health States

| State | Meaning | Action |
|-------|---------|--------|
| `healthy` | Graph loaded and current | No action needed |
| `stale` | Graph loaded but workspace has changed | Consider refresh |
| `not_ready` | Graph not yet loaded | Run analysis/load |
| `corrupted` | Graph store appears corrupted | Run recovery |

## Troubleshooting

### Analysis Timeout

**Symptom:** `{:error, :timeout}` during analysis

**Causes:**
- Repository too large (file count exceeds limits)
- System resource constraints
- ElixirOntologies performance issue

**Solutions:**
1. Increase `source_code_graph_analysis_timeout_ms`
2. Reduce `source_code_graph_max_file_count`
3. Check system resources (CPU, memory)

### Load Failure

**Symptom:** `{:error, :source_code_graph_store_failed}`

**Causes:**
- Insufficient disk space
- Corrupted staging directory
- TripleStore incompatibility

**Solutions:**
1. Check available disk space
2. Remove `.jido_code/source_code_graph/triple_store.*` staging files
3. Run `recover_source_code_graph` action

### Query Timeout

**Symptom:** `{:error, :timeout}` during semantic query

**Causes:**
- Complex SPARQL query
- Large graph size
- TripleStore contention

**Solutions:**
1. Increase `source_code_graph_query_timeout_ms`
2. Reduce result set size with `limit`
3. Refresh graph if stale

### Background Refresh Skipped Or Failed

**Symptom:** status shows `graph.refresh.last_failure` or a skipped refresh
result after a save.

**Causes:**
- Auto-refresh is disabled in this environment
- The graph has not been loaded and missing-graph policy is `:skip`
- Analysis or TripleStore load failed
- More saves arrived while a previous refresh was already running

**Solutions:**
1. Confirm `source_code_graph_auto_refresh_enabled` and watcher settings
2. Load or recover the graph manually when status is not ready or failed
3. Keep write-capable tools emitting `AgentWorkspace.notify_workspace_source_changed/4` after successful saves
4. Increase debounce or coalescing settings for repositories with noisy generated files

### Graceful Degradation

The runtime automatically falls back to non-semantic mode on:
- Feature disabled
- Graph not ready
- Analysis failure
- Store failure

**Logs:**
```
[warning] Source code graph degraded for repo REPO_ID: REASON
Falling back to non-semantic workspace mode.
```

## Performance Tuning

### For Large Repositories

1. **Increase timeouts:**
   ```elixir
   config :jido_code,
     source_code_graph_analysis_timeout_ms: 600_000, # 10 minutes
     source_code_graph_load_timeout_ms: 300_000      # 5 minutes
   ```

2. **Consider partial results:**
   ```elixir
   config :jido_code,
     source_code_graph_allow_partial_results: true
   ```

3. **Monitor graph size:**
   - Use health check to monitor `graph_size_mb`
   - Set up alerts for approaching `max_graph_size_mb`

### For Resource-Constrained Systems

1. **Reduce limits:**
   ```elixir
   config :jido_code,
     source_code_graph_max_file_count: 1000,
     source_code_graph_max_graph_size_mb: 100
   ```

2. **Disable for specific repos:**
   - Use `source_code_graph_enabled: false` in per-repo config

## Production Deployment

### Pre-Flight Checklist

- [ ] Verify all dependencies are available
- [ ] Test with representative repository
- [ ] Configure appropriate timeouts and limits
- [ ] Set up health monitoring
- [ ] Configure alerting for degradation events
- [ ] Document rollback procedure

### Rollback Procedure

To disable in production:
```bash
export SOURCE_CODE_GRAPH_ENABLED=false
# Or unset the variable to use default (disabled)
unset SOURCE_CODE_GRAPH_ENABLED
```

The runtime will automatically fall back to non-semantic mode.

### Monitoring Metrics

Key metrics to monitor:
- Analysis duration (target: < 5 minutes for typical repos)
- Graph freshness (stale graphs should be refreshed)
- Error rate (analysis failures, store failures)
- Degradation events (fallback to non-semantic mode)
- Disk usage per repository

## Read Next

- [`07-source-code-graph-and-semantic-services.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/07-source-code-graph-and-semantic-services.md) - Architecture overview
- [`08-memory-graph-and-workflow-provenance.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/08-memory-graph-and-workflow-provenance.md) - Related memory graph features
