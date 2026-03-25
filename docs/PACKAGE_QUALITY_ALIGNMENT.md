# Package Quality Standards Alignment

<!-- covers: package.jido_code.package_quality_alignment_doc_present package.jido_code.package_quality_exceptions_documented -->

This document compares `jido_code` against the canonical Jido package quality standards:

- [Package Quality Standards](https://jido.run/docs/contributors/package-quality-standards)

The comparison is intentionally repo-local. `jido_code` is the primary product and implementation repo in this workspace, so some package-oriented standards apply directly, while others need explicit product-repo exceptions.

## Direct Alignment Targets

These standards apply directly and should stay implemented in this repo:

- Required contributor files at the repository root.
- A standards-aligned `mix quality` surface, including `doctor --raise`.
- CI coverage, release automation, and dependency hygiene.
- README and contributor docs that explain installation, quality, and release flow.

## Explicit Product-Repo Exceptions

The following deviations are intentional and documented rather than treated as drift:

- `jido_code` is a Phoenix product repo, not a Hex-first library package. Release automation should still be version-controlled and reproducible, but Hex publish metadata is readiness scaffolding rather than an immediate publishing commitment.
- Runtime modules still use `JidoCode.*` while conceptual product docs use `Jido.Code.*`. This is a deliberate migration state captured in `.spec/decisions/jido_code.namespace_and_control_naming.md`.
- Product-owned demo and showcase domains under `lib/` are part of the shipped application surface, not standalone tutorial examples that should be split into a top-level `examples/` directory.
- Ash resources remain the canonical product modeling layer. Zoi should be used directly for option and struct validation when plain schemas are the right fit, but not as a blanket replacement for Ash resources.
- Doctor enforcement is active, but the coverage thresholds are intentionally transitional while the repo works down legacy missing-doc backlog across product modules and generated web surfaces.
- Dialyzer remains part of `mix q`, but the repo currently carries a committed `.dialyzer_ignore.exs` baseline for pre-existing static-analysis backlog. The baseline is temporary and should shrink as warnings are fixed.
- Test coverage is enforced through a version-controlled `coveralls.json`, but the minimum is intentionally transitional at 60% until the product repo pays down broader execution-surface coverage debt.

## Gap Summary

The standards comparison identified these repo-applicable gaps to close:

- Add the missing root `usage-rules.md`.
- Align `mix.exs` with the standards for coverage metadata, preferred CLI envs, and the `mix q` shortcut.
- Restore the standards-aligned quality gate by removing the accidental baseline route disablement and by fixing documentation-tool configuration.
- Add a version-controlled release workflow and document the release path for maintainers.
- Enforce coverage and dependency hygiene in CI.

## Done In This Pass

- Added the missing root `usage-rules.md`.
- Aligned `mix.exs` with standards-facing metadata, coverage settings, package metadata, direct `zoi` dependency declaration, `mix q`, and a standards-aligned `mix quality` alias.
- Added `.doctor.exs` and a compatibility placeholder for generated Folio modules whose compile source is `nofile`, so Doctor can be configured consistently inside this repo.
- Added `.dialyzer_ignore.exs` and wired Dialyzer to use it with unused-filter checking so the standards-aligned quality gate can pass while making the remaining static-analysis backlog explicit.
- Added `coveralls.json` so coverage enforcement is real in CI, with a documented transitional minimum instead of a non-functional aspirational threshold.
- Restored the disabled product, RPC, and API router surfaces that were creating verified-route drift.
- Updated `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, and `docs/README.md` so contributors can discover the quality and release expectations from the repo itself.
- Added CI coverage/spec enforcement and a version-controlled GitHub release workflow.
