# Phase 2 - Repository Runtime Container Foundation

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/application.ex`
- `lib/jido_code/jido.ex`
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/agent_os/manager.ex`
- `lib/jido_code/agent_os/manager/server.ex`
- `lib/jido_code/agent_os/supervisor.ex`
- `deps/jido/lib/jido/agent/instance_manager.ex`
- `test/jido_code/agent_os/manager_test.exs`
- `test/jido_code/agent_workspace_test.exs`

## Relevant Assumptions / Defaults

- `JidoCode.Jido` remains the global Jido instance.
- Repository runtime processes are product-owned OTP processes, not AgentOS
  kernels.
- The runtime container can start without all pods being present; pods are
  ensured on demand through later phases.
- Runtime APIs should return structured reports rather than atomized kernel
  names.

[ ] 2 Phase 2 - Repository Runtime Container Foundation
  Add the supervised repository runtime container and lifecycle API that will
  replace AgentOS kernel management while preserving one active runtime
  boundary per ManagedRepo.

  [ ] 2.1 Section - Supervision and Registry Foundation
    Introduce the OTP structure that owns repository runtime processes and
    makes lookup explicit by ManagedRepo ID.

    [ ] 2.1.1 Task - Add repository runtime supervision modules
      Create the minimal supervision tree required to start, find, and stop one
      runtime process per repository.

      [ ] 2.1.1.1 Subtask - Add `JidoCode.Runtime.Supervisor` as the public child in `JidoCode.Application`.
      [ ] 2.1.1.2 Subtask - Add `JidoCode.Runtime.Registry` with unique keys for ManagedRepo IDs.
      [ ] 2.1.1.3 Subtask - Add `JidoCode.Runtime.RepositorySupervisor` or equivalent dynamic supervisor for repository runtime children.
      [ ] 2.1.1.4 Subtask - Ensure supervision child specs use stable module IDs and do not depend on repository-derived atoms.

    [ ] 2.1.2 Task - Add repository runtime process
      Implement the product-owned process that holds repository-scoped runtime
      state and owns the dynamic work-item pod map.

      [ ] 2.1.2.1 Subtask - Add `JidoCode.Runtime.RepositoryRuntime` as a GenServer or equivalent OTP process.
      [ ] 2.1.2.2 Subtask - Register each process by `managed_repo_id`.
      [ ] 2.1.2.3 Subtask - Store runtime state for repository ID, workspace path, lifecycle status, active pods, active work items, capacity policy, and diagnostics.
      [ ] 2.1.2.4 Subtask - Monitor owned pod pids once Phase 3 starts creating pods.

  [ ] 2.2 Section - Runtime Lifecycle API
    Define the public runtime functions that product callers use instead of
    kernel lifecycle functions.

    [ ] 2.2.1 Task - Add ensure and lookup APIs
      Provide idempotent runtime creation and lookup without exposing OTP
      registry details to product callers.

      [ ] 2.2.1.1 Subtask - Add `JidoCode.Runtime.ensure_repository/2` or equivalent with `managed_repo_id` and workspace path inputs.
      [ ] 2.2.1.2 Subtask - Add `JidoCode.Runtime.fetch_repository/1` for structured lookup.
      [ ] 2.2.1.3 Subtask - Add `JidoCode.Runtime.repository_status/1` for product-facing status.
      [ ] 2.2.1.4 Subtask - Add `JidoCode.Runtime.list_repositories/0` and `repository_count/0`.

    [ ] 2.2.2 Task - Add shutdown and lifecycle transitions
      Make runtime shutdown deterministic for tests, operator actions, and
      repository removal flows.

      [ ] 2.2.2.1 Subtask - Add `JidoCode.Runtime.shutdown_repository/1` as an idempotent API.
      [ ] 2.2.2.2 Subtask - Define lifecycle states such as `:starting`, `:ready`, `:degraded`, `:stopping`, and `:stopped`.
      [ ] 2.2.2.3 Subtask - Ensure failed startup unregisters the runtime and returns a structured error.
      [ ] 2.2.2.4 Subtask - Ensure repeated ensure and shutdown calls are race-safe.

  [ ] 2.3 Section - Runtime State and Admission Policy
    Move repository-scoped product policy out of AgentOS manager state and into
    the new runtime boundary.

    [ ] 2.3.1 Task - Model runtime state explicitly
      Define a small state structure that can be inspected, tested, persisted,
      and evolved without exposing process internals.

      [ ] 2.3.1.1 Subtask - Add a runtime state struct or typed map owned by `JidoCode.Runtime`.
      [ ] 2.3.1.2 Subtask - Include workspace binding and workspace validation diagnostics.
      [ ] 2.3.1.3 Subtask - Include active work-item IDs and pod keys, not AgentOS pod IDs.
      [ ] 2.3.1.4 Subtask - Include status timestamps for startup, last activity, last failure, and shutdown.

    [ ] 2.3.2 Task - Add admission and capacity checks
      Keep work-item admission product-owned so runtime capacity can fail
      closed before pod creation.

      [ ] 2.3.2.1 Subtask - Move current work queue capacity rules behind the repository runtime API.
      [ ] 2.3.2.2 Subtask - Return structured `:capacity_exceeded`, `:workspace_unavailable`, and `:runtime_unavailable` errors.
      [ ] 2.3.2.3 Subtask - Track admitted work items separately from successfully started coding pods.
      [ ] 2.3.2.4 Subtask - Release admission state when work completes or startup fails.

  [ ] 2.4 Section - Phase 2 Integration Tests
    Prove the repository runtime container can be created, found, reported, and
    shut down independently of AgentOS and before pod conversion begins.

    [ ] 2.4.1 Task - Repository lifecycle scenarios
      Exercise the new runtime lifecycle under normal, repeated, and failing
      conditions.

      [ ] 2.4.1.1 Subtask - Add tests that `ensure_repository/2` starts one runtime per ManagedRepo and returns the same runtime on repeated calls.
      [ ] 2.4.1.2 Subtask - Add tests that two ManagedRepos get isolated runtime state and do not share active work items.
      [ ] 2.4.1.3 Subtask - Add tests that `shutdown_repository/1` is idempotent and removes registry entries.
      [ ] 2.4.1.4 Subtask - Add tests that invalid workspace input fails closed without leaking runtime processes.
      [ ] 2.4.1.5 Subtask - Run `mix test test/jido_code/agent_workspace_test.exs` after adapting lifecycle expectations.
