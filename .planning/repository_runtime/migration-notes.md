# Repository Runtime Migration Notes

Back to index: [README](./README.md)

## Current Runtime Boundary

`JidoCode.Runtime` is the canonical runtime boundary. It owns one supervised
repository runtime container per ManagedRepo and keeps product policy in
`jido_code`: workspace binding, active-work admission, capacity limits, pod
lifecycle, degraded diagnostics, health projection, telemetry, shutdown, and
runtime snapshot restoration.

`Jido.Pod` remains the boundary for bounded agent groups inside that container.
Repo monitoring, source-code graph, memory graph, context management, and
coding specialists run as pods because they benefit from Jido's agent grouping,
node startup, and signal behavior. They do not own repository admission,
restore policy, or product-visible runtime status.

## Why Not Copy AgentOS

The replaced AgentOS integration provided a kernel-per-repository model plus
manager naming, persistence, and topology helpers. The useful shape is the
repository scope, not the AgentOS implementation details. The new runtime keeps
the repository scope while deleting atom-derived kernel names, AgentOS manager
state, AgentOS persistence snapshots, and product callers that depended on
AgentOS vocabulary.

## Contributor Rules

- New runtime lifecycle code should use `JidoCode.Runtime` or repository-runtime
  functions on `JidoCode.AgentWorkspace`.
- New pod work should use native `Jido.Pod` modules and static
  `Jido.Agent.InstanceManager` children.
- New status or snapshot surfaces must not expose pids, registry names,
  generated kernel names, or node maps unless explicitly behind developer
  diagnostics.
- New tests should assert product behavior: runtime health, active work,
  graph readiness, memory readiness, context-management status, diagnostics,
  and snapshot restore behavior.

## Verification

Run `mix runtime.verify` for repository runtime lifecycle, pod ownership,
runtime snapshots, and `AgentWorkspace` runtime routing. Add
`mix source_graph.verify`, `mix memory.verify`, `mix semantic.verify`, or
`mix frontend.verify` when the touched boundary crosses those domains.
