# Extensibility System Implementation Overview

The JidoCode extensibility system provides a Phoenix channel-integrated plugin architecture that maps ClaudeCode patterns to Jido v2 primitives.

## Architecture

```
┌────────────────────────────────────────────────────────────────────┐
│                     Extensibility System                            │
├────────────────────────────────────────────────────────────────────┤
│  Slash Commands  │  Sub-Agents  │  Skills  │  Hooks  │  Plugins     │
│  (Jido.Actions)  │  (Jido.Agent)│         │         │              │
├────────────────────────────────────────────────────────────────────┤
│                    Jido.Signal.Bus (CloudEvents)                   │
├────────────────────────────────────────────────────────────────────┤
│                   Phoenix Channels (Real-time)                      │
└────────────────────────────────────────────────────────────────────┘
```

## Design Document

See `../../research/1.03-extensibility-system/1.03.1-commands-agents-skills-plugins.md` for the complete design specification.

## Implementation Phases

| Phase | Description | Status |
|-------|-------------|--------|
| 1 | Configuration & Settings | Pending |
| 2 | Signal Bus Integration | Pending |
| 3 | Hook System | Pending |
| 4 | Command System | Pending |
| 5 | Plugin Registry | Pending |
| 6 | Sub-Agent System | Pending |
| 7 | Skills Framework | Pending |
| 8 | Phoenix Channels | Pending |
| 9 | TermUI Integration | Pending |

## Key Dependencies

- **Jido v2**: Pure-functional Agent API with `cmd/2` returning `{agent, directives}`
- **JidoSignal.Bus**: CloudEvents v1.0.2 compliant signal bus with path-based routing
- **Phoenix Channels**: Real-time bidirectional communication
- **Zoi**: Schema validation (v2 replaces NimbleOptions)

## Directory Structure

```
lib/jido_code/extensibility/
├── channel_config.ex          # Phoenix channel configuration
├── permissions.ex             # Permission system
├── bus_supervisor.ex          # Signal bus supervision
├── dispatch/                  # Dispatch adapters
│   ├── phoenix_channel.ex
│   ├── pubsub_ex.ex
│   └── hook.ex
├── signals/                   # Signal type definitions
│   ├── lifecycle.ex
│   ├── tool.ex
│   └── command.ex
├── hooks/                     # Hook system
│   ├── hook.ex
│   ├── registry.ex
│   ├── runner.ex
│   └── decision.ex
├── parser/                    # Markdown parsers
│   └── frontmatter.ex
├── command.ex                 # Slash command definitions
├── command_registry.ex
├── command_dispatcher.ex
├── plugin/                    # Plugin system
│   ├── manifest.ex
│   ├── registry.ex
│   ├── loader.ex
│   └── marketplace.ex
├── sub_agent.ex               # Sub-agent definitions
├── agent_registry.ex
├── agent_executor.ex
├── skill.ex                   # Skill definitions
├── skill_registry.ex
├── skill_router.ex
├── socket.ex                  # Phoenix socket
├── channels/                  # Channel handlers
│   ├── agent_state.ex
│   └── ui_events.ex
└── signal_bridge.ex           # Bus → Channel bridge
```

## Configuration Directories

```
~/.jido_code/                          # Global configuration
├── settings.json                      # Global settings + hooks
├── commands/                          # Personal slash commands
├── agents/                            # Personal sub-agent definitions
├── skills/                            # Personal skills
├── plugins/                           # Installed plugins
└── hooks/                             # Native Elixir hook modules

.jido_code/                            # Project-level configuration
├── settings.json                      # Project settings (overrides global)
├── commands/
├── agents/
├── skills/
└── hooks/
```

## Testing Strategy

Each phase includes:
- **Unit tests** for individual components
- **Integration tests** for phase completion
- **80%+ code coverage target**

## Success Criteria

- [ ] ClaudeCode-compatible markdown definitions work
- [ ] Native Elixir hooks execute on lifecycle events
- [ ] Phoenix channels broadcast real-time updates
- [ ] Plugins can be loaded, enabled, and disabled
- [ ] Sub-agents use Jido v2 pure-functional API
- [ ] Skills compose actions with path-based routing
- [ ] TermUI displays extensibility state
- [ ] All tests pass with 80%+ coverage
