# Repository Runtime Plan Index

This directory contains the phased implementation plan that replaced the
`jido_agent_os` integration with a product-owned `JidoCode.Runtime`
container. The design keeps one runtime container per ManagedRepo, uses
`Jido.Pod` for bounded agent-group topology, and keeps repository policy inside
`jido_code` instead of copying AgentOS.

Current status: Phase 5 removed `jido_agent_os`; Phase 6 is hardening the
repository runtime as the canonical boundary.

The plan aligns to:
- `lib/jido_code/agent_workspace.ex`
- `lib/jido_code/runtime/`
- `lib/jido_code/pods/`
- `lib/jido_code/application.ex`
- `deps/jido/lib/jido/pod.ex`
- `deps/jido/lib/jido/pod/runtime.ex`
- `deps/jido/lib/jido/agent/instance_manager.ex`
- `.planning/phase-19-agent-os-integration.md`
- `.planning/phase-20-source-code-graph-pod-foundation.md`
- `.planning/phase-28-memory-graph-pod-and-store-foundation.md`
- `.planning/phase-89-context-management-pod-foundation.md`

## Repository Runtime Phases

1. [Phase 1 - Runtime Contract and Current Surface Inventory](./phase-01-runtime-contract-and-current-surface-inventory.md): define the new product-owned runtime contract, confirm the role of `Jido.Pod`, and inventory every AgentOS dependency before implementation.
2. [Phase 2 - Repository Runtime Container Foundation](./phase-02-repository-runtime-container-foundation.md): add the supervised runtime container, repository registry, lifecycle API, and tuple-keyed identity model.
3. [Phase 3 - Jido.Pod Manager Topology and Pod Conversion](./phase-03-jido-pod-manager-topology-and-pod-conversion.md): define static `Jido.Agent.InstanceManager` children and convert local pods from `Jido.AgentOS.Pod` to `Jido.Pod`.
4. [Phase 4 - Product Entrypoint Cutover](./phase-04-product-entrypoint-cutover.md): route `AgentWorkspace`, source monitor, refresh scheduler, graph workflows, memory workflows, and context management through the new runtime.
5. [Phase 5 - Persistence, Recovery, and AgentOS Removal](./phase-05-persistence-recovery-and-agentos-removal.md): replace AgentOS snapshot behavior with product-owned runtime state, recover active repository runtimes, and remove the dependency and obsolete modules.
6. [Phase 6 - Operational Hardening and Acceptance](./phase-06-operational-hardening-and-acceptance.md): finalize capacity limits, observability, failure handling, documentation, and end-to-end acceptance for the new runtime model.

## Current Notes

- [Migration Notes](./migration-notes.md): current contributor guidance for why `Jido.Pod` remains the pod boundary while `JidoCode.Runtime` owns repository policy, admission, health, telemetry, and restoration.
- [Runtime Contract](./runtime-contract.md): product-owned runtime contract and forbidden AgentOS/kernel behaviors.
- [Migration Boundary Map](./migration-boundary-map.md): historical mapping from AgentOS APIs to repository runtime APIs.

## Verification

- Use `mix runtime.verify` for changes to repository runtime lifecycle, pod ownership, snapshots, and `AgentWorkspace` runtime routing.
- Use `mix source_graph.verify` when source-code graph runtime behavior, actions, pod agents, helper queries, or workspace entrypoints change.
- Use `mix memory.verify` when memory graph boundaries, capture envelopes, memory writers, provenance capture, or durable-memory adoption change.
- Use `mix semantic.verify` when product-facing semantic services, semantic surfaces, or governed semantic workflows change.
- Use `mix frontend.verify` when LiveView, LiveVue, Vite, SSR entrypoints, or shared browser helpers change.

## Shared Conventions

- Numbering:
  - Phases: `N`
  - Sections: `N.M`
  - Tasks: `N.M.K`
  - Subtasks: `N.M.K.L`
- Tracking:
  - Every phase, section, task, and subtask uses Markdown checkboxes (`[ ]`).
- Description requirement:
  - Every phase, section, and task starts with a short description paragraph.
- Integration-test requirement:
  - Each phase ends with a final integration-testing section.

## Shared Assumptions and Defaults

- This is a greenfield runtime replacement; no backward-compatibility shim is
  required for `JidoCode.AgentOS` or kernel-shaped return values.
- There is still exactly one repository runtime container per ManagedRepo.
- `Jido.Pod` is the boundary for bounded agent groups, not the complete
  top-level repository runtime policy engine.
- The repository runtime owns product concerns: admission, capacity limits,
  workspace binding, graph freshness, work-item lifecycle, restore policy, and
  shutdown behavior.
- Pod and node identity must use tuple or string keys, never atoms derived from
  ManagedRepo IDs or WorkItem IDs.
- Static `Jido.Agent.InstanceManager` names are acceptable because they are
  application-owned atoms defined at compile time.
- Source-code graph, memory graph, conversation, and context-management
  behavior should remain product-owned and should degrade legibly when runtime
  pods are missing, stale, or failed.
- The implementation removes `jido_agent_os` from `mix.exs` and `mix.lock`.
