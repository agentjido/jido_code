# 00. Spec Led Development And Drift Control

<!-- covers: docs.product_foundation.spec_led_intro_guide_present -->

This guide explains why `jido_code` uses `spec_led_ex`, how the `.spec/`
workspace works, and how contributors keep specs, code, tests, and guides from
drifting apart.

Current truth for this area lives in:

- [`../../.spec/README.md`](https://github.com/mikehostetler/jido_code/blob/main/.spec/README.md)
- [`../../.spec/AGENTS.md`](https://github.com/mikehostetler/jido_code/blob/main/.spec/AGENTS.md)
- [`../../.spec/specs/spec_system.spec.md`](https://github.com/mikehostetler/jido_code/blob/main/.spec/specs/spec_system.spec.md)
- [`../../.spec/specs/developer_workflow.spec.md`](https://github.com/mikehostetler/jido_code/blob/main/.spec/specs/developer_workflow.spec.md)
- [`../../README.md`](https://github.com/mikehostetler/jido_code/blob/main/README.md)
- [`../../CONTRIBUTING.md`](https://github.com/mikehostetler/jido_code/blob/main/CONTRIBUTING.md)

## Why This Comes First

This repo is intentionally spec-led.

That does not mean the spec workspace is a ceremonial extra layer beside the
real work. It means the repo keeps its current truth for architecture, policy,
and contributor expectations in versioned files under `.spec/`, then expects
code, tests, and guides to converge on that truth.

The goal is simple:

- make product and architecture rules explicit
- keep cross-cutting decisions reviewable
- catch drift early instead of after behavior, docs, and assumptions have
  already forked

The explanatory developer guides in `docs/developer/` help people build a fast
mental model, but `.spec/` is the stronger signal when there is any conflict.

## What `spec_led_ex` Is Doing

`spec_led_ex` is the repo-local Mix task surface that maintains and checks this
workflow.

In practice it does four jobs:

1. keeps authored current truth in `.spec/specs/*.spec.md`
2. keeps durable cross-cutting decisions in `.spec/decisions/*.md`
3. generates `.spec/state.json` as derived index and validation state
4. checks whether the current branch changed code, tests, docs, and current
   truth coherently

That is why the normal loop is not "write docs later" or "fix the specs at the
end if someone remembers." The loop is designed to keep authored truth and
implementation moving together.

## The `.spec` Workspace Pieces

The main sub-components are:

- `.spec/README.md`
  - explains layout and the default local loop
- `.spec/AGENTS.md`
  - gives local operating guidance for agents working in the spec workspace
- `.spec/topology.md`
  - explains the current product, runtime, and semantic topology at a high
    level
- `.spec/specs/*.spec.md`
  - current-truth subject files; keep one subject per file and put normative
    requirements here
- `.spec/decisions/README.md`
  - explains what belongs in a durable ADR
- `.spec/decisions/*.md`
  - durable cross-cutting decisions only
- `.spec/planning/README.md` and `.spec/planning/*.md`
  - optional phased implementation or migration plans that complement current
    truth
- `.spec/state.json`
  - generated index and verification state; do not hand-edit it

This split matters.

Subjects define current truth. ADRs explain durable decisions. Planning docs
help people execute multi-step work when that is useful. Generated state records
what the tooling observed.

Those are different jobs. Keeping them separate is one of the main ways the
repo avoids drift.

## Planning Is Supported, Not Required

The planning directory exists because some large migrations and rollouts need a
shared phased plan.

It is not required for every change.

It is also not a mandatory personal planning style. If a developer can make a
small, well-scoped change directly from the subject specs, code, and tests,
that is fine. If a larger change benefits from a checklist, a phased rollout
document, issue notes, or no written plan at all, that is a judgment call.

The important rule is not "always write a plan." The important rule is:

- keep current truth in `specs/`
- keep durable policy in `decisions/`
- use `planning/` only when a shared implementation or rollout plan genuinely
  helps

Most of the existing planning files are phase-oriented because that fit the
work they were written for. Treat that as a local convention for those efforts,
not as a required template for every contributor.

## The Default Local Loop

The default loop in this repo is:

1. run `bw prime` when Beadwork is available in the checkout
2. run `mix spec.prime --base HEAD` when you enter the repo or hand work to
   another agent
3. make the code, test, or docs change
4. add or tighten the smallest proof that matters
5. run `mix spec.next`
6. if `mix spec.next` says current truth is missing, update the named subject
   or ADR
7. run `mix spec.check --base origin/main`

Two practical details matter here:

- `mix spec.next` is the anti-drift step; it compares the current Git change set
  to the authored current truth and tells you what is missing next
- `mix spec.check` is the finishing gate; it updates derived state, validates
  specs, and checks branch coherence

## The Main Command Surface

Most contributors only need a small subset of the task surface day to day.

### Session-start and branch-guidance commands

- `mix spec.prime`
  - read-only session-start snapshot
  - useful options: `--base <ref>`, `--since <checkpoint>`, `--bugfix`,
    `--run-commands`, `--min-strength claimed|linked|executed`, `--json`
- `mix spec.next`
  - read-only "what should I update next?" command for the current change set
  - useful options: `--base <ref>`, `--since <checkpoint>`, `--bugfix`,
    `--verbose`, `--json`

### Default day-to-day gate

- `mix spec.check`
  - runs indexing, strict validation, and branch coherence checks
  - useful options: `--base <ref>`, `--no-run-commands`,
    `--min-strength claimed|linked|executed`
- `mix specs`
  - alias for `mix spec.check`

### Occasional maintainer commands

- `mix spec.status`
  - coverage, proof-strength, weak-spot, and ADR summary
  - useful options: `--no-run-commands`, `--min-strength ...`, `--json`
- `mix spec.decision.new DECISION_ID`
  - scaffolds a durable ADR under `.spec/decisions/`
  - useful options: `--title "Decision Title"`, `--force`

### Lower-level plumbing commands

- `mix spec.index`
  - rebuilds the `.spec` index and writes `.spec/state.json`
- `mix spec.validate`
  - validates authored specs and writes `.spec/state.json`
  - useful options: `--run-commands`, `--min-strength ...`, `--strict`,
    `--debug`
- `mix spec.init`
  - bootstraps a canonical `.spec/` workspace for a repo that does not have one
    yet

In this repo, the commands to learn first are still `prime`, `next`, and
`check`.

## How Verification Strength Works

`spec_led_ex` tracks verification strength per coverage claim:

- `claimed`
  - a verification item names a requirement or scenario id
- `linked`
  - a file-backed target exists and contains the covered id
- `executed`
  - a command verification actually ran and exited successfully

This matters because a spec can look complete while still being weakly proved.

`mix spec.status`, `mix spec.validate`, and `mix spec.check` can all raise the
required minimum strength when a branch or CI job needs stricter evidence.

## How To Prevent Spec Drift

The practical anti-drift rules in this repo are:

- update current truth in the same branch as the behavior change
- run `mix spec.next` after code, docs, or tests change, not just at the end
- keep one subject per file so rules stay easy to find and update
- use ADRs only for durable cross-cutting decisions
- keep rollout chronology in Git history and optional planning docs, not inside
  current-truth subjects
- prefer targeted verification that proves real behavior or real file coverage
- treat a disagreement between code, guides, and `.spec` as a problem to
  reconcile immediately
- never use planning docs as a substitute for updating subject specs
- do not hand-edit `.spec/state.json`; regenerate it through the Mix tasks

A good rule of thumb is:

If a reviewer would need to ask "where is the current truth for this change?",
the branch is not done yet.

## Common Failure Modes

The most common ways teams recreate drift are:

- changing behavior and leaving the subject spec untouched
- writing a plan and forgetting to update the real current-truth subject
- adding an ADR for a one-off local detail that should have stayed inside a
  subject file or PR discussion
- letting a guide explain something the code and `.spec` no longer do
- treating `mix spec.status` as the final gate instead of `mix spec.check`

The system works best when contributors keep the authored truth small, explicit,
and updated in the same change that introduced the behavior.

## Read Next

Continue with
[`01-system-overview.md`](https://github.com/mikehostetler/jido_code/blob/main/docs/developer/01-system-overview.md).
