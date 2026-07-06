# Repository Runtime Contract

This document records the target runtime boundary for replacing
`jido_agent_os`. It is the implementation contract for the phased work in this
planning track.

## Vocabulary

- Repository runtime:
  One supervised, product-owned runtime container for a single ManagedRepo.
  It owns repository-scoped runtime policy and starts pods on demand.
- Runtime container identity:
  The ManagedRepo ID plus explicit product metadata such as workspace path,
  lifecycle state, active pod keys, active work items, capacity, and
  diagnostics. It is not an atom generated from user or database input.
- Runtime status:
  A product-facing map or struct that reports repository ID, workspace path,
  lifecycle state, active pods, active work items, capacity policy, and
  degraded diagnostics. It may include developer diagnostics behind explicit
  debug surfaces, but ordinary product status must not expose runtime-private
  pids as product truth.
- Repository pod:
  A `Jido.Pod` instance that groups repository monitoring and work registry
  agents for one ManagedRepo.
- Work pod:
  A `Jido.Pod` instance that groups work-item-scoped agents, such as coding and
  context-management agents, for one ManagedRepo and one WorkItem.

The following terms are migration-only vocabulary and should not appear in the
new runtime API after cutover:

- Kernel
- `kernel_name`
- AgentOS naming
- AgentOS manager
- AgentOS persistence snapshot

## Boundary Ownership

`JidoCode.Runtime` owns repository-scoped product policy:

- one runtime container per ManagedRepo
- runtime lookup and lifecycle
- workspace binding
- work-item admission and capacity
- runtime status and degraded diagnostics
- active pod and active work-item bookkeeping
- restore and cleanup policy

`Jido.Pod` owns bounded agent-group topology:

- pod module topology
- eager node reconciliation
- lazy node startup
- node lookup
- node runtime snapshots

The repository runtime may use `Jido.Pod` for repo, graph, memory, coding, and
context-management pods, but the repository runtime itself is not merely a pod.
Dynamic work-item ownership remains in the product runtime process rather than
being encoded as mutable nested pod topology.

## Jido.Pod API Contract

The replacement runtime uses native Jido primitives directly:

- `Jido.Pod.get/3` starts or returns a keyed pod instance through a static
  `Jido.Agent.InstanceManager` and reconciles eager nodes.
- `Jido.Pod.reconcile/2` starts all eager topology nodes.
- `Jido.Pod.ensure_node/3` starts one eager or lazy node and returns its pid.
- `Jido.Pod.lookup_node/2` returns a live node when it already exists.
- `Jido.Pod.nodes/1` returns runtime snapshots for topology nodes.

`Jido.Pod` node identity is derived from the pod module, the pod key, and the
node name. That means tuple keys such as `{managed_repo_id, work_item_id}` are
valid for product identity without generating atoms from user input.

## Identity Rules

Runtime identity must use product data and structured keys:

- Repository runtime registry key: `managed_repo_id`.
- Repo pod key: `{managed_repo_id, :repo}`.
- Source-code graph pod key: `{managed_repo_id, :source_code_graph}`.
- Memory graph pod key: `{managed_repo_id, :memory_graph}`.
- Coding pod key: `{managed_repo_id, work_item_id, :coding}`.
- Context-management pod key:
  `{managed_repo_id, work_item_id, :context_management}`.

Static manager names are allowed only when they are application-owned atoms
defined in source code, for example `:jido_code_coding_pods` or
`:jido_code_planners`.

The runtime replacement must not use:

- `String.to_atom/1` on runtime identifiers
- `String.to_existing_atom/1` on runtime identifiers
- generated atoms such as `:"repo_#{managed_repo_id}"`
- AgentOS kernel naming helpers

## Status Fields

Repository runtime status should include:

- `:managed_repo_id`
- `:workspace_path`
- `:lifecycle`
- `:active_pods`
- `:active_work_items`
- `:capacity`
- `:diagnostics`
- `:started_at`
- `:last_activity_at`
- `:last_failure_at`

Pod status entries should include:

- `:kind`
- `:key`
- `:module`
- `:lifecycle`
- `:nodes`
- `:diagnostics`

Work-item status entries should include:

- `:work_item_id`
- `:workspace_path`
- `:admitted_at`
- `:coding_pod`
- `:context_management_pod`
- `:lifecycle`
- `:diagnostics`

## Search Targets

Runtime implementation and review should search for these patterns when
checking identity safety:

```sh
rg -n "String\\.to_atom|String\\.to_existing_atom|kernel_name|AgentOS\\.Naming|:\"repo_|ManagerSupervisor|Jido\\.AgentOS|JidoCode\\.AgentOS" lib config test mix.exs
```
