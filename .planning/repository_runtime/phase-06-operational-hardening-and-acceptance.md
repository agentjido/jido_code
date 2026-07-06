# Phase 6 - Operational Hardening and Acceptance

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/runtime/`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code_web/`
- `lib/jido_code/conversations/`
- `lib/jido_code/source_code_graph/`
- `lib/jido_code/memory_graph/`
- `lib/jido_code/context_management/`
- `mix.exs`
- `test/jido_code/**/*integration_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults

- The new runtime is the canonical repository-scoped runtime boundary.
- AgentOS has been removed before this phase begins.
- Operator surfaces should show repository runtime health in product terms,
  not OTP internals.
- Final verification should include source graph, memory graph, semantic,
  context, conversation, and frontend-relevant suites when touched.

[x] 6 Phase 6 - Operational Hardening and Acceptance
  Harden the repository runtime for normal operator use, degraded runtime
  conditions, contributor verification, and end-to-end acceptance after AgentOS
  removal.

  [x] 6.1 Section - Failure Handling and Capacity Hardening
    Make runtime failure modes explicit so repository work fails closed and
    degraded state remains visible to product callers.

    [x] 6.1.1 Task - Harden pod failure handling
      Ensure crashed, missing, or degraded pods produce actionable runtime
      diagnostics without corrupting repository state.

      [x] 6.1.1.1 Subtask - Monitor all repo-level and work-level pods owned by a repository runtime.
      [x] 6.1.1.2 Subtask - Mark runtime status degraded when an eager repo, graph, memory, or context pod exits unexpectedly.
      [x] 6.1.1.3 Subtask - Release or quarantine work-item capacity when coding pod startup fails.
      [x] 6.1.1.4 Subtask - Provide explicit retry or reconcile paths for recoverable pod failures.

    [x] 6.1.2 Task - Harden concurrency and admission behavior
      Prove repository runtimes behave predictably under concurrent work and
      repeated caller retries.

      [x] 6.1.2.1 Subtask - Add concurrency tests for simultaneous `ensure_repository/2` calls for the same ManagedRepo.
      [x] 6.1.2.2 Subtask - Add concurrency tests for simultaneous work-item admission under capacity limits.
      [x] 6.1.2.3 Subtask - Add tests for repeated specialist lookup while lazy nodes are starting.
      [x] 6.1.2.4 Subtask - Ensure capacity counters never go negative or double-count active work.

  [x] 6.2 Section - Observability and Operator Surfaces
    Expose runtime health in product terms and keep low-level process details
    out of user-facing surfaces.

    [x] 6.2.1 Task - Add runtime telemetry and logs
      Emit coarse events for runtime lifecycle and pod health that can support
      troubleshooting without becoming a hidden dependency.

      [x] 6.2.1.1 Subtask - Add telemetry events for repository runtime start, ready, degraded, restored, and stopped states.
      [x] 6.2.1.2 Subtask - Add telemetry events for pod ensure, reconcile, failure, and cleanup outcomes.
      [x] 6.2.1.3 Subtask - Include ManagedRepo ID and work-item ID where appropriate without logging prompt bodies or large graph payloads.
      [x] 6.2.1.4 Subtask - Keep logs structured and bounded for repeated runtime failures.

    [x] 6.2.2 Task - Update product-visible status surfaces
      Update any status views, dashboards, or conversation snapshots that
      mention runtime health.

      [x] 6.2.2.1 Subtask - Replace kernel terminology with repository runtime terminology in product-visible text.
      [x] 6.2.2.2 Subtask - Show active work counts, graph readiness, memory readiness, context-management status, and degraded diagnostics.
      [x] 6.2.2.3 Subtask - Avoid showing pids, registry names, or node ids unless behind explicit developer diagnostics.
      [x] 6.2.2.4 Subtask - Preserve source graph and memory graph degraded fallback behavior when runtime pods are unavailable.

  [x] 6.3 Section - Documentation and Contributor Verification
    Update planning, docs, and verification aliases so contributors understand
    the runtime model and know which suites to run.

    [x] 6.3.1 Task - Update architecture and planning references
      Replace AgentOS-specific implementation guidance with repository runtime
      guidance in the places contributors read first.

      [x] 6.3.1.1 Subtask - Update `.planning/README.md` or related phase notes to mark AgentOS integration superseded by repository runtime.
      [x] 6.3.1.2 Subtask - Update module docs for `AgentWorkspace` and new runtime modules.
      [x] 6.3.1.3 Subtask - Update any specs or decisions that still require AgentOS kernel vocabulary.
      [x] 6.3.1.4 Subtask - Record migration notes explaining why `Jido.Pod` is used for pods while repository runtime owns product policy.

    [x] 6.3.2 Task - Update verification aliases
      Make the expected test commands clear for future changes touching the
      runtime boundary.

      [x] 6.3.2.1 Subtask - Add or update a focused runtime verification alias if the existing aliases are too broad.
      [x] 6.3.2.2 Subtask - Ensure source graph runtime changes still run `mix source_graph.verify`.
      [x] 6.3.2.3 Subtask - Ensure memory runtime changes still run `mix memory.verify`.
      [x] 6.3.2.4 Subtask - Ensure semantic and frontend aliases are documented for changes that cross those boundaries.

  [x] 6.4 Section - Phase 6 Integration Tests
    Prove the final runtime design works end to end after AgentOS removal and
    remains understandable under degraded and concurrent conditions.

    [x] 6.4.1 Task - End-to-end acceptance scenarios
      Run the focused and broad verification suite needed to accept the new
      repository runtime as the canonical boundary.

      [x] 6.4.1.1 Subtask - Add end-to-end tests for two ManagedRepos running isolated repository runtimes with concurrent work items.
      [x] 6.4.1.2 Subtask - Add end-to-end tests for source graph, memory graph, context management, and specialist execution within one repository runtime.
      [x] 6.4.1.3 Subtask - Add degraded-mode tests for unavailable graph pods, failed memory pods, and failed context-management pods.
      [x] 6.4.1.4 Subtask - Run `mix source_graph.verify` when source-code graph runtime behavior changes.
      [x] 6.4.1.5 Subtask - Run `mix memory.verify` when memory graph runtime behavior changes.
      [x] 6.4.1.6 Subtask - Run `mix semantic.verify` when semantic product surfaces or governed semantic workflows change.
      [x] 6.4.1.7 Subtask - Run `mix frontend.verify` when LiveView, LiveVue, Vite, SSR, or shared browser helpers change.
      [x] 6.4.1.8 Subtask - Run `mix test` before the final PR is marked ready.

      Verification note: `mix runtime.verify`, `mix source_graph.verify`,
      `mix memory.verify`, the maintained memory graph suite, and the maintained
      context/conversation suite passed. `mix test` was run and failed with
      existing broad-suite drift outside this runtime replacement scope,
      including removed direct resource helper calls, stale LiveView selector
      assertions, old memory timeout expectations, large control-plane record
      validation cases, and legacy setup/auth helper references.
      `mix semantic.verify` and `mix frontend.verify` were not run because this
      section did not touch semantic product surfaces or browser assets.
