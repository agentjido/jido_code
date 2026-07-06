# Repository Runtime Migration Boundary Map

This map defines the ownership changes that will move the codebase from
`jido_agent_os` to the product-owned repository runtime.

## Old-To-New Module Map

| Current Surface | New Owner | Migration Action |
| --- | --- | --- |
| `JidoCode.AgentOS` | `JidoCode.Runtime` and `JidoCode.AgentWorkspace` | Delete facade after product callers use runtime/workspace APIs. |
| `JidoCode.AgentOS.Manager.ensure_kernel/1` | `JidoCode.Runtime.ensure_repository/2` | Replace kernel startup with repository runtime startup keyed by ManagedRepo ID. |
| `JidoCode.AgentOS.Manager.kernel_status/1` | `JidoCode.Runtime.repository_status/1` | Return product runtime status without `kernel_name`, supervisor pid, or AgentOS internals. |
| `JidoCode.AgentOS.Manager.shutdown_kernel/1` | `JidoCode.Runtime.shutdown_repository/1` | Stop repository runtime and release pod/work state idempotently. |
| `JidoCode.AgentOS.Manager.list_kernels/0` | `JidoCode.Runtime.list_repositories/0` | List active repository runtime IDs or status summaries. |
| `JidoCode.AgentOS.Manager.kernel_count/0` | `JidoCode.Runtime.repository_count/0` | Count active repository runtimes. |
| `JidoCode.AgentOS.Manager.kernel_name/1` | No replacement | Delete; runtime identity must not generate atoms from repo IDs. |
| `JidoCode.AgentOS.Manager.Server` | `JidoCode.Runtime.RepositoryRuntime` processes plus registry | Replace ETS-backed kernel tracking with supervised runtime state. |
| `JidoCode.AgentOS.Manager.Supervisor` | `JidoCode.Runtime.Supervisor` and repository dynamic supervisor | Replace dynamic AgentOS kernel supervisors with product runtime supervision. |
| `JidoCode.AgentOS.Manager.KernelState` | `JidoCode.Runtime.RepositoryState` or equivalent | Replace kernel-shaped state with repository runtime state. |
| `JidoCode.AgentOS.Manager.Persistence` | `JidoCode.Runtime.Snapshot` or equivalent | Replace kernel snapshots with bounded product runtime snapshots. |
| `Jido.AgentOS.ManagerSupervisor` | Static `Jido.Agent.InstanceManager` children | Start pod and node managers once under application supervision. |
| `Jido.AgentOS.Naming` | Structured tuple keys | Use ManagedRepo and WorkItem tuple keys for runtime identity. |
| `Jido.AgentOS.Persistence` | Runtime snapshot storage plus Jido manager storage config when needed | Keep persistence product-owned; do not depend on AgentOS storage resolution. |
| `Jido.AgentOS.Pod` | `Jido.Pod` | Convert local pod modules to native Jido pod definitions. |
| `JidoCode.Pods.Empty` | No replacement | Delete if it remains only an AgentOS kernel placeholder. |

## Product Boundary Map

`AgentWorkspace` remains the high-level product context during the migration.
Its internals should move in this order:

1. Runtime lifecycle calls route to `JidoCode.Runtime`.
2. Repo-level pod ensures route to repository runtime functions.
3. Work-level pod ensures route to repository runtime functions.
4. Specialist lookup uses `Jido.Pod.ensure_node/3` or `Jido.Pod.lookup_node/2`
   through runtime-owned pod pids.
5. Graph, memory, context-management, and conversation workflows keep product
   semantics while their runtime lookup moves from AgentOS to
   `JidoCode.Runtime`.

After all call sites move, kernel-named public functions should be renamed or
deleted instead of kept as compatibility shims.

## Test Migration Map

| Current Test Group | New Test Group |
| --- | --- |
| `test/jido_code/agent_os/manager_test.exs` | `test/jido_code/runtime/repository_runtime_test.exs` |
| `test/jido_code/agent_os/manager/persistence_test.exs` | `test/jido_code/runtime/snapshot_test.exs` |
| `test/jido_code/agent_os/pods_test.exs` | `test/jido_code/runtime/pods_test.exs` |
| `test/jido_code/agent_os/ai_agents_test.exs` | `test/jido_code/runtime/specialists_test.exs` or existing agent tests |
| `test/jido_code/agent_os/actions_test.exs` | Keep as product action tests if actions remain unchanged; remove AgentOS naming. |
| `test/jido_code/agent_os/phase_twenty*_integration_test.exs` | Rewrite into runtime, source graph, memory graph, and product workflow phase tests. |
| `test/jido_code/agent_os_integration_test.exs` | Rewrite into repository runtime integration tests. |
| `test/jido_code/agent_workspace_test.exs` | Keep file; update expectations to runtime vocabulary. |

## Compatibility Removal Policy

This runtime replacement is greenfield. Compatibility shims are allowed only as
short-lived internal migration helpers within the same branch.

- `AgentWorkspace.ensure_kernel/1`:
  Temporarily route through `JidoCode.Runtime.ensure_repository/2` if needed to
  keep intermediate commits testable. It should be renamed or removed before the
  final AgentOS removal commit.
- `AgentWorkspace.kernel_status/1`:
  Replace with runtime status naming before the end of Phase 4.
- `AgentWorkspace.shutdown_kernel/1`:
  Replace test and cleanup callers with repository runtime shutdown before the
  end of Phase 4.
- `JidoCode.AgentOS`:
  Delete in Phase 5 after callers move.
- `jido_agent_os` dependency:
  Remove in Phase 5 after `rg` proves no `Jido.AgentOS` or `JidoCode.AgentOS`
  references remain in production or test code.

Tests should use repository runtime vocabulary as soon as each test group is
converted. New tests should not assert generated kernel atoms.

## Deletion Points

- Phase 3:
  Convert pod modules to `Jido.Pod`; delete `JidoCode.Pods.Empty` if it is only
  a placeholder.
- Phase 4:
  Remove product callers of AgentOS lifecycle APIs and kernel vocabulary.
- Phase 5:
  Delete `lib/jido_code/agent_os.ex`, `lib/jido_code/agent_os/`, AgentOS config,
  and `jido_agent_os` from `mix.exs` and `mix.lock`.
- Phase 6:
  Remove stale planning/spec wording that treats AgentOS as the current runtime
  boundary.

## Documentation Updates

The following should be updated as the implementation crosses each boundary:

- `.planning/repository_runtime/*.md` checkboxes and notes.
- `.planning/phase-19-agent-os-integration.md` status, or a superseding note.
- Module docs for `JidoCode.AgentWorkspace`.
- New module docs for `JidoCode.Runtime`.
- Specs or decisions that require `AgentOS` kernel vocabulary.
