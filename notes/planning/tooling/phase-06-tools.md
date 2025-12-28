# Phase 6: Testing & Polish

This final phase focuses on comprehensive integration testing, advanced search tools (if time permits), documentation, and performance optimization. It ensures all tools work together reliably and are well-documented.

## Goals in This Phase

| Goal | Priority |
|------|----------|
| Comprehensive integration tests | Critical |
| Cross-session isolation tests | Critical |
| Concurrent execution tests | Critical |
| Codebase search (embeddings) | Optional |
| Repository map (AST) | Optional |
| Tool reference documentation | Required |
| Security model documentation | Required |
| Performance optimization | Required |

---

## 6.1 Comprehensive Integration Tests

End-to-end tests verifying complete tool chains work together correctly.

### 6.1.1 Full Tool Chain Tests

Test realistic workflows using multiple tools in sequence.

- [ ] 6.1.1.1 Create `test/jido_code/integration/full_workflow_test.exs`
- [ ] 6.1.1.2 Test: File creation workflow
  ```
  glob_search (find similar files) ->
  read_file (read template) ->
  write_file (create new file) ->
  edit_file (customize content) ->
  grep_search (verify changes) ->
  git_command (stage changes)
  ```
- [ ] 6.1.1.3 Test: Bug fix workflow
  ```
  grep_search (find bug location) ->
  read_file (understand context) ->
  edit_file (apply fix) ->
  run_exunit (verify fix) ->
  git_command (commit)
  ```
- [ ] 6.1.1.4 Test: Refactoring workflow
  ```
  find_references (find usages) ->
  multi_edit (update all usages) ->
  get_diagnostics (check for errors) ->
  run_exunit (verify no regressions)
  ```
- [ ] 6.1.1.5 Test: Documentation workflow
  ```
  fetch_elixir_docs (check existing) ->
  read_file (read source) ->
  edit_file (add docs) ->
  mix_task (check with ex_doc)
  ```

### 6.1.2 Error Recovery Tests

Test error handling and recovery across tool chains.

- [ ] 6.1.2.1 Test: Edit fails -> original file preserved
- [ ] 6.1.2.2 Test: Background process fails -> error captured
- [ ] 6.1.2.3 Test: LSP connection lost -> graceful degradation
- [ ] 6.1.2.4 Test: Network timeout -> cached results used
- [ ] 6.1.2.5 Test: Concurrent edits -> conflict detection

---

## 6.2 Cross-Session Tool Isolation Tests

Ensure tools respect session boundaries and don't leak state.

### 6.2.1 Session Isolation

Test that sessions are properly isolated.

- [ ] 6.2.1.1 Create `test/jido_code/integration/session_isolation_test.exs`
- [ ] 6.2.1.2 Test: Session A file reads don't affect Session B
- [ ] 6.2.1.3 Test: Session A background processes isolated from Session B
- [ ] 6.2.1.4 Test: Session A todo list separate from Session B
- [ ] 6.2.1.5 Test: Session A subagents separate from Session B
- [ ] 6.2.1.6 Test: Session close cleans up all resources

### 6.2.2 State Persistence

Test session state persistence and restoration.

- [ ] 6.2.2.1 Test: Session save preserves read file tracking
- [ ] 6.2.2.2 Test: Session save preserves todo list
- [ ] 6.2.2.3 Test: Session resume restores read file tracking
- [ ] 6.2.2.4 Test: Session resume restores todo list
- [ ] 6.2.2.5 Test: Corrupted session data handled gracefully

---

## 6.3 Concurrent Tool Execution Tests

Test tools running simultaneously without interference.

### 6.3.1 Parallel Execution

Test parallel tool execution.

- [ ] 6.3.1.1 Create `test/jido_code/integration/concurrent_tools_test.exs`
- [ ] 6.3.1.2 Test: Multiple grep_search in parallel
- [ ] 6.3.1.3 Test: Multiple read_file in parallel
- [ ] 6.3.1.4 Test: bash_execute while bash_background running
- [ ] 6.3.1.5 Test: Multiple subagents in parallel
- [ ] 6.3.1.6 Test: Mixed read/write operations (should serialize)

### 6.3.2 Resource Contention

Test resource contention handling.

- [ ] 6.3.2.1 Test: Concurrent edits to same file
- [ ] 6.3.2.2 Test: Concurrent writes create conflict
- [ ] 6.3.2.3 Test: Background process output during new command
- [ ] 6.3.2.4 Test: LSP requests during file changes

---

## 6.4 Advanced Search Tools (Optional)

Implement advanced semantic search if time permits.

### 6.4.1 Codebase Search Tool

Implement semantic code search with embeddings.

- [ ] 6.4.1.1 Create `lib/jido_code/tools/definitions/codebase_search.ex`
- [ ] 6.4.1.2 Define schema:
  ```elixir
  %{
    query: %{type: :string, required: true, description: "Natural language query"},
    file_type: %{type: :string, required: false, description: "Filter by file type"},
    limit: %{type: :integer, required: false, description: "Max results"}
  }
  ```
- [ ] 6.4.1.3 Create `lib/jido_code/tools/handlers/search/codebase.ex`
- [ ] 6.4.1.4 Implement file chunking strategy
- [ ] 6.4.1.5 Generate embeddings for code chunks
- [ ] 6.4.1.6 Store embeddings in vector index
- [ ] 6.4.1.7 Query with cosine similarity
- [ ] 6.4.1.8 Return ranked results with snippets

### 6.4.2 Repository Map Tool

Implement AST-based repository structure mapping.

- [ ] 6.4.2.1 Create `lib/jido_code/tools/definitions/repo_map.ex`
- [ ] 6.4.2.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: false, description: "Subdirectory to map"},
    depth: %{type: :integer, required: false, description: "Max depth"},
    include_private: %{type: :boolean, required: false, description: "Include private functions"}
  }
  ```
- [ ] 6.4.2.3 Create `lib/jido_code/tools/handlers/search/repo_map.ex`
- [ ] 6.4.2.4 Parse Elixir files with Code.string_to_quoted
- [ ] 6.4.2.5 Extract module structure:
  - Module name and location
  - Public function signatures
  - Type definitions
  - Module attributes (@moduledoc, @doc)
- [ ] 6.4.2.6 Generate tree representation
- [ ] 6.4.2.7 Cache AST parsing results

### 6.4.3 Unit Tests for Advanced Search

- [ ] Test codebase_search finds semantically relevant code
- [ ] Test codebase_search ranking accuracy
- [ ] Test repo_map generates correct structure
- [ ] Test repo_map respects depth limit

---

## 6.5 Documentation

Create comprehensive documentation for all tools.

### 6.5.1 Tool Reference Documentation

Create reference documentation for each tool.

- [ ] 6.5.1.1 Create `guides/tools/file-operations.md`
  - Document read_file, write_file, edit_file, multi_edit, list_dir, glob_search, delete_file
  - Include examples for each
  - Document error conditions
- [ ] 6.5.1.2 Create `guides/tools/search-shell.md`
  - Document grep_search, bash_execute, bash_background, bash_output, kill_shell
  - Include examples for each
  - Document timeout and output limits
- [ ] 6.5.1.3 Create `guides/tools/git-lsp.md`
  - Document git_command, get_diagnostics, get_hover_info, go_to_definition, find_references
  - Include examples for each
  - Document LSP requirements
- [ ] 6.5.1.4 Create `guides/tools/web-agent.md`
  - Document web_fetch, web_search, spawn_subagent, todo_write, todo_read, ask_user
  - Include examples for each
  - Document domain restrictions
- [ ] 6.5.1.5 Create `guides/tools/elixir-runtime.md`
  - Document iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit
  - Include examples for each
  - Document safety considerations

### 6.5.2 Tool Development Guide

Create guide for developing new tools.

- [ ] 6.5.2.1 Create `guides/developer/tool-development.md`
- [ ] 6.5.2.2 Document tool definition structure
- [ ] 6.5.2.3 Document handler implementation patterns
- [ ] 6.5.2.4 Document testing requirements
- [ ] 6.5.2.5 Document security considerations
- [ ] 6.5.2.6 Include example tool implementation

### 6.5.3 Security Model Documentation

Document the security model.

- [ ] 6.5.3.1 Create `guides/developer/security-model.md`
- [ ] 6.5.3.2 Document path boundary validation
- [ ] 6.5.3.3 Document command allowlist
- [ ] 6.5.3.4 Document domain restrictions
- [ ] 6.5.3.5 Document session isolation
- [ ] 6.5.3.6 Document read-before-write pattern

---

## 6.6 Performance Optimization

Optimize tool performance for large codebases.

### 6.6.1 Tool Result Caching

Implement caching for expensive operations.

- [ ] 6.6.1.1 Create `lib/jido_code/tools/cache.ex`
- [ ] 6.6.1.2 Implement ETS-based cache with TTL
- [ ] 6.6.1.3 Add cache keys based on tool + args hash
- [ ] 6.6.1.4 Add cache invalidation on file changes
- [ ] 6.6.1.5 Cache expensive operations:
  - grep_search results (5 minute TTL)
  - glob_search results (1 minute TTL)
  - web_fetch results (15 minute TTL)
  - LSP diagnostics (30 second TTL)
  - repo_map results (10 minute TTL)

### 6.6.2 Output Streaming

Implement streaming for large outputs.

- [ ] 6.6.2.1 Create streaming interface for tool results
- [ ] 6.6.2.2 Stream bash_execute output incrementally
- [ ] 6.6.2.3 Stream grep_search results incrementally
- [ ] 6.6.2.4 Stream read_file content for large files
- [ ] 6.6.2.5 Update TUI to display streaming output

### 6.6.3 Parallel Tool Execution

Optimize parallel execution where safe.

- [ ] 6.6.3.1 Identify parallelizable tool combinations
- [ ] 6.6.3.2 Implement parallel execution infrastructure
- [ ] 6.6.3.3 Add concurrency limits to prevent resource exhaustion
- [ ] 6.6.3.4 Test parallel execution performance gains

### 6.6.4 Performance Tests

Create performance benchmarks.

- [ ] 6.6.4.1 Create `test/jido_code/performance/tools_benchmark_test.exs`
- [ ] 6.6.4.2 Benchmark grep_search on large codebase
- [ ] 6.6.4.3 Benchmark glob_search with many files
- [ ] 6.6.4.4 Benchmark read_file with large files
- [ ] 6.6.4.5 Benchmark concurrent tool execution
- [ ] 6.6.4.6 Document performance characteristics

---

## 6.7 Final Integration Tests

Final comprehensive tests before release.

### 6.7.1 Smoke Tests

Quick tests to verify basic functionality.

- [ ] 6.7.1.1 Create `test/jido_code/integration/smoke_test.exs`
- [ ] 6.7.1.2 Test each tool with minimal valid input
- [ ] 6.7.1.3 Test each tool with invalid input (error handling)
- [ ] 6.7.1.4 Test tool registration and discovery
- [ ] 6.7.1.5 Test tool execution through executor

### 6.7.2 Stress Tests

Tests under load conditions.

- [ ] 6.7.2.1 Create `test/jido_code/integration/stress_test.exs`
- [ ] 6.7.2.2 Test 100+ concurrent tool calls
- [ ] 6.7.2.3 Test memory usage under load
- [ ] 6.7.2.4 Test recovery from resource exhaustion
- [ ] 6.7.2.5 Test long-running background processes

---

## Phase 6 Success Criteria

1. **Integration Tests**: All tool chain workflows pass
2. **Session Isolation**: Tools respect session boundaries
3. **Concurrent Execution**: No race conditions or data corruption
4. **Documentation**: All tools documented with examples
5. **Security Documentation**: Security model clearly documented
6. **Performance**: Acceptable performance on large codebases
7. **Test Coverage**: Minimum 80% overall test coverage

---

## Phase 6 Critical Files

**New Files:**
- `test/jido_code/integration/full_workflow_test.exs`
- `test/jido_code/integration/session_isolation_test.exs`
- `test/jido_code/integration/concurrent_tools_test.exs`
- `test/jido_code/integration/smoke_test.exs`
- `test/jido_code/integration/stress_test.exs`
- `test/jido_code/performance/tools_benchmark_test.exs`
- `lib/jido_code/tools/cache.ex`
- `guides/tools/file-operations.md`
- `guides/tools/search-shell.md`
- `guides/tools/git-lsp.md`
- `guides/tools/web-agent.md`
- `guides/tools/elixir-runtime.md`
- `guides/developer/tool-development.md`
- `guides/developer/security-model.md`

**Optional Files (Advanced Search):**
- `lib/jido_code/tools/definitions/codebase_search.ex`
- `lib/jido_code/tools/definitions/repo_map.ex`
- `lib/jido_code/tools/handlers/search/codebase.ex`
- `lib/jido_code/tools/handlers/search/repo_map.ex`

---

## Summary: All Phases Complete

Upon completion of Phase 6, JidoCode will have:

| Category | Tools | Count |
|----------|-------|-------|
| File Operations | read_file, write_file, edit_file, multi_edit, list_dir, glob_search, delete_file | 7 |
| Code Search | grep_search, (codebase_search, repo_map optional) | 1-3 |
| Shell Execution | bash_execute, bash_background, bash_output, kill_shell | 4 |
| Git Operations | git_command | 1 |
| LSP Integration | get_diagnostics, get_hover_info, go_to_definition, find_references | 4 |
| Web Tools | web_fetch, web_search | 2 |
| Agent/Task | spawn_subagent, get_task_output, todo_write, todo_read, ask_user | 5 |
| Elixir-Specific | iex_eval, mix_task, get_process_state, inspect_supervisor, reload_module, ets_inspect, fetch_elixir_docs, run_exunit | 8 |
| **Total** | | **32-34** |

All tools will have:
- Complete test coverage (80%+)
- Comprehensive documentation
- Security boundary enforcement
- Performance optimization
- Session isolation
