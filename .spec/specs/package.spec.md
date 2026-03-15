# Package

High-level package contract for `jido_code`.

```spec-meta
id: package.jido_code
kind: package
status: active
summary: jido_code is the primary implementation repo and maintains a package-local Spec Led workspace.
decisions:
  - jido_code.auth_user_system
surface:
  - AGENTS.md
  - mix.exs
  - .spec/README.md
  - .spec/specs/*.spec.md
  - .spec/decisions/*.md
  - lib/
  - test/
```

## Requirements

```spec-requirements
- id: package.jido_code.primary_implementation_repo
  statement: The jido_code repository shall serve as the primary product and implementation repo for active work in this workspace.
  priority: must
  stability: stable

- id: package.jido_code.spec_led_workspace
  statement: The repository shall maintain a package-local .spec workspace for current-truth subject specs, durable ADRs, and generated spec state.
  priority: must
  stability: stable
```

## Verification

```spec-verification
- kind: source_file
  target: AGENTS.md
  covers:
    - package.jido_code.primary_implementation_repo

- kind: source_file
  target: .spec/README.md
  covers:
    - package.jido_code.spec_led_workspace
```
