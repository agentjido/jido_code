# Package Quality Standards

This subject defines how `jido_code` aligns with the canonical Jido package quality standards while documenting explicit product-repo exceptions.

```spec-meta
id: package.jido_code.package_quality_standards
kind: policy
status: active
summary: jido_code keeps the contributor-facing quality and core Mix command surfaces from the Jido package standards current, including repo-local compatibility package wiring, a repo-local Doctor config for generated modules without source files, committed dependency and lockfile hygiene that keeps `mix q` actionable after consolidated refreshes even as the source-code graph ontology/store stack adds heavier native dependencies, a repo-owned `mix server` start alias that prepares the current browser stack before boot, Vite-backed frontend asset commands that still flow through repo-owned Mix aliases, a deeper `mix frontend.verify` browser verification command, a repo-owned `mix source_graph.verify` semantic graph verification command, contributor docs that describe both the approved LiveView-plus-LiveVue browser boundary and the repository-scoped source graph workflow, and a documented fast-vs-deep quality split while the repo carries existing Dialyzer and Doctor debt, plus the current repo-local Spec Led gate surface in docs and CI.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.canonical_repo_surface
surface:
  - .doctor.exs
  - mix.exs
  - README.md
  - CONTRIBUTING.md
  - CHANGELOG.md
  - LICENSE
  - AGENTS.md
  - compat/
  - .spec/README.md
  - .spec/specs/package_quality_standards.spec.md
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
```

## Requirements

```spec-requirements
- id: package.jido_code.package_quality_alignment_doc_present
  statement: "The repository shall keep its package-quality alignment, approved browser-composition conventions, product-oriented fallback messaging expectations, and any explicit product-repo exceptions documented in version-controlled repo files or specs."
  priority: must
  stability: stable

- id: package.jido_code.package_quality_required_files_present
  statement: "The repository shall include the contributor-facing root files required by the package quality standards for this product repo: README, CHANGELOG, CONTRIBUTING, AGENTS, and LICENSE."
  priority: must
  stability: stable

- id: package.jido_code.package_quality_mix_surface_aligned
  statement: "The repository shall provide a standards-aligned mix surface with Phoenix-style contributor entrypoints (`mix setup`, `mix ecto.setup`, `mix ecto.reset`, `mix test`, and repo-owned `mix server`), direct Mix task entrypoints for repo-owned CLI flows, Vite-backed `mix assets.setup`, `mix assets.build`, and `mix assets.deploy` aliases for the browser toolchain, a repo-owned `mix frontend.verify` command for deeper browser-pipeline verification, a repo-owned `mix source_graph.verify` command for semantic source-code graph verification, coverage metadata, a fast `mix q` contributor gate that covers deps hygiene, lockfile hygiene, format, compile warnings, and Credo, plus repo-owned deeper quality surfaces for browser verification, semantic graph verification, documentation coverage, and broader static analysis while the repo carries existing Doctor and Dialyzer debt."
  priority: must
  stability: evolving

- id: package.jido_code.package_quality_ci_and_release_present
  statement: "The repository shall keep version-controlled CI and release workflows that enforce the documented package quality baseline for this repo."
  priority: must
  stability: evolving

- id: package.jido_code.package_quality_exceptions_documented
  statement: "Any repo-specific deviation from the canonical package standards shall be explicit and documented instead of remaining implicit drift."
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: .spec/specs/package_quality_standards.spec.md
  covers:
    - package.jido_code.package_quality_alignment_doc_present
    - package.jido_code.package_quality_exceptions_documented

- kind: command
  target: test -f README.md -a -f CHANGELOG.md -a -f CONTRIBUTING.md -a -f AGENTS.md -a -f LICENSE
  covers:
    - package.jido_code.package_quality_required_files_present

- kind: source_file
  target: mix.exs
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: "rg -n '\"frontend.verify\": \\[\"assets.setup\", \"assets.build\"\\]' mix.exs"
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: "rg -n '\"source_graph.verify\": \\[' mix.exs"
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: "rg -n 'server: \\[\"frontend.start\", \"phx.server\"\\]' mix.exs"
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: "rg -n 'mix server|mix frontend.verify|mix source_graph.verify|LiveView-plus-LiveVue|<\\.vue_surface|source_code graph|semantic graph' README.md CONTRIBUTING.md AGENTS.md"
  covers:
    - package.jido_code.package_quality_alignment_doc_present
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: mix help command
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: mix help coveralls
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: command
  target: test -f .github/workflows/ci.yml -a -f .github/workflows/release.yml
  covers:
    - package.jido_code.package_quality_ci_and_release_present

- kind: command
  target: "rg -n 'Verify frontend asset pipeline|mix frontend.verify|actions/setup-node@v4' .github/workflows/ci.yml"
  covers:
    - package.jido_code.package_quality_ci_and_release_present
```
