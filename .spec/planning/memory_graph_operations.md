# Memory Graph Operations Guide

This guide covers operational aspects of the memory graph capability, including configuration, troubleshooting, performance tuning, and production deployment.

## Configuration Options

All memory graph configuration options can be set via application config or environment variables.

### Enablement

- **Application Config**: `config :jido_code, memory_graph_enabled: true`
- **Environment Variable**: `MEMORY_GRAPH_ENABLED=true`
- **Default**: `false` (disabled)
- **Development**: `true` (enabled in dev.exs)

### Timeout Configurations

| Option | Default | Description |
|--------|---------|-------------|
| `memory_graph_store_timeout_ms` | 30_000 | Timeout for TripleStore operations (open, close, load) |
| `memory_graph_query_timeout_ms` | 60_000 | Timeout for SPARQL query execution |
| `memory_graph_validation_timeout_ms` | 120_000 | Timeout for ontology validation operations |
| `memory_graph_recovery_timeout_ms` | 300_000 | Timeout for recovery operations |

### Retry Configurations

| Option | Default | Description |
|--------|---------|-------------|
| `memory_graph_max_retries` | 3 | Maximum retry attempts for transient failures |
| `memory_graph_max_write_retries` | 2 | Maximum retry attempts for write operations |
| `memory_graph_retry_backoff_ms` | 1000 | Base backoff time in milliseconds (exponential) |

### Resource Limits

| Option | Default | Description |
|--------|---------|-------------|
| `memory_graph_max_graph_size_mb` | 10_000 | Maximum graph size in megabytes (10 GB) |
| `memory_graph_max_query_results` | 10_000 | Maximum number of query results |
| `memory_graph_max_concurrent_operations` | 50 | Maximum concurrent write operations |

## Troubleshooting

### Memory Graph Not Ready

**Symptoms**: Conversations fall back to workspace mode, memory queries fail

**Diagnosis**:
```elixir
JidoCode.MemoryGraph.ProductService.status(managed_repo_id, workspace_path)
```

**Solutions**:
1. **Graph not initialized**: Run refresh operation
   ```elixir
   JidoCode.AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)
   ```

2. **Graph stale**: Run validation
   ```elixir
   JidoCode.AgentWorkspace.validate_memory_graph(managed_repo_id, workspace_path)
   ```

3. **Recovery required**: Run recovery
   ```elixir
   JidoCode.MemoryGraph.ProductService.recover(managed_repo_id, workspace_path)
   ```

### Timeout Errors

**Symptoms**: Operations fail with `:timeout` reason

**Diagnosis**:
- Check timeout configurations
- Monitor operation duration
- Review graph size

**Solutions**:
1. Increase timeout for specific operation type
2. Reduce graph size through pruning
3. Optimize SPARQL queries

### Resource Exhaustion

**Symptoms**: Operations fail with limit exceeded errors

**Diagnosis**:
```elixir
JidoCode.MemoryGraph.ProductService.health(managed_repo_id, workspace_path)
```

**Solutions**:
1. **Graph size limit**: Increase `memory_graph_max_graph_size_mb`
2. **Query result limit**: Increase `memory_graph_max_query_results`
3. **Concurrent operations**: Increase `memory_graph_max_concurrent_operations`

### Retry Loop

**Symptoms**: Operations repeatedly retry and fail

**Diagnosis**:
- Check error logs for retry messages
- Identify transient vs. permanent errors

**Solutions**:
1. For transient errors (econnrefused, enospc): Address underlying issue
2. For permanent errors: Investigate root cause rather than increasing retries
3. Reduce `retry_backoff_ms` for faster failure detection

## Performance Tuning

### Graph Size Management

1. **Monitor growth**: Use health endpoint to track graph size
   ```elixir
   {:ok, health} = JidoCode.MemoryGraph.Health.check(graph_context)
   health.metrics.total_triple_count
   ```

2. **Set appropriate limits**: Balance between storage and performance needs

3. **Consider pruning**: Old or invalid memories can be invalidated

### Query Optimization

1. **Use specific predicates**: Avoid broad queries
2. **Limit results**: Use LIMIT in SPARQL when possible
3. **Index governance**: Ensure governed references are properly indexed

### Timeout Tuning

For larger repositories or complex queries:
- Increase `query_timeout_ms` for complex SPARQL
- Increase `validation_timeout_ms` for large ontologies
- Keep `store_timeout_ms` low for fast failure detection

## Production Deployment Checklist

### Pre-Deployment

- [ ] Memory graph tested with representative data
- [ ] Timeout configurations appropriate for production workload
- [ ] Resource limits set based on available resources
- [ ] Monitoring configured for health metrics
- [ ] Backup strategy for graph storage

### Configuration

- [ ] `MEMORY_GRAPH_ENABLED=true` set for production
- [ ] Timeout values tuned for production infrastructure
- [ ] Resource limits aligned with container/VM resources
- [ ] Environment variables documented in deployment config

### Monitoring

- [ ] Health endpoint monitored
- [ ] Metrics tracked:
  - Graph size and triple count
  - Query latency
  - Error rate
  - Write success rate
- [ ] Alerts configured for:
  - Health status degraded/unhealthy
  - High error rate
  - Resource limit approaching

### Graceful Degradation

- [ ] Verify fallback to workspace mode works
- [ ] Test recovery procedures
- [ ] Document known issues and workarounds

### Security

- [ ] Graph storage directory secured
- [ ] Access controls applied to memory operations
- [ ] Sensitive data not stored in graph

## Operational Commands

### Status Check
```elixir
JidoCode.MemoryGraph.ProductService.status(managed_repo_id, workspace_path)
```

### Health Check
```elixir
JidoCode.MemoryGraph.ProductService.health(managed_repo_id, workspace_path)
```

### Refresh Graph
```elixir
JidoCode.AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)
```

### Recover Graph
```elixir
JidoCode.MemoryGraph.ProductService.recover(managed_repo_id, workspace_path)
```

### Query Memory
```elixir
JidoCode.MemoryGraph.ProductService.memories(managed_repo_id, workspace_path, limit: 100)
```

## Cross-Reference

- [Source Code Graph Operations Guide](../specs/source_code_graph.spec.md)
- [Memory Graph Spec](../specs/memory_graph.spec.md)
- [Memory Capture Plane](../specs/memory_capture_plane.spec.md)
