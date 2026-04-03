# Developer Workflow

This subject defines the normal local development contract for contributors working on `jido_code`.

```spec-meta
id: developer.workflow
kind: policy
status: active
summary: jido_code keeps normal repository development on a host Postgres-backed Phoenix workflow, presents a quickstart-first repo README, uses root Mix commands as the canonical dependency refresh and quality surface including repo-owned `mix server` and `mix frontend.verify` commands for the richer browser stack, pins the repo toolchain through asdf including the Node runtime needed by the Vite frontend pipeline, and isolates desktop runtime configuration behind desktop-specific entrypoints.
decisions:
  - jido_code.local_developer_workflow
surface:
  - .tool-versions
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
  statement: The primary contributor commands shall present a Phoenix-style workflow where `mix setup` drives `ecto.setup`, `mix server` is the preferred local start path and prepares the current browser stack when needed, `mix test` provisions the test database with Ecto tasks, and repo dependency refresh, browser verification, plus fast quality hygiene stay rooted in the same Mix surface instead of external wrapper scripts or desktop-only entrypoints.
  priority: must
  stability: evolving

- id: developer.workflow.docs_split
  statement: Contributor-facing setup docs, ExDoc extras, and the root env example shall describe host-Postgres repo development separately from the desktop packaging and runtime guide while exposing the repo-local `spec_led_ex` workflow, direct Mix task entrypoints, the `mix frontend.verify` browser verification path, and the current LiveView-plus-LiveVue frontend boundary instead of repo shell wrappers.
  priority: must
  stability: evolving

- id: developer.workflow.repo_toolchain_asdf
  statement: The repository shall pin contributor tool versions in a root `.tool-versions` file, including the Node runtime required by the Vite frontend pipeline, and contributor setup docs shall use `asdf install` for the normal local development path.
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
  target: "rg -n '\"frontend.verify\": \\[\"assets.setup\", \"assets.build\"\\]' mix.exs"
  covers:
    - developer.workflow.phoenix_mix_surface

- kind: command
  target: "rg -n 'server: \\[\"frontend.start\", \"phx.server\"\\]' mix.exs"
  covers:
    - developer.workflow.phoenix_mix_surface

- kind: command
  target: "rg -n 'test: \\[\"ecto.create --quiet\", \"ecto.migrate --quiet\", \"test\"\\]' mix.exs"
  covers:
    - developer.workflow.phoenix_mix_surface

- kind: command
  target: "rg -n 'extras: \\[\"README.md\", \"CHANGELOG.md\", \"CONTRIBUTING.md\", \"\\.spec/README.md\"\\]' mix.exs"
  covers:
    - developer.workflow.docs_split

- kind: command
  target: "rg -n 'localhost:5432|postgres / `postgres`|mix setup|mix assets.setup|mix assets.build|mix frontend.verify|mix server|mix ecto.reset|mix test|live_vue|<\\.vue_surface|mix spec.prime --base HEAD|mix spec.next|mix spec.check --base origin/main|mix spec.status|mix skill.list|mix command list|mix workflow.control definitions' README.md"
  covers:
    - developer.workflow.docs_split

- kind: command
  target: "rg -n 'localhost:5432|postgres / `postgres`|mix assets.setup|mix assets.build|mix frontend.verify|mix server|mix test|mix ecto.reset|<\\.vue_surface|mix spec.prime --base HEAD|mix spec.next|mix spec.check --base origin/main|mix spec.status|tauri/README.md' CONTRIBUTING.md"
  covers:
    - developer.workflow.docs_split

- kind: command
  target: "rg -n '^erlang 27\\.3$|^elixir 1\\.18\\.4-otp-27$|^nodejs 22\\.14\\.0$|^rust stable$|^zig 0\\.15\\.2$' .tool-versions"
  covers:
    - developer.workflow.repo_toolchain_asdf

- kind: command
  target: "rg -n 'asdf install|\\.tool-versions' README.md"
  covers:
    - developer.workflow.repo_toolchain_asdf

- kind: command
  target: "rg -n 'asdf install' CONTRIBUTING.md"
  covers:
    - developer.workflow.repo_toolchain_asdf

- kind: command
  target: "rg -n 'Leave DATABASE_URL unset|localhost:5432|jido_code_dev|jido_code_test' .env.example"
  covers:
    - developer.workflow.docs_split

- kind: command
  target: "rg -n 'not the normal contributor workflow|mix setup|mix server|DATABASE_URL' tauri/README.md"
  covers:
    - developer.workflow.docs_split
```
