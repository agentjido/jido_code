# `.spec` Agent Guide

Use this folder to maintain authored Spec Led Development subjects and generated state for `jido_code`.

<!-- covers: spec.workspace.agents_present -->

## First Read

1. Run `bw prime` from the repo root if you have not already.
2. Read `.spec/README.md`.
3. Read `.spec/decisions/README.md` and any ADRs that affect the subject you are changing.
4. Read the current `.spec/specs/*.spec.md` files before editing.

## Working Rules

- Keep one subject per file.
- Put normative statements in `spec-requirements`.
- Add `spec-scenarios` only when `given` / `when` / `then` improves clarity.
- Add `spec-meta.decisions` only when a subject depends on a durable cross-cutting ADR.
- Keep ADRs in `.spec/decisions/*.md` for cross-cutting policy only.
- Prefer targeted command verifications for behavioral proof.
- Use file-backed verifications only when the target can carry stable `covers:` markers for every covered id.
- Keep verification targets repository-root-relative.
- Use Git history and pull requests as the change log; keep `.spec` current-state only.
- Finish with `mix spec.verify --debug`, `mix spec.check`, and `mix spec.diffcheck`.
- Run `mix spec.report` when you need coverage or weak-spot summaries.
- If spec tooling is blocked by a compile failure outside `.spec`, report the blocker instead of fabricating verification results.
