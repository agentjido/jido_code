# AgentJido

[![CI](https://github.com/agentjido/agent_jido/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/agent_jido/actions/workflows/ci.yml)

AgentJido is a Phoenix 1.8 application for the Jido AI agent ecosystem.

## Features

- **Phoenix 1.8** with LiveView for real-time UI
- **Ash Framework** for data modeling and business logic
- **Authentication** via Ash Authentication
- **PostgreSQL** for persistence
- **Tailwind CSS v4** for modern styling

## Installation

### Prerequisites

- Elixir 1.18+
- PostgreSQL 14+
- Node.js 18+ (for asset compilation)

### Setup

```bash
# Clone the repository
git clone https://github.com/agentjido/agent_jido.git
cd agent_jido

# Install JavaScript dependencies
cd assets && npm install && cd ..

# Install Elixir dependencies and setup database
mix setup

# Start the Phoenix server
mix phx.server
```

Now visit [`localhost:4000`](http://localhost:4000) from your browser.

## Development

### Commands

```bash
# Run all quality checks
mix quality

# Run tests
mix test

# Run tests with coverage
mix coveralls.html

# Pre-commit checks
mix precommit
```

### Quality Checks

The `quality` alias runs:
- `mix compile --warnings-as-errors` - Strict compilation
- `mix format --check-formatted` - Code formatting
- `mix credo --strict` - Static analysis
- `mix doctor --raise` - Documentation coverage

## Project Structure

```
lib/
├── agent_jido/              # Core business logic
│   ├── accounts.ex          # User accounts domain
│   ├── error.ex             # Centralized error handling
│   └── repo.ex              # Database repository
├── agent_jido_web/          # Web layer
│   ├── components/          # Reusable UI components
│   ├── controllers/         # HTTP controllers
│   └── live/                # LiveView modules
└── agent_jido.ex            # Application entry
```

## Documentation

- [CONTRIBUTING.md](CONTRIBUTING.md) - Contribution guidelines
- [CHANGELOG.md](CHANGELOG.md) - Version history

## License

Apache-2.0 - see [LICENSE](LICENSE) for details.
