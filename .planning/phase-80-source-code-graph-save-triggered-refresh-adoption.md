# Phase 80 - Source Code Graph Save-Triggered Refresh Adoption

<!-- covers: package.jido_code.spec_led_workspace -->
<!-- covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query -->
<!-- covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently -->
<!-- covers: architecture.agent_os_integration.repo_pod_singleton_when_enabled -->

Back to index: [README](https://github.com/mikehostetler/jido_code/blob/main/.planning/README.md)

## Relevant Shared APIs / Interfaces
- `.planning/phase-20-source-code-graph-pod-foundation.md`
- `.planning/phase-23-source-code-graph-hardening-and-operational-convergence.md`
- `.planning/phase-53-source-code-graph-enablement-and-hardening.md`
- `docs/developer/03-agent-workspace-and-runtime-topology.md`
- `docs/developer/07-source-code-graph-and-semantic-services.md`
- `docs/developer/13-source-code-graph-operations.md`
- `lib/jido_code/agents/repo_monitor.ex`
- `lib/jido_code/pods/repo_pod.ex`
- `lib/jido_code/pods/source_code_graph_pod.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/source_code_graph.ex`
- `lib/jido_code/source_code_graph/store.ex`
- `lib/jido_code/actions/load_source_code_graph.ex`
- `lib/jido_code/actions/refresh_source_code_graph.ex`
- `lib/jido_code/actions/get_source_code_graph_status.ex`
- `lib/jido_code/actions/source_code_graph_support.ex`
- `lib/jido_code/conversations/runtime.ex`
- `lib/jido_code/forge/runners/workflow.ex`
- `lib/jido_code/forge/runners/claude_code.ex`
- `mix.exs`
- `config/config.exs`
- `config/runtime.exs`
- `test/jido_code/source_code_graph_workspace_test.exs`
- `test/jido_code/agent_os/phase_twenty_three_integration_test.exs`
- `test/jido_code/source_code_graph_workflow_service_test.exs`

## Relevant Assumptions / Defaults
- The source-code graph remains repository-local runtime state and not product
  truth; save-triggered refresh should keep it useful without making it a hidden
  dependency for ordinary source reads or edits.
- `RepoPod` and `RepoMonitor` are the right repository-scoped observation seam
  for human editor saves and runtime-managed code writes, while
  `SourceCodeGraphPod` and `AgentWorkspace` remain the only boundaries that
  analyze, load, refresh, query, or recover the graph.
- File-save detection must catch both human editor changes in a local workspace
  and product-controlled LLM writes. Remote or virtual write paths should emit
  the same normalized workspace-source-change signal after successful writes.
- Refresh work is potentially expensive, so saves should enqueue a debounced,
  coalesced refresh rather than running analysis synchronously in the save path.
- Query behavior remains bounded: stale queries still require `allow_stale?: true`
  unless a refresh has already completed.
- The source graph's refresh input set must be shared with revision detection so
  watcher filters, stale detection, and analysis do not drift.

[x] 80 Phase 80 - Source Code Graph Save-Triggered Refresh Adoption
  Add repository-scoped source-change observation and debounced refresh scheduling
  so the `source_code` graph updates after code saves from either a human editor
  or product-managed LLM write path, while preserving explicit graph lifecycle,
  stale-state visibility, and fallback behavior.

  [x] 80.1 Section - Repository-Scoped Source Change Observation Boundary
    Establish one product-owned way to detect and normalize source file changes
    without teaching LiveViews, tool handlers, or graph query code how filesystem
    watching works.

    [x] 80.1.1 Task - Expose the canonical source graph file scope
      Make the graph input set reusable so watcher filtering and revision
      detection agree about what counts as source-code graph input.

      [x] 80.1.1.1 Subtask - Promote the current private source globs and
        exclusion rules in `JidoCode.SourceCodeGraph` into a public helper such
        as `source_file?/2`, `source_files/1`, or `source_patterns/1`.
      [x] 80.1.1.2 Subtask - Keep the canonical input set aligned with current
        revision detection: `mix.exs`, `lib/**/*.ex`, `lib/**/*.exs`,
        `test/**/*.ex`, `test/**/*.exs`, and `config/**/*.exs`, excluding
        `deps`, `_build`, `node_modules`, and repository-local graph storage.
      [x] 80.1.1.3 Subtask - Add coverage proving the watcher filter and
        revision identity use the same source-scope helper instead of duplicating
        path rules.

    [x] 80.1.2 Task - Add repo-monitor source change events
      Turn workspace source saves into repository-scoped observations that can
      be consumed by graph refresh scheduling and operator status surfaces.

      [x] 80.1.2.1 Subtask - Extend `RepoMonitor` or a RepoPod-owned helper with
        a normalized event shape such as `:workspace_source_changed`, carrying
        managed repo id, workspace path, changed paths, detected revision, event
        source, and observed timestamp.
      [x] 80.1.2.2 Subtask - Add a local filesystem watcher for repo-scoped
        local workspaces, using a direct runtime dependency if needed rather than
        relying on transitive development-only watcher packages.
      [x] 80.1.2.3 Subtask - Ignore irrelevant and self-generated paths such as
        `.jido_code/source_code_graph`, `.jido_code/memory_graph`, `_build`,
        `deps`, and `node_modules` so refresh does not recursively trigger from
        graph writes.
      [x] 80.1.2.4 Subtask - Ensure watcher lifecycle follows managed repository
        workspace binding changes, repo runtime startup, and repo runtime
        shutdown without leaving orphaned OS watcher processes.

  [x] 80.2 Section - Save-Origin Coverage For Human And LLM Writes
    Make both external editor saves and product-managed code writes converge on
    the same source-change event instead of creating actor-specific refresh
    behavior.

    [x] 80.2.1 Task - Cover human editor saves through the workspace watcher
      Treat ordinary editor saves as external repository changes that mark the
      graph stale and enqueue refresh without requiring a product UI action.

      [x] 80.2.1.1 Subtask - Detect create, modify, rename, and delete events
        for source-scope files under the managed repository workspace path.
      [x] 80.2.1.2 Subtask - Debounce editor write bursts and atomic-save rename
        patterns into one normalized source-change observation per quiet window.
      [x] 80.2.1.3 Subtask - Preserve current stale status behavior while a
        refresh is queued or running so product surfaces remain honest about
        graph freshness.

    [x] 80.2.2 Task - Add explicit product write notifications for LLM save paths
      Ensure runtime-managed writes emit the same source-change signal even when
      the storage layer is remote, virtualized, or otherwise not visible to a
      local OS watcher.

      [x] 80.2.2.1 Subtask - Add a product-owned helper such as
        `AgentWorkspace.notify_workspace_source_changed/3` or a RepoMonitor
        action that write-capable runtime boundaries can call after successful
        code writes.
      [x] 80.2.2.2 Subtask - Wire product-controlled write paths, including
        Forge/Sprite write helpers and LLM runner save boundaries, to emit the
        normalized change event only after the write succeeds.
      [x] 80.2.2.3 Subtask - Include event source metadata such as
        `:human_watcher`, `:llm_write`, `:tool_write`, or `:runtime_write`
        without changing graph refresh semantics by actor type.
      [x] 80.2.2.4 Subtask - Keep external LLM or CLI edits covered by the
        filesystem watcher whenever they touch a local workspace on disk.

  [x] 80.3 Section - Debounced Source Graph Refresh Scheduling
    Convert source-change observations into bounded graph refresh work that is
    reliable under save bursts and does not block editing, tool execution, or
    conversation progress.

    [x] 80.3.1 Task - Introduce a per-repository refresh coordinator
      Add one repo-scoped scheduler that owns debounce, coalescing, in-flight
      protection, and retry visibility for source graph refresh requests.

      [x] 80.3.1.1 Subtask - Add a RepoPod-owned or AgentWorkspace-owned
        coordinator that queues refresh requests per managed repo and workspace
        path with configurable debounce and maximum coalescing windows.
      [x] 80.3.1.2 Subtask - Prevent overlapping source graph refreshes for the
        same managed repo; if another save arrives while refresh is in flight,
        mark a follow-up refresh as pending and run it after the current refresh
        completes.
      [x] 80.3.1.3 Subtask - Keep refresh work asynchronous from the save path,
        returning event acceptance promptly while recording queued, running,
        succeeded, skipped, and failed scheduler states.
      [x] 80.3.1.4 Subtask - Add bounded retries or handoff to
        `recover_source_code_graph/3` for refresh failures without creating an
        infinite analysis loop.

    [x] 80.3.2 Task - Reuse explicit graph lifecycle entrypoints
      Preserve the current source graph lifecycle by routing scheduler work
      through `AgentWorkspace` rather than writing to TripleStore directly.

      [x] 80.3.2.1 Subtask - For ready stale graphs, call
        `AgentWorkspace.refresh_source_code_graph/3` so the existing staged
        replacement behavior remains canonical.
      [x] 80.3.2.2 Subtask - For missing graphs, make policy explicit: either
        leave the graph not-ready until semantic use requests `load_if_missing`,
        or enqueue `load_source_code_graph/3` behind an opt-in configuration.
      [x] 80.3.2.3 Subtask - For disabled source graph configuration, drop or
        record the event as skipped without starting watcher or refresh work.
      [x] 80.3.2.4 Subtask - Persist refresh diagnostics on the existing source
        graph pod metadata so product surfaces and recovery actions can explain
        queued, stale, failed, and refreshed states.

  [x] 80.4 Section - Operator Visibility And Runtime Degradation
    Surface save-triggered refresh as a bounded runtime capability without
    making the graph feel magically current when refresh is queued, disabled,
    or degraded.

    [x] 80.4.1 Task - Extend source graph status projections with refresh activity
      Make background refresh state visible to product helpers and operator
      surfaces through existing bounded projection layers.

      [x] 80.4.1.1 Subtask - Extend source graph status or health projections
        with fields such as `auto_refresh`, `last_source_change_at`,
        `last_refresh_started_at`, `last_refresh_completed_at`,
        `refresh_queued?`, and `refresh_in_flight?`.
      [x] 80.4.1.2 Subtask - Keep existing ready, stale, degraded, and recovery
        labels authoritative while adding refresh activity as supporting context.
      [x] 80.4.1.3 Subtask - Update managed-repo semantic inspection and
        dashboard monitoring hints to explain queued or failed background
        refresh without exposing watcher internals.

    [x] 80.4.2 Task - Add configuration and contributor guidance
      Make save-triggered refresh safe to enable by environment, workspace type,
      and repository size.

      [x] 80.4.2.1 Subtask - Add configuration for auto-refresh enablement,
        debounce interval, maximum coalescing delay, watcher path limits, and
        missing-graph load policy.
      [x] 80.4.2.2 Subtask - Default auto-refresh conservatively for production
        while keeping local development behavior useful when the source graph is
        enabled.
      [x] 80.4.2.3 Subtask - Update source graph developer and operations docs
        to explain human editor saves, LLM write notifications, debounce,
        skipped refreshes, and manual recovery.
      [x] 80.4.2.4 Subtask - Align contributor guidance so future write-capable
        tools emit the normalized source-change notification rather than calling
        graph refresh directly.

  [x] 80.5 Section - Phase 80 Integration Tests
    Prove save-triggered refresh updates the source graph for human and LLM
    saves while preserving stale-query semantics, explicit lifecycle boundaries,
    and operational safety.

    [x] 80.5.1 Task - Add source-change observation and scheduler coverage
      Verify file saves become bounded repo-scoped refresh requests without
      duplicated path rules or overlapping graph writes.

      [x] 80.5.1.1 Subtask - Add unit coverage for source file scope filtering,
        ignored directories, deleted files, atomic-save renames, and graph-store
        self-write suppression.
      [x] 80.5.1.2 Subtask - Add GenServer or action-level coverage proving
        repeated save events coalesce into one refresh during the debounce
        window.
      [x] 80.5.1.3 Subtask - Add coverage proving in-flight refresh coalescing
        schedules one follow-up refresh when more saves arrive during analysis
        or load.
      [x] 80.5.1.4 Subtask - Add coverage proving disabled configuration skips
        watchers and refresh scheduling without breaking manual load, refresh,
        status, or query entrypoints.

    [x] 80.5.2 Task - Add end-to-end human and LLM save refresh scenarios
      Exercise the full repository-scoped path from save event to refreshed graph
      status through product-owned boundaries.

      [x] 80.5.2.1 Subtask - Add an integration test that loads a graph, changes
        a local source file through a simulated watcher event, waits for the
        debounced refresh, and verifies the graph imports the new revision.
      [x] 80.5.2.2 Subtask - Add an integration test that simulates a
        product-controlled LLM write notification and verifies it follows the
        same refresh path as a watcher event.
      [x] 80.5.2.3 Subtask - Add coverage proving stale queries still fail
        without `allow_stale?: true` while refresh is queued or failed, and
        return current results after refresh completes.
      [x] 80.5.2.4 Subtask - Run and document `mix source_graph.verify`, plus
        any targeted RepoPod, conversation-runtime, or Forge write-path tests
        touched by the implementation.
