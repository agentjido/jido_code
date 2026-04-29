---
id: jido_code.local_developer_workflow
status: accepted
date: 2026-03-25
affects:
  - developer.workflow
  - docs.product_foundation
  - package.jido_code
  - package.jido_code.package_quality_standards
---

# Local Phoenix Developer Workflow

## Context

`jido_code` now has two distinct ways to run:

- normal repository development from the repo root with `mix` commands
- desktop packaging/runtime work through Burrito and Tauri

Without an explicit rule, the desktop path starts to bleed into contributor setup,
which makes the repo feel less like a normal Phoenix application to work on.

## Decision

Normal contributor development uses the repo root with the standard Phoenix-style
commands:

- `mix setup`
- `mix phx.server`
- `mix test`
- `mix ecto.reset`
- `mix onboarding.reset --keep-owner`
- `mix onboarding.reset --full`

The local developer database comes from the checked-in dev/test config and targets a
host PostgreSQL instance. Desktop packaging/runtime guidance remains documented
separately and must not become the default contributor story.

When contributors use the onboarding reset surface during local bootstrap iteration,
that reset rewinds setup state and clears imported managed-repository inventory plus
persisted repo-kernel snapshots so the signed-in `/setup` flow does not inherit stale
control-plane repository state from a prior run.

## Consequences

- The primary public `mix` aliases should read like Phoenix/Ecto entrypoints rather than Ash-specific setup commands.
- The onboarding reset task is a developer convenience surface, so it must reset repo-import side effects as well as setup metadata when contributors rewind local bootstrap state.
- README, CONTRIBUTING, and the root env example should describe host-Postgres local development clearly.
- The Tauri guide should remain discoverable, but explicitly separate from normal repo-root development.
- Future desktop database work should preserve this contributor contract even if desktop runtime internals change.
