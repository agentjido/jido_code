# 10. Development Workflow And Quality Gates

This guide summarizes how contributors should work in `jido_code` day to day.

Useful implementation sources:

- [`../../README.md`](https://github.com/mikehostetler/jido_code/blob/main/README.md)
- [`../../CONTRIBUTING.md`](https://github.com/mikehostetler/jido_code/blob/main/CONTRIBUTING.md)
- [`../../AGENTS.md`](https://github.com/mikehostetler/jido_code/blob/main/AGENTS.md)

## Normal Local Workflow

The normal contributor path is the repo-root Phoenix workflow backed by the
embedded control-plane `TripleStore`. A local Postgres server is not part of the
current product data plane.

Typical flow:

1. `asdf install`
2. `mix setup`
3. `mix server`
4. `mix test`

Desktop packaging and runtime work are separate and live under
[`../../tauri/README.md`](https://github.com/mikehostetler/jido_code/blob/main/tauri/README.md).

## Read Order For New Work

For non-trivial changes, the repo expects contributors to orient themselves
before editing:

1. read `README.md`
2. read `AGENTS.md`
3. read the relevant code, routes, and tests
4. read the relevant developer guides and planning notes when they apply

## Quality Commands

| Command | Purpose |
| --- | --- |
| `mix test` | run test suite and provision test DB |
| `mix q` | fast quality gate |
| `mix quality` | broader local verification including frontend and semantic checks |
| `mix frontend.verify` | verify LiveVue and Vite browser pipeline |
| `mix source_graph.verify` | verify semantic source-code graph stack |
| `mix memory.verify` | verify memory graph and capture-plane behavior |
| `mix control_plane.integrity` | check embedded control-plane graph topology, ontology version, identities, and dangling links |
| `mix control_plane.query --named health` | inspect bounded control-plane store health without raw SPARQL |
| `mix control_plane.export priv/tmp/control-plane.nq` | export control-plane graphs with auth and security graph redaction enabled by default |
| `mix test test/jido_code/embedded_store_removal_gate_test.exs` | verify Ash/Postgres removal, codec coverage, store boundary, and export redaction guardrails |
| `mix test test/jido_code/conversations/context_memory_test.exs test/jido_code/phase_seventy_eight_integration_test.exs` | verify prompt context memory adapter and runtime integration |
| `mix test test/jido_code/conversations_driver_test.exs test/jido_code/conversations_coordinator_test.exs test/jido_code/conversations_test.exs test/jido_code/conversations_pubsub_test.exs test/jido_code/conversations/context_memory_test.exs --seed 871949 --max-cases 1 --max-failures 1` | verify the historical conversation child-supervisor lifecycle regression |
| `mix test test/jido_code/conversations/context_memory_test.exs test/jido_code/phase_fifty_two_integration_test.exs test/jido_code/phase_eighty_three_integration_test.exs --max-cases 1 --max-failures 1` | verify prompt-memory fixture isolation with deterministic routing and refactor-routing integration |
| `mix test test/jido_code/context_budget_test.exs test/jido_code/phase_eighty_five_integration_test.exs test/jido_code/phase_eighty_six_integration_test.exs test/jido_code/phase_eighty_seven_integration_test.exs --max-cases 1 --max-failures 1` | verify context-budget policy, prompt packing, graph prompt projections, specialist history packing, and tool-output caps |
| `mix test test/jido_code/context_management_test.exs test/jido_code/phase_eighty_nine_integration_test.exs test/jido_code/phase_ninety_integration_test.exs test/jido_code/phase_ninety_one_integration_test.exs --max-cases 1 --max-failures 1` | verify context-management pod topology, monitor decisions, compactor lifecycle, and summary injection |
| `mix test test/jido_code/agent_os/actions_test.exs test/jido_code/agent_workspace/prompt_projection_test.exs --max-failures 1` | verify workspace tool budget diagnostics and graph prompt projection shaping |
| `mix semantic.verify` | verify product-facing semantic behavior |
| `mix docs` | build repo docs surface |

## When To Run Specialty Verification

Run the narrower verification commands when you touch those boundaries:

- browser stack or `live_vue` changes -> `mix frontend.verify`
- embedded control-plane store, codecs, graph topology, product record stores,
  recovery tooling, or persistence guardrails -> `mix control_plane.integrity`
  and `mix test test/jido_code/embedded_store_removal_gate_test.exs`
- source graph boundaries -> `mix source_graph.verify`
- memory graph or capture boundaries -> `mix memory.verify`
- prompt context memory adapter or conversation prompt recall changes -> run the
  focused prompt-memory tests listed above
- conversation coordinator, child-work supervision, or conversation runtime
  startup changes -> run the historical seeded conversation batch listed above
- workflow routing, refactor routing, or prompt-memory fixture changes -> run
  the mixed context-memory plus Phase 52 and Phase 83 routing command listed
  above
- context budget policy, prompt packing, specialist ReAct history, or
  tool-output budget changes -> run the focused context-budget and action test
  commands listed above
- context-management pod, monitor, compactor, summary store, or summary
  injection changes -> run the focused context-management command plus
  `test/jido_code/context_budget_test.exs` and
  `test/jido_code/agent_workspace_test.exs --max-cases 1 --max-failures 1`
- AgentWorkspace semantic or memory prompt projection changes -> run the
  focused context-budget commands plus `mix source_graph.verify` and
  `mix memory.verify`
- product-facing semantic surfaces or services -> `mix semantic.verify`

## Context Budget Verification

Context budget changes can affect more than one prompt boundary. Use
`test/jido_code/context_budget_test.exs` for the policy and packer rules,
Phase 85 for conversation-runtime packing, Phase 86 for AgentWorkspace graph
projection adoption, and Phase 87 for specialist history and tool-output caps.

Run `test/jido_code/agent_os/actions_test.exs` when changing workspace actions
that return file content, search results, diffs, or test output. Run the Phase
52 and Phase 83 routing command when budget changes alter conversation routing
inputs or specialist selection.

Budget diagnostics must stay metadata-only. They can report policy id, token
estimates, retained or dropped sections, and remediation hints, but they should
not persist raw prompt bodies or raw tool output as durable memory.

## Context Management Verification

Context management is the proactive layer on top of request-time budgeting.
Use `test/jido_code/context_management_test.exs` for policy, observation,
candidate, and summary-store rules. Use Phases 89 through 96 for pod topology,
monitor observation, compactor lifecycle, prompt injection, automatic trigger
adoption, reset-aware snapshots, runtime adoption, controls, and lifecycle
metadata.

Run AgentWorkspace regression tests when changing lifecycle wiring, because the
context-management pod is created and stopped with the work-item `CodingPod`.
Run context-budget tests when changing summary injection because
`compaction_summary` sections remain non-required prompt context.

Focused automatic compaction verification should include:

- `test/jido_code/phase_ninety_three_integration_test.exs`
- `test/jido_code/phase_ninety_four_integration_test.exs`
- `test/jido_code/phase_ninety_five_integration_test.exs`
- `test/jido_code/phase_ninety_six_integration_test.exs`

Also run conversation coordinator and snapshot regressions when touching
pending compaction, reset projection, retry, disable, or failure events.
`mix memory.verify` is only required when changing durable-memory capture,
memory graph boundaries, workflow provenance capture, or memory adoption.
`mix source_graph.verify` is only required when changing source graph prompt
projection, graph actions, graph pods, or workspace source graph entrypoints.

## Prompt Context Memory Verification

Prompt context memory is short-term runtime help for assembling the next
conversation turn. It is not durable repository memory, transcript storage, or
an operator-facing memory surface.

Use the focused context-memory command when changing
`JidoCode.Conversations.ContextMemory`, provider config, namespace policy,
fallback behavior, or lifecycle cleanup. Use the historical seeded conversation
batch when changing conversation runtime startup or shared child-work
supervision. Use the mixed Phase 52 and Phase 83 routing command when changing
workflow routing, refactor routing, prompt-memory fixtures, or any path where
routing integration and prompt-memory setup run in the same VM.

Prompt-memory tests use `JidoCode.PromptMemoryTestStore` for per-test ETS table
families. New prompt-memory tests should use that fixture instead of fixed ETS
table names or raw `:ets.delete/1` cleanup.

## Branching And Collaboration

The repo prefers:

- branch + PR flow for non-trivial work
- GitHub issues and PRs for shared history
- beadwork for local durable work state when initialized

If beadwork is unavailable in a checkout, call that out clearly rather than
pretending the local state is durable.

## Guardrails Worth Remembering

- keep product truth in governed records
- keep governed records in the embedded control-plane store through product
  query and record helpers
- keep runtime topology behind `AgentWorkspace`
- do not reintroduce Ash, Ecto, Repo, Postgres, or database migrations for
  product persistence
- do not call `TripleStore` directly from LiveView, workflow, or product
  service modules; use `JidoCode.ControlPlane.RecordStore`, product-specific
  stores, `StoreQuery`, or safe diagnostics
- prefer one module per file
- use `Req` for HTTP work
- do not add a parallel React frontend
- keep semantic and memory behavior bounded and explicit
- use `JidoCode.Conversations.ContextMemory` for short-term prompt help, not as
  transcript storage or durable repository memory
- run the right verification commands when touching specialized stacks

## Practical Contributor Checklist

Before landing meaningful work:

1. verify the relevant code paths
2. update docs when behavior or expectations changed
3. run the matching test and verification commands
4. keep the change aligned with the product-owned boundaries described in these
   guides

## Where To Go Back

If you need a refresher on the architecture, go back to:

- [`README.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/README.md)
- [`01-system-overview.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/01-system-overview.md)
- [`03-agent-workspace-and-runtime-topology.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/03-agent-workspace-and-runtime-topology.md)
- [`05-specialist-prompts-context-and-tool-execution.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/05-specialist-prompts-context-and-tool-execution.md)
