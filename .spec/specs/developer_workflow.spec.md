# Developer Workflow

This subject defines the normal local development contract for contributors working on `jido_code`.

```spec-meta
id: developer.workflow
kind: policy
status: active
summary: jido_code keeps normal repository development on a host Postgres-backed Phoenix workflow while isolating desktop runtime configuration behind desktop-specific entrypoints.
surface:
  - mix.exs
  - config/dev.exs
  - config/test.exs
  - config/runtime.exs
  - README.md
  - CONTRIBUTING.md
  - .env.example
  - tauri/README.md
```

## Requirements

```spec-requirements
- id: developer.workflow.host_postgres_defaults
  statement: Normal repository development and test configuration shall default to a host Postgres instance instead of requiring the desktop runtime path.
  priority: must
  stability: stable

- id: developer.workflow.desktop_runtime_isolated
  statement: Desktop runtime configuration shall stay isolated behind desktop-specific entrypoints so it does not become the default contributor workflow.
  priority: must
  stability: evolving

- id: developer.workflow.phoenix_mix_surface
  statement: The primary contributor commands shall present a Phoenix-style workflow where `mix setup` drives `ecto.setup` and `mix test` provisions the test database with Ecto tasks instead of making `ash.setup` the public entrypoint.
  priority: must
  stability: evolving
```

## Verification

```spec-verification
- kind: command
  target: "rg -n 'postgres|localhost|jido_code_dev' config/dev.exs"
  covers:
    - developer.workflow.host_postgres_defaults

- kind: command
  target: "rg -n 'postgres|localhost|jido_code_test' config/test.exs"
  covers:
    - developer.workflow.host_postgres_defaults

- kind: command
  target: "rg -n 'BURRITO_TARGET|DATABASE_URL' config/runtime.exs"
  covers:
    - developer.workflow.desktop_runtime_isolated

- kind: command
  target: "rg -n 'setup: \\[\"deps.get\", \"git_hooks.install\", \"ecto.setup\", \"assets.setup\", \"assets.build\"\\]' mix.exs"
  covers:
    - developer.workflow.phoenix_mix_surface

- kind: command
  target: "rg -n 'test: \\[\"ecto.create --quiet\", \"ecto.migrate --quiet\", \"test\"\\]' mix.exs"
  covers:
    - developer.workflow.phoenix_mix_surface
```
