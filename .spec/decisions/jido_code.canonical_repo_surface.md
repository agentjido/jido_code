---
id: jido_code.canonical_repo_surface
status: accepted
date: 2026-03-25
affects:
  - package.jido_code
  - package.jido_code.package_quality_standards
  - docs.product_foundation
---

# Canonical repo surface

## Context

`jido_code` is a Phoenix product repo with desktop packaging, a package-local `.spec` workspace, and several contributor-facing quality tools. Over time the repository accumulated root-level wrapper scripts, package-policy residue, and deployment helpers that were useful in isolation but made the repo feel less like a normal Elixir/Phoenix application.

The cleanup goal is not to erase product-specific surfaces such as `.spec`, `AGENTS.md`, or `tauri/`. It is to keep the contributor workflow anchored on standard Mix and Phoenix entrypoints, while moving auxiliary deployment helpers and deleting redundant wrapper layers that do not carry durable product value.

The repository also no longer keeps a separate root `docs/` tree. Repo-facing orientation now lives in `README.md`, adjacent contributor guides, and the current-truth `.spec` workspace.

## Decision

The repository should prefer a canonical Phoenix/Elixir root surface:

- contributor workflows should use Mix commands directly, including the `spec_led_ex` Mix task surface for `.spec`
- repo-owned operator/runtime CLIs should prefer direct Mix tasks, such as `mix command`, over repo-root shell wrapper scripts
- dependency and lockfile refreshes should land as explicit version-controlled Mix configuration changes in the repo instead of lingering as a pile of uncurated bot branches
- redundant shell wrappers and one-off helper scripts should be removed when an equivalent Mix task or documented workflow already exists
- product-specific surfaces that are part of the actual repo contract, including `.spec`, `AGENTS.md`, and `tauri/`, should remain first-class
- top-level repo-facing documentation should stay concise in `README.md`, while durable architecture and policy records live under `.spec/`
- deployment helper files may live under a dedicated `deploy/` folder, while top-level tooling entry files that external tooling expects at the repo root may stay there
- repo policy should be expressed through version-controlled specs, docs, and Mix configuration rather than through an extra root `usage-rules.md` file

## Consequences

- README, CONTRIBUTING, and subject specs must describe the Mix-first workflow explicitly.
- Removing the separate root `docs/` tree means any durable in-repo product or architecture guidance must move into `README.md` or `.spec/` rather than silently disappearing.
- Any removal of root helper files requires updating both specs and deploy references so the simplified layout remains current truth.
- Keeping worktree-based branch flow healthy is part of this policy, so contributor tooling such as git hook installation must work without assuming a literal `.git/` directory.
- Consolidated dependency refreshes still have to preserve repo-local compatibility overrides such as `compat/jido_os` and `compat/jido_workflow` while keeping repo-owned demo surfaces on the current supported public APIs.
