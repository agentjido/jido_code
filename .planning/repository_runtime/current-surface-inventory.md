# Current AgentOS Surface Inventory

This inventory classifies the current `jido_agent_os` integration points before
the repository runtime replacement begins. It is intentionally focused on
runtime replacement ownership, not every unrelated use of the word runtime.

## Search Commands

The inventory was built from these searches:

```sh
rg -l "JidoCode\\.AgentOS|Jido\\.AgentOS|AgentOS|kernel_name|ManagerSupervisor|Naming|ensure_kernel|kernel_status|shutdown_kernel|list_kernels|kernel_count" lib config test mix.exs
rg -n "String\\.to_atom|String\\.to_existing_atom|:\\\"repo_|kernel_name\\(" lib/jido_code config test/jido_code/agent_os test/jido_code/agent_workspace_test.exs
rg -n "use Jido\\.AgentOS\\.Pod|alias Jido\\.AgentOS|alias JidoCode\\.AgentOS|Jido\\.AgentOS\\.Supervisor|AgentOS\\.Manager|kernel_name|ensure_kernel\\(|kernel_status\\(|shutdown_kernel\\(|list_kernels\\(|kernel_count" lib/jido_code lib/jido_code_web test/jido_code/agent_os test/jido_code/agent_workspace_test.exs test/jido_code/agent_os_integration_test.exs
rg --files test | rg "agent_workspace|agent_os|pod|source_code_graph|memory_graph|context_management|conversation"
```

## Production Code Classification

| Surface | Files | Current Responsibility | Runtime Replacement Treatment |
| --- | --- | --- | --- |
| AgentOS public facade | `lib/jido_code/agent_os.ex` | Delegates kernel lifecycle and status to the manager. | Delete after callers move to `JidoCode.Runtime`. |
| AgentOS manager lifecycle | `lib/jido_code/agent_os/manager.ex` | Creates one AgentOS kernel per ManagedRepo, converts repo IDs to atoms, tracks pods, persists kernel snapshots. | Replace with product-owned `JidoCode.Runtime` lifecycle, status, pod tracking, and restore policy. |
| AgentOS manager state | `lib/jido_code/agent_os/manager/kernel_state.ex` | Stores tracked kernel pid, repo ID, pods, timestamps, and status. | Replace with repository runtime state struct using ManagedRepo ID keys and pod keys. |
| AgentOS manager server | `lib/jido_code/agent_os/manager/server.ex` | Owns the ETS table used by `JidoCode.AgentOS.Manager`. | Replace with repository runtime processes and registry. |
| AgentOS dynamic supervisor | `lib/jido_code/agent_os/supervisor.ex` | Starts AgentOS kernel supervisors. | Replace with `JidoCode.Runtime.Supervisor` and repository runtime dynamic supervisor. |
| AgentOS snapshot persistence | `lib/jido_code/agent_os/manager/persistence.ex` | Saves and loads kernel snapshots into the control-plane record store with `agent-os-*` checkpoint IDs. | Replace with small product-owned runtime snapshots in Phase 5. |
| Application supervision | `lib/jido_code/application.ex` | Starts AgentOS manager server and dynamic supervisor. | Replace with repository runtime supervisor and static Jido instance managers. |
| App configuration | `config/dev.exs`, `config/test.exs` | Configures AgentOS kernel supervisor and registry. | Remove AgentOS config after runtime cutover. |
| AgentWorkspace lifecycle | `lib/jido_code/agent_workspace.ex` | Exposes `ensure_kernel/1`, `kernel_status/1`, `shutdown_kernel/1`, `list_kernels/0`, and routes pod startup through AgentOS naming/managers. | Route through `JidoCode.Runtime`; rename kernel vocabulary where product callers can be updated directly. |
| AgentWorkspace pod startup | `lib/jido_code/agent_workspace.ex` | Uses `Jido.AgentOS.ManagerSupervisor`, `Jido.AgentOS.Naming`, `Jido.AgentOS.Persistence`, scoped topology, and manual `AgentServer.start/1`. | Replace with `Jido.Pod.get/3` through static `Jido.Agent.InstanceManager`s. |
| Pod definitions | `lib/jido_code/pods/*.ex` | Use `Jido.AgentOS.Pod`; `Empty` exists only as an AgentOS kernel placeholder. | Convert real pods to `Jido.Pod`; delete `Empty` if no longer needed. |
| Source watcher | `lib/jido_code/agents/repo_monitor/source_watcher.ex` | Persists watcher state by calling AgentOS manager pod status. | Route watcher state through repository runtime or product source-monitor state. |
| Source graph refresh scheduler | `lib/jido_code/source_code_graph/refresh_scheduler.ex` | Imports AgentOS manager for repository-scoped runtime lookup. | Route through repository runtime status or source graph pod APIs. |
| Agent docs/comments | `lib/jido_code/agents/budget_monitor.ex`, `lib/jido_code/agents/context_compactor.ex` | Mention AgentOS topology slots. | Rewrite to repository runtime or Jido pod language during pod conversion. |

## Pod Topology Surfaces

Current pod modules:

- `JidoCode.Pods.RepoPod`
- `JidoCode.Pods.CodingPod`
- `JidoCode.Pods.SourceCodeGraphPod`
- `JidoCode.Pods.MemoryGraphPod`
- `JidoCode.Pods.ContextManagementPod`
- `JidoCode.Pods.Empty`

Replacement treatment:

- `RepoPod` becomes a repository-scoped `Jido.Pod` keyed by
  `{managed_repo_id, :repo}`.
- `SourceCodeGraphPod` becomes a repository-scoped `Jido.Pod` keyed by
  `{managed_repo_id, :source_code_graph}`.
- `MemoryGraphPod` becomes a repository-scoped `Jido.Pod` keyed by
  `{managed_repo_id, :memory_graph}`.
- `CodingPod` becomes a work-scoped `Jido.Pod` keyed by
  `{managed_repo_id, work_item_id, :coding}`.
- `ContextManagementPod` becomes a work-scoped `Jido.Pod` keyed by
  `{managed_repo_id, work_item_id, :context_management}`.
- `Empty` is a deletion candidate because it only provides an AgentOS kernel
  placeholder.

## Test Surface Classification

| Test Surface | Files | Replacement Treatment |
| --- | --- | --- |
| Direct AgentOS manager tests | `test/jido_code/agent_os/manager_test.exs`, `test/jido_code/agent_os/manager/persistence_test.exs` | Rewrite as runtime lifecycle, status, identity, and snapshot tests; delete atom naming expectations. |
| Direct AgentOS integration tests | `test/jido_code/agent_os_integration_test.exs`, `test/jido_code/agent_os/phase_twenty*_integration_test.exs` | Split into repository runtime lifecycle tests, native Jido pod tests, and product workflow tests. |
| Pod macro tests | `test/jido_code/agent_os/pods_test.exs`, `test/jido_code/agent_os/ai_agents_test.exs`, `test/jido_code/agent_os/actions_test.exs`, `test/jido_code/agent_os/source_code_graph_agent_adoption_test.exs` | Rewrite around `Jido.Pod.get/3`, `Jido.Pod.ensure_node/3`, eager/lazy node behavior, and product actions. |
| AgentWorkspace tests | `test/jido_code/agent_workspace_test.exs` | Preserve product behavior; update lifecycle expectations from kernel atoms to runtime status reports. |
| Graph and memory workflow tests | `test/jido_code/source_code_graph*_test.exs`, `test/jido_code/memory_graph*_test.exs`, phase 20-38 tests | Preserve product behavior; route setup/cleanup through repository runtime. |
| Context and conversation tests | `test/jido_code/context_management_test.exs`, conversation tests, phase 39+ tests | Preserve conversation snapshots that already avoid `kernel_name`; update cleanup helpers that call `shutdown_kernel/1`. |
| LiveView cleanup tests | `test/jido_code_web/live/run_detail_live_test.exs`, `test/jido_code_web/live/workbench_live_test.exs` | Update cleanup helpers to runtime shutdown APIs. |

## Public Surface Exposure

AgentOS vocabulary is visible mostly through product APIs and tests rather than
user-facing UI text.

- `AgentWorkspace.ensure_kernel/1`, `kernel_status/1`, `shutdown_kernel/1`,
  `list_kernels/0`, and `kernel_count/0` are public Elixir API surfaces that
  should move to repository runtime vocabulary.
- Conversation snapshot tests already assert `kernel_name` is absent; preserve
  that behavior.
- LiveView tests call `AgentWorkspace.shutdown_kernel/1` for cleanup; these
  should become repository runtime cleanup calls.
- No direct LiveVue or browser UI file currently exposes AgentOS kernel naming
  as product text in the runtime replacement search set.

## Runtime Identity Risks

The primary runtime identity risk is current AgentOS atom generation:

- `JidoCode.AgentOS.Manager.kernel_name/1` converts ManagedRepo IDs with
  `String.to_atom/1`.
- `AgentWorkspace.pod_name/1` converts WorkItem IDs with `String.to_atom/1`.
- AgentOS persistence stores `kernel_name` strings in checkpoint metadata.
- Tests assert kernel atoms and generated kernel names.

Other `String.to_existing_atom/1` and `String.to_atom/1` uses exist outside the
AgentOS boundary. They are not part of this runtime replacement unless they are
used for repository runtime identity, but they should remain visible during
review.

## Replacement Owner Summary

- Lifecycle, status, registry, admission, capacity, pod bookkeeping, and
  degraded diagnostics move to `JidoCode.Runtime`.
- Pod topology, eager reconciliation, lazy specialist startup, and node lookup
  move to native `Jido.Pod` and static `Jido.Agent.InstanceManager`s.
- Runtime restoration moves to product-owned runtime snapshots that avoid pids,
  atomized repo IDs, AgentOS kernel names, and process-private node ids.
- Product workflows continue through `AgentWorkspace` during cutover, then shed
  kernel vocabulary once all call sites are updated.
