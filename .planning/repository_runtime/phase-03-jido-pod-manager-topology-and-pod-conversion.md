# Phase 3 - Jido.Pod Manager Topology and Pod Conversion

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/pods/repo_pod.ex`
- `lib/jido_code/pods/coding_pod.ex`
- `lib/jido_code/pods/source_code_graph_pod.ex`
- `lib/jido_code/pods/memory_graph_pod.ex`
- `lib/jido_code/pods/context_management_pod.ex`
- `lib/jido_code/pods/empty.ex`
- `lib/jido_code/agents/`
- `lib/jido_code/application.ex`
- `deps/jido/lib/jido/pod.ex`
- `deps/jido/lib/jido/pod/runtime.ex`
- `deps/jido/lib/jido/agent/instance_manager.ex`
- `test/jido_code/agent_os/pods_test.exs`
- `test/jido_code/agent_os/ai_agents_test.exs`

## Relevant Assumptions / Defaults

- Pod modules remain product-owned modules under `JidoCode.Pods`.
- `Jido.Pod` replaces `Jido.AgentOS.Pod`.
- Every topology node references a static application-owned
  `Jido.Agent.InstanceManager`.
- Dynamic pod identity comes from tuple keys passed to pod managers.

[ ] 3 Phase 3 - Jido.Pod Manager Topology and Pod Conversion
  Convert the local pod topology to native `Jido.Pod` and static
  `Jido.Agent.InstanceManager` ownership so repository runtimes can start pods
  directly without AgentOS manager, naming, or persistence helpers.

  [x] 3.1 Section - Static Instance Manager Inventory
    Define every pod manager and node manager needed by the local runtime
    before changing pod modules.

    [x] 3.1.1 Task - Define pod instance managers
      Add a stable manager for each pod type so `Jido.Pod.get/3` can start
      repository-scoped and work-item-scoped pods.

      [x] 3.1.1.1 Subtask - Add manager child spec for `JidoCode.Pods.RepoPod`.
      [x] 3.1.1.2 Subtask - Add manager child spec for `JidoCode.Pods.CodingPod`.
      [x] 3.1.1.3 Subtask - Add manager child spec for `JidoCode.Pods.SourceCodeGraphPod`.
      [x] 3.1.1.4 Subtask - Add manager child spec for `JidoCode.Pods.MemoryGraphPod`.
      [x] 3.1.1.5 Subtask - Add manager child spec for `JidoCode.Pods.ContextManagementPod`.

    [x] 3.1.2 Task - Define node instance managers
      Add stable managers for eager and lazy topology agents so pod
      reconciliation can start and adopt child nodes consistently.

      [x] 3.1.2.1 Subtask - Add managers for `RepoMonitor` and `WorkRegistry`.
      [x] 3.1.2.2 Subtask - Add managers for `TaskBoard`, `ProjectContext`, `Planner`, `Coder`, `Reviewer`, `Refactorer`, and `Explainer`.
      [x] 3.1.2.3 Subtask - Add managers for source-code graph agents used by `SourceCodeGraphPod`.
      [x] 3.1.2.4 Subtask - Add managers for memory graph agents used by `MemoryGraphPod`.
      [x] 3.1.2.5 Subtask - Add managers for context-management agents used by `ContextManagementPod`.

  [ ] 3.2 Section - Pod Module Conversion
    Replace AgentOS macros and topology metadata with native `Jido.Pod`
    definitions that keep the same product-owned agents and actions.

    [ ] 3.2.1 Task - Convert repository and work pods
      Move the core repo and coding pods onto `Jido.Pod` while preserving eager
      and lazy activation behavior.

      [ ] 3.2.1.1 Subtask - Change `RepoPod` to `use Jido.Pod` with static manager atoms in topology.
      [ ] 3.2.1.2 Subtask - Change `CodingPod` to `use Jido.Pod` with eager `TaskBoard` and `ProjectContext` nodes.
      [ ] 3.2.1.3 Subtask - Preserve lazy specialist activation for planner, coder, reviewer, refactorer, and explainer nodes.
      [ ] 3.2.1.4 Subtask - Remove AgentOS signal route compatibility entries that are no longer needed by product behavior.

    [ ] 3.2.2 Task - Convert graph and context pods
      Move source graph, memory graph, and context-management pods onto the
      same native Jido pod model.

      [ ] 3.2.2.1 Subtask - Change `SourceCodeGraphPod` to `use Jido.Pod` with repository-scoped pod keys.
      [ ] 3.2.2.2 Subtask - Change `MemoryGraphPod` to `use Jido.Pod` with repository-scoped pod keys.
      [ ] 3.2.2.3 Subtask - Change `ContextManagementPod` to `use Jido.Pod` with `{managed_repo_id, work_item_id}` keys.
      [ ] 3.2.2.4 Subtask - Delete `Empty` pod if it only exists to satisfy AgentOS kernel startup behavior.

  [ ] 3.3 Section - Repository Runtime Pod Ownership
    Wire the new repository runtime process to pod managers and make pod state
    explicit in runtime status.

    [ ] 3.3.1 Task - Add repo-level pod ensure functions
      Start repository singleton pods from the repository runtime container
      instead of through AgentOS kernel setup.

      [ ] 3.3.1.1 Subtask - Add `ensure_repo_pod/1` using a key such as `{managed_repo_id, :repo}`.
      [ ] 3.3.1.2 Subtask - Add `ensure_source_code_graph_pod/1` using a repository-scoped key.
      [ ] 3.3.1.3 Subtask - Add `ensure_memory_graph_pod/1` using a repository-scoped key.
      [ ] 3.3.1.4 Subtask - Store pod pids, keys, status, and diagnostics in runtime state.

    [ ] 3.3.2 Task - Add work-level pod ensure functions
      Start work-item pods from runtime admission state and keep their lifecycle
      isolated by work item.

      [ ] 3.3.2.1 Subtask - Add `ensure_coding_pod/3` using a key such as `{managed_repo_id, work_item_id, :coding}` or `{managed_repo_id, work_item_id}`.
      [ ] 3.3.2.2 Subtask - Add `ensure_context_management_pod/3` using a key that cannot collide with coding pod keys.
      [ ] 3.3.2.3 Subtask - Monitor work-level pod pids and mark runtime status degraded when unexpected exits occur.
      [ ] 3.3.2.4 Subtask - Ensure `complete_work/2` tears down or releases work-level pods and admission state deterministically.

  [ ] 3.4 Section - Phase 3 Integration Tests
    Prove native Jido pods start, reconcile eager nodes, lazy-start specialists,
    and stay isolated by repository and work-item keys.

    [ ] 3.4.1 Task - Pod lifecycle and isolation scenarios
      Exercise each converted pod through `Jido.Pod` APIs rather than AgentOS
      wrappers.

      [ ] 3.4.1.1 Subtask - Add tests that `RepoPod` starts eager `RepoMonitor` and `WorkRegistry` nodes through `Jido.Pod.get/3`.
      [ ] 3.4.1.2 Subtask - Add tests that `CodingPod` starts eager nodes and lazy-starts specialist nodes with `Jido.Pod.ensure_node/3`.
      [ ] 3.4.1.3 Subtask - Add tests that identical work-item IDs in different ManagedRepos resolve to different pod and node pids.
      [ ] 3.4.1.4 Subtask - Add tests that graph and context pods reconcile without AgentOS signal routes.
      [ ] 3.4.1.5 Subtask - Run focused pod tests replacing `test/jido_code/agent_os/pods_test.exs` with runtime/pod test paths.
