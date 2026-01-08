# Phase 6: Sub-Agent System

This phase implements markdown-based sub-agents with Jido v2 Agent API, channel broadcasting, and signal routing. Sub-agents are specialized AI agents that can be invoked for specific tasks.

## Sub-Agent Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Agent Discovery                            │
│  ~/.jido_code/agents/*.md + .jido_code/agents/*.md           │
│  plugins/*/agents/*.md                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Parse
┌─────────────────────────────────────────────────────────────┐
│                 Agent Frontmatter Parser                      │
│  - name, description, model, tools                           │
│  - jido: schema (Zoi), channels, signals                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Generate
┌─────────────────────────────────────────────────────────────┐
│              Jido.Agent Compliant Module                      │
│  - Pure-functional cmd/2 API                                 │
│  - Directive-based effects                                   │
│  - Channel broadcasting wrapper                              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Register
┌─────────────────────────────────────────────────────────────┐
│                   Agent Registry                              │
│  ETS-backed: name => Agent definition                        │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Execute
┌─────────────────────────────────────────────────────────────┐
│              AgentServer (OTP Process)                        │
│  cmd/2 → Process directives → Broadcast state                │
└─────────────────────────────────────────────────────────────┘
```

---

## 6.1 Sub-Agent Definition Module

Define the structure for sub-agent definitions.

### 6.1.1 Sub-Agent Macro

Create macro for defining sub-agents as Jido Agents.

- [ ] 6.1.1.1 Create `lib/jido_code/extensibility/sub_agent.ex`
- [ ] 6.1.1.2 Define `__using__/1` macro:
  ```elixir
  defmacro __using__(opts) do
    quote do
      use Jido.Agent,
        name: unquote(opts[:name]),
        description: unquote(opts[:description]),
        schema: unquote(opts[:schema] || Zoi.object(%{}))

      alias Jido.Agent.Directive

      @channel_config unquote(opts[:channels])
      @signal_config unquote(opts[:signals])
      @system_prompt unquote(opts[:system_prompt])
      @tools unquote(opts[:tools])

      @impl Jido.Agent
      def on_before_cmd(agent, action) do
        # Emit start signal
        # Broadcast to channels
        {agent, []}
      end

      @impl Jido.Agent
      def on_after_cmd(agent, action, directives) do
        # Add channel broadcast directives
        {agent, add_channel_directives(directives)}
      end
    end
  end
  ```
- [ ] 6.1.1.3 Include Jido.Agent behavior
- [ ] 6.1.1.4 Add channel broadcasting in callbacks
- [ ] 6.1.1.5 Add system prompt storage

### 6.1.2 Sub-Agent Struct

Define the sub-agent data structure.

- [ ] 6.1.2.1 Define SubAgent struct:
  ```elixir
  defmodule JidoCode.Extensibility.SubAgent do
    @moduledoc """
    Sub-agent definition for specialized AI agents.

    ## Fields

    - `:name` - Agent identifier
    - `:description` - Agent description
    - `:module` - Generated Jido.Agent module
    - `:model` - LLM model to use
    - `:tools` - Allowed tools for agent
    - `:prompt` - System prompt from markdown body
    - `:schema` - Zoi schema for agent state
    - `:channels` - Channel configuration
    - `:signals` - Signal emit/subscribe configuration
    - `:source_path` - Path to markdown file
    """

    @type t :: %__MODULE__{
      name: String.t(),
      description: String.t(),
      module: module(),
      model: String.t() | nil,
      tools: [String.t()] | nil,
      prompt: String.t(),
      schema: term(),
      channels: map() | nil,
      signals: map() | nil,
      source_path: String.t() | nil
    }

    defstruct [
      :name,
      :description,
      :module,
      :model,
      :tools,
      :prompt,
      :schema,
      :channels,
      :signals,
      :source_path
    ]
  end
  ```

---

## 6.2 Agent Parser

Parse markdown agent definitions.

### 6.2.1 Agent Frontmatter Parser

Extend parser for agent-specific fields.

- [ ] 6.2.1.1 Add agent field parsing to frontmatter parser
- [ ] 6.2.1.2 Parse `jido.agent_module` for custom Elixir module
- [ ] 6.2.1.3 Parse `jido.schema` in Zoi format:
  ```yaml
  jido:
    schema:
      review_depth: quick/standard/thorough
      focus_areas: [security, performance]
  ```
- [ ] 6.2.1.4 Parse `jido.channels.broadcast_to`
- [ ] 6.2.1.5 Parse `jido.channels.events` map (on_start, on_finding, etc.)
- [ ] 6.2.1.6 Parse `jido.signals.emit` list
- [ ] 6.2.1.7 Parse `jido.signals.subscribe` list

### 6.2.2 Zoi Schema Parser

Parse Zoi schema from YAML format.

- [ ] 6.2.2.1 Implement `parse_zoi_schema/1` function
- [ ] 6.2.2.2 Convert YAML to Zoi expressions
- [ ] 6.2.2.3 Handle atom values: `Zoi.atom(values: [...])`
- [ ] 6.2.2.4 Handle string values: `Zoi.string()`
- [ ] 6.2.2.5 Handle list values: `Zoi.list(inner_type)`
- [ ] 6.2.2.6 Handle default values: `|> Zoi.default(value)`
- [ ] 6.2.2.7 Return valid Zoi schema expression

### 6.2.3 Agent Module Generator

Generate Jido.Agent compliant module.

- [ ] 6.2.3.1 Implement `from_markdown/1` in SubAgent module
- [ ] 6.2.3.2 Parse frontmatter and body
- [ ] 6.2.3.3 Build unique module name:
  ```elixir
  "JidoCode.Extensibility.Agents.#{sanitize_name(Path.basename(path, ".md"))}"
  ```
- [ ] 6.2.3.4 Build Zoi schema from parsed config
- [ ] 6.2.3.5 Use `Module.create/3` to compile:
  ```elixir
  Module.create(module_name, quote do
    use JidoCode.Extensibility.SubAgent,
      name: unquote(frontmatter["name"]),
      description: unquote(frontmatter["description"]),
      schema: unquote(zoi_schema),
      channels: unquote(channel_config),
      signals: unquote(signal_config),
      system_prompt: unquote(body),
      tools: unquote(tools)
  ```
- [ ] 6.2.3.6 Return `{:ok, SubAgent struct}` or `{:error, reason}`

---

## 6.3 Agent Registry

Registry for managing sub-agents.

### 6.3.1 Registry Module

Create ETS-backed agent registry.

- [ ] 6.3.1.1 Create `lib/jido_code/extensibility/agent_registry.ex`
- [ ] 6.3.1.2 Use GenServer for registry management
- [ ] 6.3.1.3 Define Registry state:
  ```elixir
  defstruct [
    by_name: %{},      # name => SubAgent struct
    by_module: %{},   # module => SubAgent struct
    running: %{},     # agent_id => server_pid
    table: nil        # ETS table
  ]
  ```
- [ ] 6.3.1.4 Implement `start_link/1`
- [ ] 6.3.1.5 Implement `init/1` creating ETS table

### 6.3.2 Agent Registration

Implement agent registration functions.

- [ ] 6.3.2.1 Implement `register_agent/1`
- [ ] 6.3.2.2 Validate agent before registration
- [ ] 6.3.2.3 Check for name conflicts
- [ ] 6.3.2.4 Store in ETS table and state maps
- [ ] 6.3.2.5 Emit `agent/registered` signal
- [ ] 6.3.2.6 Return `{:ok, agent}` or `{:error, reason}`

### 6.3.3 Agent Lookup

Implement agent lookup functions.

- [ ] 6.3.3.1 Implement `get_agent/1` - Get by name
- [ ] 6.3.3.2 Implement `get_by_module/1` - Get by module
- [ ] 6.3.3.3 Implement `list_agents/0` - List all
- [ ] 6.3.3.4 Implement `find_agent/1` - Fuzzy search
- [ ] 6.3.3.5 Implement `get_running_agents/0` - List active

### 6.3.4 Agent Discovery

Discover and load agents from directories.

- [ ] 6.3.4.1 Implement `scan_agents_directory/1`
- [ ] 6.3.4.2 Scan `~/.jido_code/agents/*.md`
- [ ] 6.3.4.3 Scan `.jido_code/agents/*.md`
- [ ] 6.3.4.4 Scan plugin agent directories
- [ ] 6.3.4.5 Parse each markdown file
- [ ] 6.3.4.6 Register valid agents
- [ ] 6.3.4.7 Return `{loaded, skipped, errors}` summary

---

## 6.4 Agent Execution

Execute sub-agents with Jido v2 cmd/2 API.

### 6.4.1 Agent Supervisor

Create supervisor for agent processes.

- [ ] 6.4.1.1 Create `JidoCode.Extensibility.AgentSupervisor`
- [ ] 6.4.1.2 Use `DynamicSupervisor`
- [ ] 6.4.1.3 Implement `start_link/1` with strategy: :one_for_one
- [ ] 6.4.1.4 Add to application children
- [ ] 6.4.1.5 Track running agent processes

### 6.4.2 Agent Executor

Create executor for agent operations.

- [ ] 6.4.2.1 Create `lib/jido_code/extensibility/agent_executor.ex`
- [ ] 6.4.2.2 Implement `start_agent/2` - Start agent process
- [ ] 6.4.2.3 Use `Jido.AgentServer.start_link/2`
- [ ] 6.4.2.4 Generate unique agent ID
- [ ] 6.4.2.5 Track in registry running map
- [ ] 6.4.2.6 Return `{:ok, pid, agent_id}` or `{:error, reason}`

- [ ] 6.4.2.7 Implement `execute/3` - Execute action via cmd/2
- [ ] 6.4.2.8 Look up agent definition
- [ ] 6.4.2.9 Get or start AgentServer process
- [ ] 6.4.2.10 Call `Jido.Agent.cmd(agent, action)`
- [ ] 6.4.2.11 Process returned directives
- [ ] 6.4.2.12 Return `{:ok, result, directives}`

- [ ] 6.4.2.13 Implement `stop_agent/2` - Stop agent process
- [ ] 6.4.2.14 Use `Jido.AgentServer.stop/1`
- [ ] 6.4.2.15 Remove from running map
- [ ] 6.4.2.16 Emit `agent/stopped` signal

### 6.4.3 Directive Processing

Process Jido v2 directives.

- [ ] 6.4.3.1 Implement `process_directives/3`
- [ ] 6.4.3.2 Handle `Directive.Emit` - Publish signal
- [ ] 6.4.3.3 Handle `Directive.Spawn` - Start child process
- [ ] 6.4.3.4 Handle `Directive.Schedule` - Schedule delayed message
- [ ] 6.4.3.5 Handle `Directive.Stop` - Stop agent
- [ ] 6.4.3.6 Handle `Directive.Error` - Handle error
- [ ] 6.4.3.7 Return list of results

### 6.4.4 Agent State Broadcasting

Broadcast agent state changes.

- [ ] 6.4.4.1 Implement `broadcast_state/3`
- [ ] 6.4.4.2 Detect state changes from agent
- [ ] 6.4.4.3 Emit `agent/state_changed` signal
- [ ] 6.4.4.4 Broadcast to configured channels
- [ ] 6.4.4.5 Include agent_id, state, timestamp in payload

---

## 6.5 Unit Tests for Sub-Agent System

Comprehensive unit tests for agent components.

### 6.5.1 SubAgent Macro Tests

- [ ] Test __using__ generates Jido.Agent compliant module
- [ ] Test on_before_cmd emits signal
- [ ] Test on_after_cmd adds channel directives
- [ ] Test system_prompt stored correctly

### 6.5.2 Parser Tests

- [ ] Test parse_zoi_schema converts YAML to Zoi
- [ ] Test parse_zoi_schema handles atoms
- [ ] Test parse_zoi_schema handles lists
- [ ] Test parse_zoi_schema handles defaults
- [ ] Test from_markdown generates valid module
- [ ] Test from_markdown includes all frontmatter fields

### 6.5.3 Registry Tests

- [ ] Test registry starts successfully
- [ ] Test register_agent stores agent
- [ ] Test register_agent rejects duplicates
- [ ] Test get_agent retrieves by name
- [ ] Test get_by_module retrieves by module
- [ ] Test list_agents returns all
- [ ] Test find_agent does fuzzy match
- [ ] Test unregister_agent removes agent

### 6.5.4 Executor Tests

- [ ] Test start_agent creates AgentServer
- [ ] Test start_agent tracks in running map
- [ ] Test execute calls Agent.cmd
- [ ] Test execute processes directives
- [ ] Test stop_agent terminates process
- [ ] Test stop_agent removes from running

### 6.5.5 Directive Processing Tests

- [ ] Test process_directives handles Emit
- [ ] Test process_directives handles Spawn
- [ ] Test process_directives handles Schedule
- [ ] Test process_directives handles Stop
- [ ] Test process_directives handles Error

### 6.5.6 State Broadcasting Tests

- [ ] Test broadcast_state emits signal
- [ ] Test broadcast_state sends to channels
- [ ] Test broadcast_state includes agent_id
- [ ] Test broadcast_state includes state

---

## 6.6 Phase 6 Integration Tests

Comprehensive integration tests for sub-agent system.

### 6.6.1 Agent Lifecycle Integration

- [ ] Test: Load agent from markdown
- [ ] Test: Start agent process
- [ ] Test: Execute action via cmd/2
- [ ] Test: Stop agent process
- [ ] Test: Agent state changes broadcast
- [ ] Test: Agent cleanup on stop

### 6.6.2 Agent Directive Integration

- [ ] Test: Emit directive publishes signal
- [ ] Test: Spawn directive starts child process
- [ ] Test: Schedule directive sets timeout
- [ ] Test: Stop directive terminates agent
- [ ] Test: Error directive handles failure
- [ ] Test: Multiple directives processed

### 6.6.3 Agent Signal Integration

- [ ] Test: Agent subscribes to configured signals
- [ ] Test: Agent emits configured signals
- [ ] Test: Agent routes signals to actions
- [ ] Test: Agent handles signal-based triggers

### 6.6.4 End-to-End Agent Flow

- [ ] Test: Define agent in markdown
- [ ] Test: System discovers agent
- [ ] Test: User invokes agent
- [ ] Test: Agent executes with LLM
- [ ] Test: Agent returns result
- [ ] Test: Channels receive updates

---

## Phase 6 Success Criteria

1. **SubAgent Macro**: Generates Jido.Agent compliant modules
2. **Zoi Schema Parser**: Converts YAML to Zoi expressions
3. **Module Generator**: Creates valid dynamic modules
4. **Agent Registry**: ETS-backed with process tracking
5. **Agent Executor**: cmd/2 execution with directive processing
6. **State Broadcasting**: Real-time agent state updates
7. **Test Coverage**: Minimum 80% for Phase 6 modules

---

## Phase 6 Critical Files

**New Files:**
- `lib/jido_code/extensibility/sub_agent.ex`
- `lib/jido_code/extensibility/agent_registry.ex`
- `lib/jido_code/extensibility/agent_executor.ex`
- `lib/jido_code/extensibility/agent_supervisor.ex`

**Test Files:**
- `test/jido_code/extensibility/sub_agent_test.exs`
- `test/jido_code/extensibility/agent_registry_test.exs`
- `test/jido_code/extensibility/agent_executor_test.exs`
- `test/jido_code/integration/phase6_agents_test.exs`
