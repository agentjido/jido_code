# Package Quality Standards

This subject defines how `jido_code` aligns with the canonical Jido package quality standards while documenting explicit product-repo exceptions.

```spec-meta
id: package.jido_code.package_quality_standards
kind: policy
status: active
summary: jido_code keeps the contributor-facing quality and core Mix command surfaces from the Jido package standards current while documenting explicit product-repo exceptions.
decisions:
  - jido_code.namespace_and_control_naming
  - jido_code.canonical_repo_surface
surface:
  - mix.exs
  - README.md
  - CONTRIBUTING.md
  - CHANGELOG.md
  - LICENSE
  - coveralls.json
  - .dialyzer_ignore.exs
  - AGENTS.md
  - .github/workflows/ci.yml
  - .github/workflows/release.yml
  - docs/PACKAGE_QUALITY_ALIGNMENT.md
```

## Requirements

```spec-requirements
- id: package.jido_code.package_quality_alignment_doc_present
  statement: "The repository shall keep a repo-local comparison document that maps jido_code to the canonical Jido package quality standards and records any explicit product-repo exceptions."
  priority: must
  stability: stable

- id: package.jido_code.package_quality_required_files_present
  statement: "The repository shall include the contributor-facing root files required by the package quality standards for this product repo: README, CHANGELOG, CONTRIBUTING, AGENTS, and LICENSE."
  priority: must
  stability: stable

- id: package.jido_code.package_quality_mix_surface_aligned
  statement: "The repository shall provide a standards-aligned mix surface with Phoenix-style contributor entrypoints (`mix setup`, `mix ecto.setup`, `mix ecto.reset`, `mix test`), direct Mix task entrypoints for repo-owned CLI flows, coverage metadata, a `mix q` shortcut, and quality checks that include format, compile warnings, Credo, Dialyzer, and Doctor."
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
  target: docs/PACKAGE_QUALITY_ALIGNMENT.md
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
  target: mix help command
  covers:
    - package.jido_code.package_quality_mix_surface_aligned

- kind: source_file
  target: .dialyzer_ignore.exs
  covers:
    - package.jido_code.package_quality_mix_surface_aligned
    - package.jido_code.package_quality_exceptions_documented

- kind: command
  target: test -f .github/workflows/ci.yml -a -f .github/workflows/release.yml
  covers:
    - package.jido_code.package_quality_ci_and_release_present
```
