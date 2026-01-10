# LLMAgent Redesign - Strategy-Agentic Architecture

**Date:** 2025-01-09
**Status:** Design Phase
**Branch:** `feature/section2.1-v2-skill-integration`

## Overview

Redesign `JidoCode.Agents.LLMAgent` from a GenServer-based agent using JidoAI v1 APIs to a `Jido.Agent`-based agent using JidoAI v2 strategies. This enables pluggable reasoning algorithms (ReAct, CoT, ToT, GoT, Adaptive) while preserving all existing functionality.

## Current Architecture (v1 - Being Replaced)

```
LLMAgent (GenServer, 1526 lines)
├── Jido.AI.Agent (v1) - LLM interaction
├── Jido.AI.Keyring (deprecated) - API keys
├── Jido.AI.Model (deprecated) - Model management
├── Jido.AI.Model.Registry (deprecated) - Provider/Model listing
├── Jido.AI.Prompt (deprecated) - Prompt construction
├── Memory integration - ContextBuilder, ResponseProcessor
└── Tools.Executor - Tool execution
```

### Issues with Current Design

1. **Hardcoded algorithm** - Only ReAct pattern available
2. **Deprecated APIs** - Uses JidoAI v1 modules that no longer exist
3. **Monolithic** - All logic in one GenServer (1526 lines)
4. **Tight coupling** - LLM interaction, memory, tools all intertwined

## New Architecture (v2 - Proposed)

```
LLMAgent (Jido.Agent-based)
├── Strategy (pluggable)
│   ├── Jido.AI.Strategies.Adaptive (default)
│   ├── Jido.AI.Strategies.ReAct (optional)
│   ├── Jido.AI.Strategies.ChainOfThought (optional)
│   ├── Jido.AI.Strategies.TreeOfThoughts (optional)
│   └── Jido.AI.Strategies.GraphOfThoughts (optional)
├── Skills (modular capabilities)
│   ├── Jido.AI.Skills.LLM - Core LLM actions (Chat, Complete, Embed)
│   ├── Jido.AI.Skills.Streaming - Response streaming
│   ├── Jido.AI.Skills.ToolCalling - Tool/function calling
│   ├── JidoCode.Memory.Skill - Memory integration
│   ├── JidoCode.Extensibility.Skills.Permissions - Permission checking
│   └── JidoCode.Extensibility.Skills.ChannelBroadcaster - PubSub broadcasting
└── Actions (JidoCode-specific)
    ├── Chat - Send message and get response
    ├── ChatStream - Send message with streaming response
    └── SetStrategy - Change reasoning strategy
```

## Mapping Current Features to New Architecture

| Current Feature | New Implementation |
|----------------|-------------------|
| **Session management** | Agent state schema field |
| **Memory integration** | `JidoCode.Memory.Skill` |
| **Tool execution** | `Jido.AI.Skills.ToolCalling` + `JidoCode.Tools` actions |
| **Streaming responses** | `Jido.AI.Skills.Streaming` |
| **PubSub broadcasting** | `JidoCode.Extensibility.Skills.ChannelBroadcaster` |
| **LLM configuration** | `Jido.AI.Config` + agent state |
| **Progress tracking** | Agent state schema fields |
| **System prompt** | Strategy config or skill state |

## Agent Schema Definition

```elixir
schema: [
  # Session
  session_id: [type: :string, default: nil],

  # LLM Configuration
  provider: [type: :atom, default: :anthropic],
  model: [type: :string, default: "anthropic:claude-sonnet-4-20250514"],
  temperature: [type: :float, default: 0.7],
  max_tokens: [type: :integer, default: 4096],

  # Memory
  memory_enabled: [type: :boolean, default: true],
  token_budget: [type: :integer, default: 32_000],

  # Status
  status: [type: :atom, default: :idle],
  progress: [type: :float, default: 0.0],
  last_answer: [type: :string, default: ""],

  # Strategy
  current_strategy: [type: :atom, default: :adaptive]
]
```

## Strategy Configuration

```elixir
strategy: {
  Jido.AI.Strategies.Adaptive,
  model: "anthropic:claude-sonnet-4-20250514",
  default_strategy: :react,
  available_strategies: [:cot, :react, :tot, :got, :trm],
  # JidoCode-specific additions
  tools: [
    # File operations
    JidoCode.Tools.Actions.ReadFile,
    JidoCode.Tools.Actions.WriteFile,
    JidoCode.Tools.Actions.EditFile,
    JidoCode.Tools.Actions.ListDirectory,
    # Search
    JidoCode.Tools.Actions.Grep,
    JidoCode.Tools.Actions.FindFiles,
    # Commands
    JidoCode.Tools.Actions.RunCommand,
    # Memory (if enabled)
    JidoCode.Memory.Actions.Remember,
    JidoCode.Memory.Actions.Recall,
    JidoCode.Memory.Actions.Forget
  ],
  system_prompt: JidoCode.Agents.LLMAgent.system_prompt()
}
```

## Skills Configuration

```elixir
skills: [
  # Core LLM capabilities
  {Jido.AI.Skills.LLM, [
    default_model: :capable,
    default_max_tokens: 4096
  ]},

  # Streaming support
  {Jido.AI.Skills.Streaming, [
    pubsub: JidoCode.PubSub,
    topic_builder: &JidoCode.PubSubTopics.llm_stream/1
  ]},

  # Tool calling with JidoCode tools
  {Jido.AI.Skills.ToolCalling, [
    tool_registry: JidoCode.Tools.Registry
  ]},

  # Memory integration
  {JidoCode.Memory.Skill, [
    enabled: true,
    token_budget: 32_000
  ]},

  # Permissions (from extensibility)
  {JidoCode.Extensibility.Skills.Permissions, [
    agent_name: :llm_agent
  ]},

  # Channel broadcasting (from extensibility)
  {JidoCode.Extensibility.Skills.ChannelBroadcaster, [
    agent_name: :llm_agent,
    auto_connect: true
  ]}
]
```

## Public API Preservation

All existing public API functions will be preserved with the same signatures:

```elixir
# Starting
LLMAgent.start_link(opts)
LLMAgent.via(session_id)

# Chat
LLMAgent.chat(pid, message, opts)
LLMAgent.chat_stream(pid, message, opts)

# Configuration
LLMAgent.configure(pid, opts)
LLMAgent.get_config(pid)

# Session info
LLMAgent.get_session_info(pid)
LLMAgent.get_status(pid)
LLMAgent.topic_for_session(session_id)

# Tools
LLMAgent.get_available_tools(pid)
LLMAgent.execute_tool(pid, tool_call)
LLMAgent.execute_tool_batch(pid, tool_calls, opts)

# NEW: Strategy selection
LLMAgent.set_strategy(pid, strategy)
LLMAgent.get_strategy(pid)
LLMAgent.list_strategies()
```

## Implementation Phases

### Phase 1: Core Agent Structure
- [ ] Create new LLMAgent using `Jido.Agent`
- [ ] Define agent schema
- [ ] Set up Adaptive strategy with tools
- [ ] Implement basic chat functionality

### Phase 2: Memory Integration
- [ ] Create `JidoCode.Memory.Skill`
- [ ] Port ContextBuilder logic to skill
- [ ] Port ResponseProcessor logic to skill
- [ ] Integrate memory tools (remember, recall, forget)

### Phase 3: Streaming and PubSub
- [ ] Integrate `Jido.AI.Skills.Streaming`
- [ ] Hook up PubSub events (stream_chunk, stream_end, stream_error)
- [ ] Integrate ChannelBroadcaster skill

### Phase 4: Permissions and Extensibility
- [ ] Integrate Permissions skill
- [ ] Add permission checks to tool actions
- [ ] Integrate ChannelBroadcaster for event broadcasting

### Phase 5: Client API Compatibility
- [ ] Implement all public API functions
- [ ] Preserve backward compatibility
- [ ] Add new strategy selection APIs

### Phase 6: Testing and Documentation
- [ ] Write comprehensive tests
- [ ] Update documentation
- [ ] Update examples and guides

## Signal Flow

```
User: LLMAgent.chat(pid, "Explain pattern matching")
       ↓
AgentServer.call/3 with signal
       ↓
Agent.cmd/2 routes to :llm_chat action
       ↓
LLM action processes message
       ↓
Strategy (Adaptive) selects ReAct
       ↓
ReAct strategy initiates LLM call
       ↓
ReqLLM returns response
       ↓
StreamChunk events → Streaming skill
       ↓
PubSub broadcasts to TUI
       ↓
Final answer stored in agent.state.last_answer
```

## Benefits

1. **Pluggable algorithms** - Switch between ReAct, CoT, ToT, GoT at runtime
2. **Better modularity** - Skills are composable and reusable
3. **Future-proof** - New strategies can be added without changing agent code
4. **Cleaner code** - Less monolithic, easier to understand and maintain
5. **Signal-based** - Better integration with Jido v2 ecosystem
6. **Testable** - Each skill can be tested independently

## Backward Compatibility

The new implementation will maintain full backward compatibility:

- Same public API with identical function signatures
- Same PubSub event formats
- Same configuration options
- Same behavior for all existing use cases

New capabilities are additive (strategy selection, new algorithms).
