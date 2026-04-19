# 10. Development Workflow And Quality Gates

This guide summarizes how contributors should work in `jido_code` day to day.

Current truth for this area lives in:

- [`../../README.md`](https://github.com/mikehostetler/jido_code/blob/main/README.md)
- [`../../CONTRIBUTING.md`](https://github.com/mikehostetler/jido_code/blob/main/CONTRIBUTING.md)
- [`../../AGENTS.md`](https://github.com/mikehostetler/jido_code/blob/main/AGENTS.md)
- [`../../.spec/specs/developer_workflow.spec.md`](https://github.com/mikehostetler/jido_code/blob/main/.spec/specs/developer_workflow.spec.md)

## Normal Local Workflow

The normal contributor path is the repo-root Phoenix workflow with host
Postgres.

Typical flow:

1. `asdf install`
2. start local Postgres
3. `mix setup`
4. `mix server`
5. `mix test`

Desktop packaging and runtime work are separate and live under
[`../../tauri/README.md`](https://github.com/mikehostetler/jido_code/blob/main/tauri/README.md).

## Read Order For New Work

For non-trivial changes, the repo expects contributors to orient themselves
before editing:

1. read `README.md`
2. read `AGENTS.md`
3. read `.spec/README.md`
4. read the relevant subject specs and ADRs
5. read the relevant code, routes, and tests

## Spec-Led Workflow

`.spec/` is the current-truth architecture and policy workspace.

Useful commands:

```bash
mix spec.prime --base HEAD
mix spec.next
mix spec.check --base origin/main
mix spec.status
```

These help you:

- load the relevant context
- see what subject should be updated next
- verify branch coherence against current truth

## Quality Commands

| Command | Purpose |
| --- | --- |
| `mix test` | run test suite and provision test DB |
| `mix q` | fast quality gate |
| `mix quality` | broader local verification including frontend and semantic checks |
| `mix frontend.verify` | verify LiveVue and Vite browser pipeline |
| `mix source_graph.verify` | verify semantic source-code graph stack |
| `mix memory.verify` | verify memory graph and capture-plane behavior |
| `mix semantic.verify` | verify product-facing semantic behavior |
| `mix docs` | build repo docs surface |

## When To Run Specialty Verification

Run the narrower verification commands when you touch those boundaries:

- browser stack or `live_vue` changes -> `mix frontend.verify`
- source graph boundaries -> `mix source_graph.verify`
- memory graph or capture boundaries -> `mix memory.verify`
- product-facing semantic surfaces or services -> `mix semantic.verify`

## Branching And Collaboration

The repo prefers:

- branch + PR flow for non-trivial work
- GitHub issues and PRs for shared history
- beadwork for local durable work state when initialized

If beadwork is unavailable in a checkout, call that out clearly rather than
pretending the local state is durable.

## Guardrails Worth Remembering

- keep product truth in governed records
- keep runtime topology behind `AgentWorkspace`
- prefer one module per file
- use `Req` for HTTP work
- do not add a parallel React frontend
- keep semantic and memory behavior bounded and explicit
- run the right verification commands when touching specialized stacks

## Practical Contributor Checklist

Before landing meaningful work:

1. verify the relevant specs and code paths
2. update docs or specs when behavior or expectations changed
3. run the matching test and verification commands
4. keep the change aligned with the product-owned boundaries described in these
   guides

## Where To Go Back

If you need a refresher on the architecture, go back to:

- [`README.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/README.md)
- [`01-system-overview.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/01-system-overview.md)
- [`03-agent-workspace-and-runtime-topology.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/03-agent-workspace-and-runtime-topology.md)
- [`05-specialist-prompts-context-and-tool-execution.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/05-specialist-prompts-context-and-tool-execution.md)

