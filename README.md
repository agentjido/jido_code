# Jido.Code

[![CI](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml/badge.svg)](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml)

Jido.Code is the primary product and implementation repo in this workspace. It is a Phoenix + LiveView application built on Ash, Postgres, and the Jido runtime, with a separate Tauri desktop packaging path.

Status today is alpha and developer-focused. The repo is real, runnable software, but it is still evolving toward the broader product shape described in the repo-local spec workspace.

<!-- covers: docs.product_foundation.readme_quickstart_present -->
<!-- covers: docs.operator_provider_auth_guide.local_quickstart_excludes_operator_setup -->
## Quickstart

Normal repository development uses the repo root and a host PostgreSQL instance.

Expected local defaults:

- PostgreSQL on `localhost:5432`
- username/password `postgres` / `postgres`
- databases `jido_code_dev` and `jido_code_test*`

```bash
git clone https://github.com/epic-creative/jido_code.git
cd jido_code

asdf install
mix setup
mix server
```

Then open http://localhost:4000

For normal local development, leave `DATABASE_URL` unset. `mix setup` installs dependencies, prepares the development database, and builds assets. `mix server` is the preferred start path and prepares browser dependencies or bundles first when the current LiveVue/Vite output is missing. `mix test` provisions the test database automatically. Desktop packaging is separate and lives in [`tauri/README.md`](tauri/README.md).

## What This Repo Contains

Jido.Code currently centers on a few concrete areas:

- a Phoenix web app with AshAuthentication-backed sign-in, settings, setup, and dashboard/workbench routes
- Forge, an OTP subsystem for isolated execution sessions with observable events and a LiveView terminal UI
- GitHub integration primitives for repos, webhook deliveries, analyses, and automation-oriented workflows
- Jido-oriented command, skill, and workflow task surfaces for local operator and developer use
- a Tauri desktop packaging path that wraps the Phoenix backend as a sidecar application

The product direction is still broader than the currently finished UX. Treat this repo as a working implementation base, not a finished end-user product.

## Local Development

The repo toolchain is pinned in `.tool-versions` for `asdf`. Normal day-to-day development should feel like a conventional Phoenix app:

```bash
mix setup
mix assets.setup
mix assets.build
mix frontend.verify
mix server
mix test
mix ecto.reset
```

`.env.example` includes the main runtime overrides. For the normal contributor path, the important rule is still: leave `DATABASE_URL` unset and use the checked-in `config/dev.exs` and `config/test.exs` defaults.

You may also need extra credentials depending on what you are exercising:

- `ANTHROPIC_API_KEY` for Claude-powered flows
- `SPRITES_API_TOKEN` for live Sprites-backed execution
- mail provider settings such as `RESEND_API_KEY`

<!-- covers: docs.product_foundation.readme_frontend_stack_orientation_present -->
## Frontend Stack

`jido_code` keeps LiveView as the routed product shell and uses `live_vue` only for bounded regions that genuinely need richer client-side composition.

- Keep route ownership, auth/session boundaries, and straightforward forms in LiveView and HEEx.
- Mount Vue-backed regions through `<.vue_surface ...>` rather than raw LiveVue calls so props, streams, and emits stay product-owned.
- Treat `props:` and `streams:` as server-authored boundaries and map Vue emits back into LiveView events.
- When changing the browser stack, run `mix frontend.verify`. Hybrid screens must degrade to product-oriented fallback messaging instead of exposing raw Vite or SSR failures to operators.

## Day-To-Day Commands

```bash
mix setup               # deps, ecto.setup, and asset build
mix assets.setup        # install browser toolchain dependencies
mix assets.build        # build the Vite + SSR browser bundle
mix frontend.verify     # run the repo-owned browser pipeline verification
mix server              # preferred local start path; prepares browser deps/builds if needed
mix ecto.reset          # drop, recreate, migrate, and seed the dev DB
mix test                # create/migrate the test DB and run tests
mix q                   # fast merge-safe quality gate
mix quality             # fast gate plus frontend verification, doctor, and dialyzer debt surfacing
mix precommit           # compile, format, and test
mix coveralls           # run tests with coverage summary
mix coveralls.html      # generate the HTML coverage report
mix spec.prime --base HEAD      # print session-start Spec Led context for the current branch
mix spec.next                   # point at the next subject or ADR update for current changes
mix spec.check --base origin/main # run the full Spec Led gate and branch coherence checks
mix spec.status                 # summarize current coverage and verification strength
mix docs                # build ExDoc output from the repo docs surface
```

Repo-owned CLI surfaces stay Mix-first:

```bash
mix skill.list
mix skill.run my-skill --route my/route --data '{"key":"value"}'

mix command list
mix command my-command --params '{"key":"value"}'

mix workflow.control definitions
mix workflow.run my_workflow --inputs '{"file_path":"lib/example.ex","mode":"full"}'
```

<!-- covers: docs.product_foundation.docs_index_present -->
<!-- covers: docs.product_foundation.product_summary_present -->
<!-- covers: docs.operator_provider_auth_guide.external_operator_docs_allowed -->
## Repo Guides

The canonical repo-facing guides now live here:

- [`.spec/README.md`](.spec/README.md) for the repo-local Spec Led Development workflow
- [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor setup and quality expectations
- [`tauri/README.md`](tauri/README.md) for the separate desktop packaging/runtime path
- [`CHANGELOG.md`](CHANGELOG.md) for release history
- [`AGENTS.md`](AGENTS.md) for local agent operating guidance in this repo

The durable architecture and product-shaping decisions live in [`.spec/decisions/`](.spec/decisions/), especially:

- [`.spec/decisions/jido_code.runic_execution_model.md`](.spec/decisions/jido_code.runic_execution_model.md)
- [`.spec/decisions/jido_code.vsm_recursion_and_scope.md`](.spec/decisions/jido_code.vsm_recursion_and_scope.md)
- [`.spec/decisions/jido_code.local_developer_workflow.md`](.spec/decisions/jido_code.local_developer_workflow.md)

## Repo Shape

```text
assets/   frontend assets
config/   Phoenix, Ash, and runtime configuration
deploy/   container and deploy helper files
lib/      application and web code
priv/     repo migrations, seeds, and static assets
tauri/    desktop packaging app
test/     tests and support code
.spec/    current-truth specs and ADRs
```

## Main Technologies

| Package | Role |
| --- | --- |
| [`phoenix`](https://github.com/phoenixframework/phoenix) | Web framework and router |
| [`phoenix_live_view`](https://github.com/phoenixframework/phoenix_live_view) | Interactive server-rendered UI |
| [`ash`](https://ash-hq.org) | Resource modeling and application layer |
| [`ash_postgres`](https://github.com/ash-project/ash_postgres) | Primary data layer integration |
| [`jido`](https://github.com/agentjido/jido) | Agent runtime, signals, and orchestration patterns |
| [`req`](https://github.com/wojtekmach/req) | HTTP client |
| [`burrito`](https://github.com/burrito-elixir/burrito) | Phoenix desktop sidecar packaging |
| [`tauri`](https://v2.tauri.app) | Native desktop shell |

## Release Notes

Release automation is version-controlled in [`.github/workflows/release.yml`](.github/workflows/release.yml). Keep [`CHANGELOG.md`](CHANGELOG.md) current, run the relevant quality and spec checks, and cut releases from the workflow instead of relying on ad hoc local release steps.

## License

Apache-2.0 — see [LICENSE](LICENSE) for details.
