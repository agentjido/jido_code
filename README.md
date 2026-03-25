# Jido.Code (alpha)

[![CI](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml/badge.svg)](https://github.com/epic-creative/jido_code/actions/workflows/ci.yml)

Jido.Code is an **Elixir/Phoenix + LiveView** application exploring a practical "AI coding orchestrator" built on the [Jido](https://github.com/agentjido/jido) agent runtime.

Today, the repo contains two substantial, working showcases:

1. **Forge** — a production-quality OTP subsystem for running **isolated, observable execution sessions** (via [Sprites](https://fly.io) sandboxes or a local fake client) with pluggable runners, iteration control, persistence, and a real streaming terminal UI.

2. **GitHub Issue Bot** — a real multi-agent system demonstrating Jido patterns (coordination, fan-out, signal routing) for issue triage, research, and PR planning — currently as agent code + a debug CLI runner, not yet wired into the web UI as a product feature.

> **Status: alpha / developer-focused.** Several documents in [`./specs`](specs/) describe an intended product direction; this README is intentionally limited to what exists in the codebase today.

The repo aligns to the canonical Jido package quality standards where they apply to a product repo and documents the remaining exceptions in [`docs/PACKAGE_QUALITY_ALIGNMENT.md`](docs/PACKAGE_QUALITY_ALIGNMENT.md).

---

## What Works Today

### Forge: Sandbox Sessions with Streaming UI

Forge is a parallel execution subsystem with proper OTP structure:

- **Public API** (`JidoCode.Forge`): `start_session`, `stop_session`, `exec`, `cmd`, `run_loop`, `run_iteration`, `apply_input`, `resume`, `cancel`, `create_checkpoint`
- **Lifecycle management** (`Forge.Manager`): `DynamicSupervisor` + `Registry`, concurrency limits (default 50 total, per-runner limits)
- **Per-session runtime** (`Forge.SpriteSession`): GenServer handling provision → bootstrap → init runner → iterate → input → cleanup
- **Runner behaviour** (`Forge.Runner`): iteration statuses `:continue`, `:done`, `:needs_input`, `:blocked`, `:error`
- **Built-in runners**:
  - `ClaudeCode` — complete Claude Code CLI runner with `--output-format stream-json` parsing
  - `Shell` — shell command runner
  - `Workflow` — data-driven step runner
  - `Custom` — user-provided runner
- **Sprite clients**: `Live` (real Sprites SDK) and `Fake` (dev/test)
- **Persistence + observability**: Ash resources for session events, PubSub broadcasting on `forge:sessions` and `forge:session:<id>`
- **LiveView UI**: session list, creation form, and a real terminal UI with streaming output, iteration controls, input prompts, and colocated JS hooks for scrolling + command history

See [`specs/FORGE_OVERVIEW.md`](specs/FORGE_OVERVIEW.md) for the full architecture.

### GitHub Issue Bot: Multi-Agent Jido Showcase

Agent code implementing an issue lifecycle pipeline:

- `CoordinatorAgent` drives: `issue.start` → triage → research → PR
- **Research fan-out**: `ResearchCoordinator` with 4 parallel workers (CodeSearch, PRSearch, Reproduction, RootCause)
- **PR fan-out**: `PullRequestCoordinator` with 3 workers (Patch, Quality, PRSubmit)
- Each worker has its own agent + action module
- Uses Jido signal routing, fan-out coordination, and directive patterns
- Includes a CLI runner for debugging

### GitHub Domain

- `GitHub.Repo` (AshPostgres) with code interface for CRUD + enable/disable
- `GitHub.WebhookDelivery` — persisted webhook payloads
- `GitHub.IssueAnalysis` — persisted analyses
- `GitHub.WebhookSensor` — polls pending deliveries and emits Jido signals (e.g. `github.issues.opened`)

### Folio: GTD Task Manager Demo

A separate demo domain showcasing `Jido.AI.ReActAgent`:

- `Folio.Project`, `InboxItem`, `Action` resources (ETS data layer)
- `FolioAgent` — ReActAgent with ~15 tools, `model: :fast`, `max_iterations: 8`
- `FolioLive` — chat-based GTD UI with agent state polling

### Web App + Auth

- Phoenix 1.8 + LiveView with AshAuthentication (password, magic link, API key)
- Authenticated routes: `/forge/*`, `/folio`, `/settings`, `/dashboard`, `/demos/chat`
- `SettingsLive` — tabbed UI managing GitHub repos via `AshPhoenix.Form`
- Tailwind v4 + DaisyUI theme system with core Phoenix components
- JSON:API endpoints + Swagger UI at `/api/json`
- Health check at `GET /status`

---

## What Is Not Implemented (Yet)

- No onboarding wizard or first-run flow
- No `SystemConfig`, credential resources, or centralized settings store
- No Runic workflow engine integration
- No git operations, branch/commit automation, or PR creation in the web product flow
- GitHub Issue Bot is not wired end-to-end (webhooks → repo workspace → Forge → PR)
- `.env.example` does not include several keys you'll need in practice (e.g. `ANTHROPIC_API_KEY`, `SPRITES_API_TOKEN`, GitHub App credentials)
- Dashboard is a stub
- Test coverage is sparse (9 test files, mostly Issue Bot + controller tests)

See [`specs/03_decisions_and_invariants.md`](specs/03_decisions_and_invariants.md) and [`specs/02_requirements_and_scope.md`](specs/02_requirements_and_scope.md) for the canonical planning baseline.

---

## Product Vision

The intended direction (documented in [`specs/`](specs/)):

- **Onboarding wizard** — configure API keys, GitHub App, and environment on first run
- **Project import** — clone repos to local workspaces or Sprite sandboxes
- **Durable workflows** — Runic DAG-based pipelines (plan → implement → test → approve → ship)
- **Human approval gates** — nothing ships without review
- **Auto commit + PR** — branch, commit, push, and open PRs automatically
- **Webhook-triggered agents** — automated issue triage and research
- **Real-time observability** — execution timelines, cost tracking, artifact browsing

---

## Local Development

### Prerequisites
- Elixir `~> 1.18`
- PostgreSQL 14+

The repo toolchain is pinned in `mise.toml`. If you use `mise`, install the local toolchain with:

```bash
mise install
```

### Setup
```bash
git clone https://github.com/epic-creative/jido_code.git
cd jido_code

mise install
mix setup
mix phx.server
```

Visit http://localhost:4000

### Environment Variables

`.env.example` currently includes:
- `SECRET_KEY_BASE`, `PORT`, `PHX_HOST`, `CANONICAL_HOST`
- `RESEND_API_KEY`, `MAILER_FROM_EMAIL`

Depending on what you run, you may also need:
- `ANTHROPIC_API_KEY` — for the Claude Code runner
- `SPRITES_API_TOKEN` — for the live Sprites client
- GitHub App, broker, and PAT settings — documented in the operator guide below

For the current self-hosted provider-login and GitHub automation model, use the operator guide:

- [`docs/self_hosted_provider_auth.md`](docs/self_hosted_provider_auth.md)

### Commands
```bash
mix q                   # Shorthand for the canonical quality gate
mix test                # Run tests
mix coveralls           # Run tests with coverage summary
mix quality             # Deps hygiene + format + compile + credo + dialyzer + doctor
mix precommit           # Compile + format + test
mix coveralls.html      # Coverage report
mix docs                # Build docs including package-quality alignment notes
```

### Release Workflow

Release automation is version-controlled in `.github/workflows/release.yml`. Maintainers should keep `CHANGELOG.md` current, ensure `mix q`, `mix coveralls`, and the relevant spec checks pass, then use the GitHub workflow to cut a tagged release from repository state instead of relying on ad hoc local release commands.

### Jido CLI Wrapper
```bash
# from repo root (wrapper script)
./jidocode --skills

# equivalent explicit path
bin/jidocode --skills
bin/jidocode --skill list
bin/jidocode --skill run my-skill --route my/route --data '{"key":"value"}'

bin/jidocode --commands
bin/jidocode --command my-command --params '{"key":"value"}'

bin/jidocode --workflows
bin/jidocode --workflow my_workflow -file_path lib/example.ex -mode full
```

---

## Architecture

```
lib/
├── jido_code/                  # Core business logic
│   ├── accounts/               # AshAuthentication (User, Token, ApiKey)
│   ├── forge/                  # Sandbox execution engine
│   │   ├── runners/            # Shell, ClaudeCode, Workflow, Custom
│   │   ├── resources/          # Ash resources (Session, Event, Checkpoint, ...)
│   │   ├── sprite_client/      # Fake + Live Sprites clients
│   │   ├── manager.ex          # Lifecycle + concurrency GenServer
│   │   ├── sprite_session.ex   # Per-session GenServer
│   │   ├── operations.ex       # Resume, cancel, checkpoint orchestration
│   │   └── pubsub.ex           # PubSub helpers
│   ├── folio/                  # GTD task manager demo
│   ├── github/                 # GitHub integration (Repo, Webhook, Sensor)
│   └── github_issue_bot/       # Multi-agent issue bot
│       ├── issue_run/          # Coordinator agent + actions
│       ├── triage/             # Triage agent + action
│       ├── research/           # Research coordinator + 4 workers
│       └── pull_request/       # PR coordinator + 3 workers
├── jido_code_web/              # Web layer
│   ├── components/             # Core and app-specific Phoenix UI components
│   ├── live/                   # LiveView modules
│   │   ├── forge/              # Session list, create, show (terminal UI)
│   │   ├── demos/              # Chat demo
│   │   ├── folio_live.ex       # GTD demo
│   │   └── settings_live.ex    # Settings (GitHub repos)
│   └── router.ex               # Routes + AshAuthentication
specs/                          # PRD & design documents
```

### Jido Ecosystem Dependencies

| Package | Role |
|---------|------|
| [`jido`](https://github.com/agentjido/jido) | Agent runtime, strategies, signals |
| [`jido_action`](https://github.com/agentjido/jido_action) | Composable action definitions |
| [`jido_signal`](https://github.com/agentjido/jido_signal) | Agent communication envelopes |
| [`jido_ai`](https://github.com/agentjido/jido_ai) | LLM integration (Anthropic, OpenAI) |
| [`req_llm`](https://github.com/agentjido/req_llm) | HTTP LLM client |
| [`ash`](https://ash-hq.org) | Data modeling, persistence |
| [`sprites`](https://fly.io) | Cloud sandbox containers |

---

## Documentation

<!-- covers: docs.product_foundation.docs_index_present -->

- [`docs/VISION.md`](docs/VISION.md) - product thesis, trust model, and initial scope
- [`docs/TECHNICAL_IMPLEMENTATION.md`](docs/TECHNICAL_IMPLEMENTATION.md) - technical approach, control loop, and Ash domain layout
- [`docs/DATA_ONTOLOGY.md`](docs/DATA_ONTOLOGY.md) - base data ontology for repository control
- [`docs/factory_gaps.md`](docs/factory_gaps.md) - Jido-centric comparison note on what to learn from Factory.ai and where Jido should go further
- [`docs/PACKAGE_QUALITY_ALIGNMENT.md`](docs/PACKAGE_QUALITY_ALIGNMENT.md) - comparison against the canonical Jido package quality standards
- [`docs/README.md`](docs/README.md) - docs index
- [`specs/FORGE_OVERVIEW.md`](specs/FORGE_OVERVIEW.md) — Forge architecture deep dive
- [`specs/`](specs/) — Product specs and PRD
- [`specs/03_decisions_and_invariants.md`](specs/03_decisions_and_invariants.md) — Cross-spec source of truth
- [`docs/self_hosted_provider_auth.md`](docs/self_hosted_provider_auth.md) — Self-hosted provider login and GitHub automation setup
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — Contribution guidelines
- [`CHANGELOG.md`](CHANGELOG.md) — Version history

---

## License

Apache-2.0 — see [LICENSE](LICENSE) for details.
