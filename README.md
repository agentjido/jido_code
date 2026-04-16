# Jido.Code

<!-- covers: package.jido_code.version_controlled_quality_surfaces -->

[![CI](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml/badge.svg)](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml)

Jido.Code is the primary product and implementation repo in this workspace. It is a Phoenix + LiveView application built on Ash, Postgres, and the Jido runtime, with a separate Tauri desktop packaging path.

Status today is alpha and developer-focused. The repo is real, runnable software, but it is still evolving toward the broader product shape described in the repo-local spec workspace.

<!-- covers: docs.product_foundation.readme_quickstart_present -->
<!-- covers: docs.operator_provider_auth_guide.local_quickstart_excludes_operator_setup -->
<!-- covers: docs.product_foundation.readme_source_graph_orientation_present -->
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
- a repo-scoped conversation orchestration layer with interruptible turns, durable event history, bounded shared context, and governed work steering
- Forge, an OTP subsystem for isolated execution sessions with observable events
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

## Source Code Graph

The repo now carries a repository-scoped semantic source-code graph capability
for managed repositories.

- The stack is built from `elixir_ontologies`, `triple_store`, `sparql`, and
  `rocksdb`.
- The graph is repository-local, not a global service. Each workspace keeps its
  store under `.jido_code/source_code_graph/triple_store`.
- Normal lifecycle is explicit: analyze, load or refresh the canonical
  `source_code` named graph, then query it.
- Contributors touching this stack should have the normal native build toolchain
  available for RocksDB-backed dependencies. The repo already pins the Elixir,
  Erlang, Node, Rust, and Zig toolchain through `.tool-versions`.

Use the semantic graph when you need cross-file semantic structure:

- module and function discovery across a repository
- bounded impact tracing
- runtime pattern lookups
- repeated SPARQL-backed structural questions
- explicit planning, review, and explanation flows that opt into bounded
  semantic context
- governed work or evidence adoption from semantic findings after an explicit
  product action

Prefer ordinary file/code tools when you need:

- exact latest source text
- line-level editing context
- one-off single-file reads
- answers that should not depend on the current graph being analyzed or loaded

Keep the semantic graph as a bounded enhancement, not a hidden dependency:

- operator and workflow paths should remain legible when the graph is stale,
  degraded, or unavailable
- recovery stays product-owned and repo-scoped
- semantic findings only influence product behavior after explicit governed
  adoption into records like `Observation`, `Assessment`, `WorkItem`, or
  `Evidence`

<!-- covers: docs.product_foundation.readme_frontend_stack_orientation_present -->
## Frontend Stack

`jido_code` keeps LiveView as the routed product shell and uses `live_vue` only for bounded regions that genuinely need richer client-side composition.

- Keep route ownership, auth/session boundaries, and straightforward forms in LiveView and HEEx.
- Mount Vue-backed regions through `<.vue_surface ...>` rather than raw LiveVue calls so props, streams, and emits stay product-owned.
- Treat `props:` and `streams:` as server-authored boundaries and map Vue emits back into LiveView events.
- When changing the browser stack, run `mix frontend.verify`. Hybrid screens must degrade to product-oriented fallback messaging instead of exposing raw Vite or SSR failures to operators.

## Conversation Model

Productive coding conversations are managed-repository scoped and usually attach to one canonical `WorkItem`.

- Use the conversation driver and sequenced event stream for conversation UX. Snapshots are for cold load, reconnect recovery, and degraded continuity, not steady-state polling.
- Route steering through canonical work records. If a conversation narrows, redirects, or promotes work, the durable outcome should rejoin `ManagedRepo` and `WorkItem` surfaces instead of living as free-floating chat state.
- Keep short-term collaboration context bounded and explainable. Referenced files, accepted tool results, and pending clarification state should remain explicit enough to steer follow-up work without turning conversations into hidden long-term memory.

## Day-To-Day Commands

```bash
mix setup               # deps, ecto.setup, and asset build
mix assets.setup        # install browser toolchain dependencies
mix assets.build        # build the Vite + SSR browser bundle
mix frontend.verify     # run the repo-owned browser pipeline verification
mix source_graph.verify # run the repo-owned semantic graph verification suite
mix memory.verify       # verify the ontology pair, typed governed links, and repo-owned memory recovery path
mix semantic.verify     # run the full product-facing semantic graph verification suite
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
- [`docs/developer/README.md`](docs/developer/README.md) for the numbered developer architecture guide set; these guides are explanatory and point back to `.spec` as the current-truth source
- [`CONTRIBUTING.md`](CONTRIBUTING.md) for contributor setup and quality expectations
- [`memory_ontology_guide.md`](memory_ontology_guide.md) for the developer-facing explanation of the coding memory ontology
- [`tauri/README.md`](tauri/README.md) for the separate desktop packaging/runtime path
- [`CHANGELOG.md`](CHANGELOG.md) for release history
- [`AGENTS.md`](AGENTS.md) for local agent operating guidance in this repo

The durable architecture and product-shaping decisions live in [`.spec/decisions/`](.spec/decisions/), especially:

- [`.spec/decisions/jido_code.runic_execution_model.md`](.spec/decisions/jido_code.runic_execution_model.md)
- [`.spec/decisions/jido_code.vsm_recursion_and_scope.md`](.spec/decisions/jido_code.vsm_recursion_and_scope.md)
- [`.spec/decisions/jido_code.local_developer_workflow.md`](.spec/decisions/jido_code.local_developer_workflow.md)

## Semantic Memory

The repository semantic stack is now three linked named graphs in one
repository-local store:

- `source_code` for repository structure and semantic code entities
- `workflow_provenance` for bounded work sessions, agent runs, tool use, plans,
  patches, and reviews
- `memory` for durable adopted facts, decisions, conventions, issues, lessons,
  and patterns

The write seam is explicit:

- workflow provenance is inserted at `AgentWorkspace` and product workflow
  boundaries through typed capture envelopes
- durable memory is inserted only after explicit classification or governed
  adoption
- raw runtime or model output is not durable memory on its own

The verification and cutover seam is explicit too:

- `mix memory.verify` checks the companion ontology pair, typed governed-link
  adoption, repository-local graph coherence, and bounded rebuild or
  revalidation behavior
- new memory and provenance code should emit typed `governed_references`
  directly; generic artifact-style governed links are legacy recovery-only
  state, not the contract for new work
- governed truth still lives in Ash-backed control-plane records such as
  `ManagedRepo`, `WorkItem`, `Run`, `Evidence`, and governed `Decision`; the
  semantic graphs store supporting recall, provenance, and cross-links

When touching the memory graph boundary, capture envelopes, memory actions,
memory workspace entrypoints, or provenance or durable-memory adoption flows,
run `mix memory.verify`.

For operational guidance on configuration, troubleshooting, and production
deployment of the memory graph capability, see the
[Memory Graph Operations Guide](.spec/planning/memory_graph_operations.md).

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
