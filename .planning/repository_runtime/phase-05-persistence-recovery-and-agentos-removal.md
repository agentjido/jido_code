# Phase 5 - Persistence, Recovery, and AgentOS Removal

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces

- `lib/jido_code/agent_os/manager/persistence.ex`
- `lib/jido_code/agent_os/manager/kernel_state.ex`
- `lib/jido_code/agent_os/manager.ex`
- `lib/jido_code/application.ex`
- `lib/jido_code/runtime/`
- `mix.exs`
- `mix.lock`
- `config/dev.exs`
- `config/test.exs`
- `test/jido_code/agent_os/manager/persistence_test.exs`
- `test/jido_code/agent_os/phase_twenty*_integration_test.exs`
- `test/jido_code/phase_thirty*_integration_test.exs`

## Relevant Assumptions / Defaults

- Runtime restoration is product metadata restoration, not AgentOS kernel
  restoration.
- Persistent product truth remains in the control plane, source graph, memory
  graph, conversations, and governed records.
- Runtime snapshots should contain only enough state to resume or explain
  runtime topology.
- Removing `jido_agent_os` is part of the phase, not a later cleanup.

[x] 5 Phase 5 - Persistence, Recovery, and AgentOS Removal
  Replace AgentOS snapshot and recovery behavior with a product-owned runtime
  restoration path, then delete obsolete AgentOS modules, configuration, tests,
  and dependency entries.

  [x] 5.1 Section - Runtime Snapshot Contract
    Define the small durable record that lets repository runtimes restore
    explainable state without treating process identity as product truth.

    [x] 5.1.1 Task - Define snapshot contents
      Capture only the runtime metadata needed to restart pods, explain active
      work, and reconnect product workflows.

      [x] 5.1.1.1 Subtask - Include ManagedRepo ID, workspace path, lifecycle state, active work-item IDs, pod keys, and last diagnostics.
      [x] 5.1.1.2 Subtask - Exclude pids, AgentOS kernel names, registry process names, and runtime-private node ids.
      [x] 5.1.1.3 Subtask - Include graph freshness summaries by reference to product graph state rather than duplicating graph data.
      [x] 5.1.1.4 Subtask - Include memory and context-management summaries only when they are needed for runtime restoration.

    [x] 5.1.2 Task - Choose snapshot storage owner
      Decide where runtime metadata lives so restart behavior is durable but
      does not become a second product database.

      [x] 5.1.2.1 Subtask - Evaluate using existing control-plane storage for repository runtime metadata.
      [x] 5.1.2.2 Subtask - Evaluate an ETS-only path for test runtime state and failure injection.
      [x] 5.1.2.3 Subtask - Define clear behavior when snapshot storage is unavailable.
      [x] 5.1.2.4 Subtask - Keep storage writes bounded and avoid persisting large graph, conversation, or prompt payloads.

  [x] 5.2 Section - Startup Recovery and Orphan Handling
    Restore repository runtime state after application restart and handle stale
    pod or work metadata deterministically.

    [x] 5.2.1 Task - Add runtime restoration flow
      Start repository runtimes from durable product metadata when a caller
      asks for an existing repository or when configured startup restoration is
      enabled.

      [x] 5.2.1.1 Subtask - Add a restore function that reconstructs repository runtime state from snapshots.
      [x] 5.2.1.2 Subtask - Reconcile repo, graph, memory, coding, and context pods with `Jido.Pod.get/3` as needed.
      [x] 5.2.1.3 Subtask - Mark missing, stale, or failed pods as degraded diagnostics rather than hiding failures.
      [x] 5.2.1.4 Subtask - Ensure restoration is idempotent when multiple callers request the same ManagedRepo concurrently.

    [x] 5.2.2 Task - Add stale work and orphan cleanup
      Make restart behavior explicit when snapshots mention work that no
      longer has a valid product record or workspace.

      [x] 5.2.2.1 Subtask - Detect active work items that no longer exist or no longer belong to the ManagedRepo.
      [x] 5.2.2.2 Subtask - Detect work items whose workspace path is missing or no longer matches repository binding.
      [x] 5.2.2.3 Subtask - Mark unrecoverable runtime entries as stale and release capacity.
      [x] 5.2.2.4 Subtask - Emit bounded diagnostics for operator surfaces and tests.

  [x] 5.3 Section - AgentOS Deletion
    Remove the dependency and obsolete local integration after product
    workflows have been routed through `JidoCode.Runtime`.

    [x] 5.3.1 Task - Delete local AgentOS modules and config
      Remove modules that only existed to adapt AgentOS kernels to the product
      runtime model.

      [x] 5.3.1.1 Subtask - Delete `lib/jido_code/agent_os.ex` after callers move to runtime APIs.
      [x] 5.3.1.2 Subtask - Delete `lib/jido_code/agent_os/` manager, server, supervisor, kernel state, and persistence modules.
      [x] 5.3.1.3 Subtask - Remove AgentOS supervisor and registry config from `config/dev.exs` and `config/test.exs`.
      [x] 5.3.1.4 Subtask - Remove AgentOS supervision children from `JidoCode.Application`.

    [x] 5.3.2 Task - Remove external AgentOS dependency
      Delete the upstream dependency once no production or test code references
      it.

      [x] 5.3.2.1 Subtask - Remove `{:jido_agent_os, ...}` from `mix.exs`.
      [x] 5.3.2.2 Subtask - Run `mix deps.get` to update `mix.lock`.
      [x] 5.3.2.3 Subtask - Run `rg -n "jido_agent_os|Jido.AgentOS|JidoCode.AgentOS|AgentOS" lib config test mix.exs mix.lock`.
      [x] 5.3.2.4 Subtask - Delete or rewrite AgentOS-specific tests under `test/jido_code/agent_os/`.

  [x] 5.4 Section - Phase 5 Integration Tests
    Prove runtime restoration works from product-owned metadata and the codebase
    no longer depends on AgentOS.

    [x] 5.4.1 Task - Recovery and dependency-removal scenarios
      Exercise restart, stale metadata, and dependency deletion cases in the
      focused runtime suite.

      [x] 5.4.1.1 Subtask - Add tests that runtime snapshots restore repo-level pods and active work metadata after runtime shutdown.
      [x] 5.4.1.2 Subtask - Add tests that stale work metadata fails closed and releases capacity.
      [x] 5.4.1.3 Subtask - Add tests that restoration does not expose pids or runtime-private node ids as product truth.
      [x] 5.4.1.4 Subtask - Run `mix deps.get --check-locked` after dependency removal.
      [x] 5.4.1.5 Subtask - Run `mix test` for runtime, workspace, graph, memory, context, and conversation suites affected by the deletion.
