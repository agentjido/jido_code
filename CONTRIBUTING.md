# Contributing to JidoCode

<!-- covers: package.jido_code.version_controlled_quality_surfaces -->

Thank you for your interest in contributing to JidoCode! This document provides guidelines for contributing.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/mikehostetler/jido_code.git
   cd jido_code
   ```

2. Install the repo toolchain:
   ```bash
   asdf install
   ```

3. Start PostgreSQL locally.

   Normal contributor development uses the defaults from `config/dev.exs` and `config/test.exs`:

   - `localhost:5432`
   - username/password `postgres` / `postgres`
   - databases `jido_code_dev` and `jido_code_test*`

4. Install dependencies and set up the development database:
   ```bash
   mix setup
   ```

5. Start the development server:
   ```bash
   mix server
   ```

For day-to-day development:

- `mix assets.setup` installs the Vite and LiveVue browser dependencies
- `mix assets.build` builds the current browser bundle and SSR output
- `mix frontend.verify` runs the repo-owned browser pipeline verification
- `mix source_graph.verify` runs the repo-owned semantic source-code graph verification suite
- `mix memory.verify` verifies the ontology pair, typed governed links, and the repo-owned memory recovery path
- `mix semantic.verify` runs the full product-facing semantic graph verification suite
- `mix server` is the preferred local start path and prepares browser deps or builds when the LiveVue/Vite output is missing
- `mix test` provisions the test database and runs the test suite
- `mix ecto.reset` drops, recreates, migrates, and seeds the local development database
- `mix onboarding.reset --keep-owner` rewinds onboarding to signed-in `/setup` while preserving the bootstrap owner and clearing imported managed repos
- `mix onboarding.reset --full` returns the install to first-run bootstrap and clears local bootstrap users plus imported managed repos
- `mix spec.prime --base HEAD`, `mix spec.next`, `mix spec.check --base origin/main`, and `mix spec.status` are the repo-local `spec_led_ex` commands for `.spec/`
- `tauri/README.md` is only for desktop packaging/runtime work, not the normal contributor path

Ash resource changes are explicit in this workspace. Browser requests do not
auto-run Ash codegen or migrations. When resource DSL changes require generated
files, run `mix ash.codegen --dev` while iterating and `mix ash.codegen <name>`
before you finalize the change set.

## Route Orientation

Keep the routed entry contract explicit in product code and tests:

- `/welcome` is the public/bootstrap and sign-in entry route
- `/setup` is the signed-in continuation surface while onboarding is incomplete
- `/dashboard` is the durable ready-state authenticated landing
- `/settings/auth` is the durable home for Provider Login and Git Provider Integrations

## Canonical Repo And Run Terms

New product code, tests, and docs should default to `SourceRepo`,
`ManagedRepo`, and governed `Run` terminology.

- Use shared helpers such as `provision_managed_repo!/1` and
  `create_governed_run!/2` for greenfield test setup.
- Keep `Project` and `WorkflowRun` references limited to explicit
  compatibility, migration, or audit coverage, and label those cases clearly.

## Source Code Graph Capability

The repository-scoped semantic graph stack uses `elixir_ontologies`,
`triple_store`, `sparql`, and `rocksdb`.

- The canonical named graph is `source_code`.
- Repository-local graph data lives under `.jido_code/source_code_graph/triple_store`.
- Normal workflow is explicit: analyze, load or refresh, then query.
- If you touch the semantic graph boundary, actions, pod agents, or repository
  workspace entrypoints, run `mix source_graph.verify`.
- If you touch memory graph boundaries, capture envelopes, memory actions,
  memory workspace entrypoints, workflow provenance capture, or durable-memory
  adoption flows, run `mix memory.verify`.
- If you touch product-facing semantic services, semantic operator UI, semantic
  workflow entrypoints, or governed semantic-finding adoption, run
  `mix semantic.verify`.

Reach for the semantic graph when you need repository-wide semantic structure
such as module discovery, function discovery, impact tracing, runtime-pattern
lookups, or repeated SPARQL-backed questions. Prefer normal file/code tools when
you need exact latest source text, line-level editing context, or trivial
single-file inspection.

Treat the semantic graph as a bounded enhancement rather than a required
product dependency:

- keep semantic freshness, stale state, and recovery visible in operator-facing
  behavior
- let planning, review, and explanation opt into semantic context explicitly
- route semantic findings back into governed records before they change product
  behavior

The memory graph follows the same bounded rule:

- provenance enters through explicit typed envelopes at `AgentWorkspace` and
  product workflow seams
- durable memory enters only after explicit classification or governed adoption
- raw runtime output, prompt text, or agent output is not durable memory unless
  a bounded product path adopts it
- new governed links should use typed `governed_references` directly instead of
  introducing fresh generic artifact-path contracts
- generic artifact-style governed links now count as legacy recovery-only store
  state and should be rebuilt or revalidated instead of extended
- governed product records remain the canonical Ash-backed truth; memory and
  provenance graphs store supporting semantic context and navigation only

Use `mix memory.verify` when this stack changes to confirm:

- the companion ontology pair is present
- typed governed links have replaced legacy governed-artifact semantics
- repository-local rebuild or revalidation still recovers older graph state cleanly

## Code Quality

Before submitting a PR, ensure all quality checks pass:

```bash
mix q
```

This runs:
- `mix deps.unlock --check-unused` - Dependency hygiene check
- `mix format --check-formatted` - Code formatting check
- `mix deps.compile` - Dependency compilation sanity check
- `mix compile --warnings-as-errors` - Compilation with strict warnings
- `mix credo --min-priority higher` - Standards-aligned static code analysis

For broader local quality review while the repo carries existing Dialyzer and Doctor debt:

```bash
mix quality
```

This extends `mix q` with:
- `mix frontend.verify` - LiveVue/Vite/SSR pipeline verification
- `mix source_graph.verify` - repository-scoped semantic graph verification
- `mix memory.verify` - repository-scoped memory graph and capture-plane verification
- `mix semantic.verify` - product-facing semantic workflow and UI verification
- `mix doctor --raise` - Documentation coverage check
- `mix dialyzer` - Broader static type analysis

For running tests with coverage:

```bash
mix coveralls
mix coveralls.html
```

The repo-local package-quality baseline is expressed through `mix.exs`, this guide, the top-level `README.md`, and the current-truth subjects under `.spec/`.

## Frontend Conventions

The routed browser shell stays LiveView-first. Reach for Vue only when a surface genuinely needs richer client-side composition than HEEx plus lightweight hooks can comfortably support.

- Keep pages and route ownership in LiveView and mount Vue through `<.vue_surface ...>` rather than raw `<.vue ...>` calls.
- Treat `props:` as server-authored data from LiveView. If a Vue surface needs LiveView streams, pass them through `streams:` so diff behavior stays intact.
- Map Vue emits back into LiveView with `events: %{"emit-name" => "live_view_event"}` or explicit `Phoenix.LiveView.JS` values instead of letting Vue own the workflow.
- Use the `JidoCodeWeb.LiveVueCase` helpers only on screens that actually mount Vue. Plain LiveView routes should keep using the normal `Phoenix.LiveViewTest` path.
- Keep degraded frontend behavior product-oriented. If a Vue surface cannot load or SSR is reduced, the page should fall back to bounded LiveView fallback messaging rather than raw Vite, SSR, or manifest errors.
- Run `mix frontend.verify` whenever a change touches `live_vue`, shared browser helpers, Vite config, SSR entrypoints, or the root browser dependency surface.

## Conversation Conventions

Conversation work in this repo is product work, not a parallel chat lane.

- Keep conversations bound to an explicit `ManagedRepo` and, when durable work is in play, to one canonical `WorkItem`.
- Prefer the event-driven conversation path. Live updates should flow through the product-owned conversation event stream, with snapshots reserved for bootstrap, reconnect recovery, and degraded continuity instead of polling-first UI.
- Treat repo detail as the canonical productive-conversation host. Workbench, governed run detail, and dashboard should only project bounded supervision state and link back rather than introducing page-local transcript or composer ownership.
- Treat `turn.steer`, `turn.stop`, `tool.cancel`, pause, and resume as explicit control-lane commands rather than ad hoc message priorities or browser-local state.
- When a conversation redirects or promotes work, send that demand back through the governed work loop so `WorkItem` auditability stays canonical.
- Keep provider/model readiness, workspace prerequisites, and degraded continuity visible in the route-owned shell instead of burying them in raw runtime metadata.
- Keep short-term shared context bounded and explainable. Referenced files, accepted tool results, and pending clarification state may inform steering, but they should remain visible, product-shaped context rather than hidden memory.

## Commit Messages

We follow [Conventional Commits](https://www.conventionalcommits.org/):

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

### Types

| Type | Description |
|------|-------------|
| `feat` | New feature |
| `fix` | Bug fix |
| `docs` | Documentation changes |
| `style` | Formatting, no code change |
| `refactor` | Code change, no fix or feature |
| `perf` | Performance improvement |
| `test` | Adding/fixing tests |
| `chore` | Maintenance, deps, tooling |
| `ci` | CI/CD changes |

### Examples

```bash
git commit -m "feat(accounts): add API key management"
git commit -m "fix: resolve timeout in async operations"
git commit -m "docs: update installation instructions"
```

## Pull Request Process

1. Fork the repository
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Make your changes
4. Run merge-safe quality checks: `mix q`
5. If you touched the browser stack, run `mix frontend.verify`
6. Run tests: `mix coveralls`
7. Commit using conventional commits
8. Push and open a Pull Request

## Release Workflow

Release automation is kept in `.github/workflows/release.yml` and should remain the source of truth for maintainers. Prepare releases from repository state by updating `CHANGELOG.md`, verifying `mix q`, `mix coveralls`, and the relevant spec checks, then running the version-controlled GitHub workflow instead of relying on undocumented local release steps. Use `mix quality` as the broader local debt-surfacing pass when working through Dialyzer- or Doctor-sensitive changes.

## Reporting Issues

When reporting issues, please include:

- Elixir/OTP version (`elixir --version`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

## Code of Conduct

Be respectful and inclusive. We're all here to build something great together.
