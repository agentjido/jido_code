# Contributing to JidoCode

Thank you for your interest in contributing to JidoCode! This document provides guidelines for contributing.

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/epic-creative/jido_code.git
   cd jido_code
   ```

2. Install dependencies:
   ```bash
   mix setup
   ```

3. Start the development server:
   ```bash
   mix phx.server
   ```

## Code Quality

Before submitting a PR, ensure all quality checks pass:

```bash
mix quality
```

This runs:
- `mix compile --warnings-as-errors` - Compilation with strict warnings
- `mix format --check-formatted` - Code formatting check
- `mix credo --strict` - Static code analysis
- `mix doctor --raise` - Documentation coverage check

For running tests with coverage:

```bash
mix coveralls.html
```

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
5. Run tests: `mix test`
6. Commit using conventional commits
7. Push and open a Pull Request

## Reporting Issues

When reporting issues, please include:

- Elixir/OTP version (`elixir --version`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant logs or error messages

## Code of Conduct

Be respectful and inclusive. We're all here to build something great together.
