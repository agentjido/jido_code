# Phase 1 - Runtime Contract and Current Surface Inventory

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_os.ex`
- `lib/jido_code/agent_os/`
- `lib/jido_code/pods/`
- `lib/jido_code/application.ex`
- `lib/jido_code/agents/repo_monitor/source_watcher.ex`
- `lib/jido_code/source_code_graph/refresh_scheduler.ex`
- `deps/jido/lib/jido/pod.ex`
- `deps/jido/lib/jido/pod/runtime.ex`
- `deps/jido/lib/jido/agent/instance_manager.ex`
- `mix.exs`
- `config/dev.exs`
- `config/test.exs`
- `test/jido_code/agent_workspace_test.exs`
- `test/jido_code/agent_os*_test.exs`
- `test/jido_code/agent_os/`

## Relevant Assumptions / Defaults

- No production runtime behavior should change until the existing AgentOS
  surfaces and product expectations are inventoried.
- The new runtime is product-owned and repository-scoped, while `Jido.Pod`
  remains the agent-group topology primitive.
- The implementation should avoid user-derived atoms from the first phase of
  design.
- Existing AgentOS-shaped names such as kernel, kernel supervisor, and pod
  persistence are migration targets, not compatibility requirements.

[ ] 1 Phase 1 - Runtime Contract and Current Surface Inventory
  Establish the target runtime contract and migration map before introducing
  new runtime modules, so implementation work removes AgentOS complexity
  intentionally instead of recreating it locally.

  [x] 1.1 Section - Target Runtime Contract
    Define the product-owned boundary and vocabulary that will replace kernels,
    kernel managers, AgentOS naming, and AgentOS persistence.

    [x] 1.1.1 Task - Define repository runtime vocabulary
      Freeze the terms used in code, tests, status output, and documentation so
      later phases do not mix AgentOS kernel terms with the new runtime model.

      [x] 1.1.1.1 Subtask - Define repository runtime as one supervised product-owned runtime container per ManagedRepo.
      [x] 1.1.1.2 Subtask - Define runtime container identity as the ManagedRepo ID plus explicit product metadata, not a generated atom.
      [x] 1.1.1.3 Subtask - Define runtime status fields for repository ID, workspace path, lifecycle state, active pods, active work items, capacity, and diagnostics.
      [x] 1.1.1.4 Subtask - Mark kernel, kernel_name, and AgentOS naming as deprecated implementation vocabulary to remove during the migration.

    [x] 1.1.2 Task - Confirm the Jido.Pod boundary
      Decide exactly where `Jido.Pod` fits so the implementation uses the
      upstream Jido primitive without forcing repository policy into pod
      topology.

      [x] 1.1.2.1 Subtask - Confirm `Jido.Pod.get/3` is the lifecycle entrypoint for bounded pod instances.
      [x] 1.1.2.2 Subtask - Confirm `Jido.Pod.ensure_node/3`, `lookup_node/2`, `nodes/1`, and `reconcile/2` cover eager and lazy node management needs.
      [x] 1.1.2.3 Subtask - Confirm pod node keys derive from pod module, pod key, and node name, allowing tuple pod keys such as `{managed_repo_id, work_item_id}`.
      [x] 1.1.2.4 Subtask - Decide that dynamic work-item pod ownership stays in the repository runtime process rather than being encoded as mutable nested pod topology.

    [x] 1.1.3 Task - Define runtime identity and key rules
      Prevent the new runtime from inheriting AgentOS atom-naming complexity or
      creating new atom exhaustion risks.

      [x] 1.1.3.1 Subtask - Define repository runtime registry keys as ManagedRepo IDs or validated tuple keys.
      [x] 1.1.3.2 Subtask - Define pod keys for repo, source graph, memory graph, coding, and context-management pods.
      [x] 1.1.3.3 Subtask - Define static manager names as application-owned atoms only.
      [x] 1.1.3.4 Subtask - Add a search target for any use of `String.to_atom/1`, `String.to_existing_atom/1`, dynamic `:"..."`, or kernel-name conversion around runtime identity.

  [x] 1.2 Section - Current AgentOS Surface Inventory
    Inventory every module, configuration value, test, and product workflow
    that currently depends on AgentOS terms or runtime behavior.

    [x] 1.2.1 Task - Inventory production code references
      Find each production dependency on `JidoCode.AgentOS`, `Jido.AgentOS`,
      AgentOS pod macros, kernel status, persistence, and manager supervision.

      [x] 1.2.1.1 Subtask - Search `lib`, `config`, and `mix.exs` for `AgentOS`, `kernel`, `kernel_name`, `ManagerSupervisor`, `Naming`, and `Persistence`.
      [x] 1.2.1.2 Subtask - Classify each reference as lifecycle, status, persistence, pod topology, specialist routing, graph runtime, memory runtime, context runtime, or docs-only.
      [x] 1.2.1.3 Subtask - Record which references will be deleted, renamed, or routed through `JidoCode.Runtime`.
      [x] 1.2.1.4 Subtask - Identify any public UI, LiveView, LiveVue, API, or conversation payload that exposes AgentOS vocabulary.

    [x] 1.2.2 Task - Inventory test and fixture assumptions
      Identify the tests that prove current behavior so the new runtime can
      preserve product semantics while deleting kernel-shaped details.

      [x] 1.2.2.1 Subtask - List focused tests under `test/jido_code/agent_os/` and decide which become runtime tests, pod tests, or deletion candidates.
      [x] 1.2.2.2 Subtask - List `AgentWorkspace` tests that should keep product behavior but update expected runtime status shapes.
      [x] 1.2.2.3 Subtask - List source-code graph, memory graph, context-management, and conversation tests that cross the runtime boundary.
      [x] 1.2.2.4 Subtask - Identify brittle assertions that inspect AgentOS internals instead of product-visible behavior.

  [x] 1.3 Section - Migration Boundary Map
    Translate the inventory into an implementation sequence that can land in
    coherent phases with explicit deletion points.

    [x] 1.3.1 Task - Map old modules to new modules
      Decide the new namespace and ownership for each AgentOS-related
      responsibility before writing code.

      [x] 1.3.1.1 Subtask - Map `JidoCode.AgentOS.Manager` lifecycle functions to `JidoCode.Runtime`.
      [x] 1.3.1.2 Subtask - Map `JidoCode.AgentOS.Manager.Server` tracked state to repository runtime process state.
      [x] 1.3.1.3 Subtask - Map `JidoCode.AgentOS.Manager.Supervisor` to repository runtime supervision and static instance managers.
      [x] 1.3.1.4 Subtask - Map AgentOS persistence snapshots to product-owned runtime restoration data.

    [x] 1.3.2 Task - Define compatibility removal policy
      Make the greenfield deletion rule explicit so implementation does not
      keep both AgentOS and runtime APIs alive unnecessarily.

      [x] 1.3.2.1 Subtask - Decide whether `AgentWorkspace.ensure_kernel/1` is renamed, deleted, or kept temporarily only as an internal migration point.
      [x] 1.3.2.2 Subtask - Decide whether tests should use repository runtime vocabulary immediately after cutover.
      [x] 1.3.2.3 Subtask - Decide which documentation and planning references should be updated or superseded.
      [x] 1.3.2.4 Subtask - Record the exact phase where `jido_agent_os` leaves `mix.exs`.

  [ ] 1.4 Section - Phase 1 Integration Tests
    Prove the migration target is understood and every current AgentOS runtime
    surface has an owner in the new plan before code changes begin.

    [ ] 1.4.1 Task - Inventory verification
      Validate the inventory and target contract against the current codebase
      and test suite boundaries.

      [ ] 1.4.1.1 Subtask - Run `rg -n "AgentOS|Jido.AgentOS|JidoCode.AgentOS|kernel_name|ManagerSupervisor|Naming|Persistence" lib config test mix.exs`.
      [ ] 1.4.1.2 Subtask - Run `rg --files test | rg "agent_workspace|agent_os|pod|source_code_graph|memory_graph|context_management"`.
      [ ] 1.4.1.3 Subtask - Confirm every AgentOS reference is classified as delete, rename, route-through-runtime, or docs-only.
      [ ] 1.4.1.4 Subtask - Confirm every later phase ends with an integration-test section.
