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
   mise install
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

- `mix test` provisions the test database and runs the test suite
- `mix ecto.reset` drops, recreates, migrates, and seeds the local development database
- `mix spec.verify --debug`, `mix spec.check`, and `mix spec.diffcheck` are the repo-local `spec_led_ex` checks for `.spec/`
- `tauri/README.md` is only for desktop packaging/runtime work, not the normal contributor path

## Code Quality

Before submitting a PR, ensure all quality checks pass:

```bash
mix q
```

This runs:
- `mix format --check-formatted` - Code formatting check
- `mix compile --warnings-as-errors` - Compilation with strict warnings
- `mix credo --min-priority higher` - Standards-aligned static code analysis
- `mix dialyzer` - Static type analysis
- `mix doctor --raise` - Documentation coverage check

For running tests with coverage:

```bash
mix coveralls
mix coveralls.html
```

The canonical package-quality comparison for this repo lives in [`docs/PACKAGE_QUALITY_ALIGNMENT.md`](docs/PACKAGE_QUALITY_ALIGNMENT.md).

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
4. Run quality checks: `mix quality`
5. Run tests: `mix coveralls`
6. Commit using conventional commits
7. Push and open a Pull Request

## Release Workflow

Release automation is kept in `.github/workflows/release.yml` and should remain the source of truth for maintainers. Prepare releases from repository state by updating `CHANGELOG.md`, verifying `mix q`, `mix coveralls`, and the relevant spec checks, then running the version-controlled GitHub workflow instead of relying on undocumented local release steps.

## Reporting Issues

When reporting issues, please include:

- Elixir/OTP version (`elixir --version`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

## Code of Conduct

Be respectful and inclusive. We're all here to build something great together.
