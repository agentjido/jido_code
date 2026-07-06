# Phase 4 - Product Entrypoint Cutover

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_workspace/runtime_specialist_runner.ex`
- `lib/jido_code/agent_workspace/deterministic_specialist_runner.ex`
- `lib/jido_code/agents/repo_monitor/source_watcher.ex`
- `lib/jido_code/source_code_graph/refresh_scheduler.ex`
- `lib/jido_code/actions/*source_code_graph*.ex`
- `lib/jido_code/actions/*memory_graph*.ex`
- `lib/jido_code/conversations/`
- `test/jido_code/agent_workspace_test.exs`
- `test/jido_code/source_code_graph*_test.exs`
- `test/jido_code/memory_graph*_test.exs`
- `test/jido_code/context_management_test.exs`

## Relevant Assumptions / Defaults

- Product callers should use runtime or workspace vocabulary, not AgentOS
  kernel vocabulary.
- `AgentWorkspace` can remain the high-level product context while its internals
  move to `JidoCode.Runtime`.
- Source-code graph, memory graph, context management, and conversation
  workflows keep their product behavior while the runtime boundary changes.
- Greenfield cutover means tests and callers can be updated directly instead of
  preserving old kernel-shaped return values.

[-] 4 Phase 4 - Product Entrypoint Cutover
  Route product entrypoints through the repository runtime container so user
  workflows no longer depend on AgentOS manager, kernel status, naming, or
  persistence modules.

  [x] 4.1 Section - AgentWorkspace Runtime Routing
    Convert the main product context to use `JidoCode.Runtime` while keeping
    its role as the boundary for controllers, LiveViews, conversations, and
    workflow services.

    [x] 4.1.1 Task - Replace kernel lifecycle functions
      Update lifecycle APIs and call sites to return repository runtime
      reports instead of AgentOS kernel names.

      [x] 4.1.1.1 Subtask - Replace `ensure_kernel/1` internals with `JidoCode.Runtime.ensure_repository/2` or a new product-owned equivalent.
      [x] 4.1.1.2 Subtask - Replace `kernel_status/1`, `list_kernels/0`, `kernel_count/0`, and `shutdown_kernel/1` with runtime status APIs.
      [x] 4.1.1.3 Subtask - Rename public functions where greenfield cleanup is clearer than keeping kernel vocabulary.
      [x] 4.1.1.4 Subtask - Update status snapshots to remove `kernel_name` and AgentOS supervisor pid fields.

    [x] 4.1.2 Task - Replace pod lifecycle functions
      Route work-item, graph, memory, and context pod creation through the
      repository runtime process.

      [x] 4.1.2.1 Subtask - Replace `ensure_runtime_coding_pod/3` with runtime-owned coding pod ensure calls.
      [x] 4.1.2.2 Subtask - Replace repo pod restoration with runtime-owned repo pod ensure calls.
      [x] 4.1.2.3 Subtask - Replace source-code graph pod ensure calls with runtime-owned source graph pod ensure calls.
      [x] 4.1.2.4 Subtask - Replace memory graph and context-management pod ensure calls with runtime-owned ensure calls.

  [x] 4.2 Section - Specialist and Agent Routing
    Ensure planning, coding, review, refactoring, explanation, and context
    management find pod nodes through native Jido pod lookup.

    [x] 4.2.1 Task - Update specialist runner lookup
      Remove AgentOS naming and pod id assumptions from runtime specialist
      dispatch.

      [x] 4.2.1.1 Subtask - Locate the active coding pod through `JidoCode.Runtime` using ManagedRepo ID and WorkItem ID.
      [x] 4.2.1.2 Subtask - Locate specialists with `Jido.Pod.lookup_node/2` or `Jido.Pod.ensure_node/3`.
      [x] 4.2.1.3 Subtask - Keep deterministic specialist runner tests independent of runtime process identity.
      [x] 4.2.1.4 Subtask - Return structured errors when a runtime, pod, or specialist node is unavailable.

    [x] 4.2.2 Task - Update work completion and cleanup
      Make work-item completion release runtime state and pod ownership without
      AgentOS pod tracking.

      [x] 4.2.2.1 Subtask - Route `complete_work/2` through repository runtime admission and work pod cleanup.
      [x] 4.2.2.2 Subtask - Ensure completed work disappears from active work-item status.
      [x] 4.2.2.3 Subtask - Ensure failed cleanup leaves a degraded runtime diagnostic instead of crashing product callers.
      [x] 4.2.2.4 Subtask - Update conversation and context-management completion paths to use the same cleanup behavior.

  [x] 4.3 Section - Cross-Workflow Runtime Adoption
    Update background services and graph workflows that currently use AgentOS
    manager state as a repository-scoped runtime lookup.

    [x] 4.3.1 Task - Cut over source monitoring and graph refresh callers
      Route source watcher and refresh scheduler dependencies through runtime
      status and repository-scoped pod APIs.

      [x] 4.3.1.1 Subtask - Update `RepoMonitor.SourceWatcher` AgentOS manager calls to runtime APIs.
      [x] 4.3.1.2 Subtask - Update source-code graph refresh scheduler AgentOS manager calls to runtime APIs.
      [x] 4.3.1.3 Subtask - Preserve explicit analyze, load, refresh, and query behavior for source-code graph actions.
      [x] 4.3.1.4 Subtask - Keep stale graph and unavailable graph diagnostics bounded and product-readable.

    [x] 4.3.2 Task - Cut over memory and context workflows
      Route memory graph and context-management product workflows through the
      new runtime without changing governed memory semantics.

      [x] 4.3.2.1 Subtask - Update memory graph status, refresh, record, query, validate, invalidate, and recover flows to use runtime-owned pods.
      [x] 4.3.2.2 Subtask - Update context observation, compaction, reset, and prompt-packing flows to use runtime-owned context pods.
      [x] 4.3.2.3 Subtask - Preserve capture-envelope and governed-reference boundaries.
      [x] 4.3.2.4 Subtask - Preserve conversation-derived recall and workflow provenance behavior across runtime cutover.

  [ ] 4.4 Section - Phase 4 Integration Tests
    Prove product workflows use the repository runtime container and no longer
    need AgentOS modules for normal operation.

    [ ] 4.4.1 Task - Product workflow scenarios
      Exercise the high-level product APIs that operators and workflows already
      depend on.

      [ ] 4.4.1.1 Subtask - Run `mix test test/jido_code/agent_workspace_test.exs`.
      [ ] 4.4.1.2 Subtask - Run focused source-code graph workflow tests that call `AgentWorkspace`.
      [ ] 4.4.1.3 Subtask - Run focused memory graph workflow tests that call `AgentWorkspace`.
      [ ] 4.4.1.4 Subtask - Run focused context-management and conversation runtime tests that ensure coding pods.
      [ ] 4.4.1.5 Subtask - Add a regression test that product snapshots no longer expose `kernel_name`.
