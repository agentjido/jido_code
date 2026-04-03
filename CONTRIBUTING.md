# Contributing to JidoCode

Thank you for your interest in contributing to JidoCode! This document provides guidelines for contributing.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/epic-creative/jido_code.git
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
   mix phx.server
   ```

For day-to-day development:

- `mix assets.setup` installs the Vite and LiveVue browser dependencies
- `mix assets.build` builds the current browser bundle and SSR output
- `mix frontend.verify` runs the repo-owned browser pipeline verification
- `mix test` provisions the test database and runs the test suite
- `mix ecto.reset` drops, recreates, migrates, and seeds the local development database
- `mix spec.prime --base HEAD`, `mix spec.next`, `mix spec.check --base origin/main`, and `mix spec.status` are the repo-local `spec_led_ex` commands for `.spec/`
- `tauri/README.md` is only for desktop packaging/runtime work, not the normal contributor path

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
- Keep degraded frontend behavior product-oriented. If a Vue surface cannot load or SSR is reduced, the page should fall back to bounded LiveView compatibility messaging rather than raw Vite, SSR, or manifest errors.
- Run `mix frontend.verify` whenever a change touches `live_vue`, shared browser helpers, Vite config, SSR entrypoints, or the root browser dependency surface.

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
