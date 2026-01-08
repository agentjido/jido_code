# Phase 3: Hook System

This phase implements the lifecycle hook system supporting command, elixir, channel, signal, and prompt hook types with proper execution ordering and result aggregation. Hooks execute on lifecycle events and can approve, deny, or ask about actions.

## Hook System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Hook Runner GenServer                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Subscribe to: "lifecycle/**" signal paths            │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼ Signal Received              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Find matching hooks via HookRegistry                 │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Execute hooks in parallel (Task.async)               │  │
│  │  - command: shell execution                           │  │
│  │  - elixir: module.function() call                     │  │
│  │  - channel: Phoenix broadcast                         │  │
│  │  - signal: Bus publish                                │  │
│  │  - prompt: LLM evaluation                             │  │
│  └───────────────────────────────────────────────────────┘  │
│                              │                              │
│                              ▼                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  Aggregate results → Decision                         │  │
│  │  - Any deny → deny                                    │  │
│  │  - Any ask → ask                                      │  │
│  │  - All approve → approve                              │  │
│  │  - No hooks → defer                                   │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3.1 Hook Data Structures

Define the core data structures for hooks.

### 3.1.1 Hook Struct

Create the main hook data structure.

- [ ] 3.1.1.1 Create `lib/jido_code/extensibility/hooks/hook.ex`
- [ ] 3.1.1.2 Define Hook struct:
  ```elixir
  defmodule JidoCode.Extensibility.Hooks.Hook do
    @moduledoc """
    Hook definition for lifecycle event handling.

    ## Hook Types

    - `:command` - Execute shell command
    - `:elixir` - Call Elixir module function
    - `:channel` - Broadcast to Phoenix channel
    - `:signal` - Emit Jido signal
    - `:prompt` - Evaluate with LLM

    ## Fields

    - `:id` - Unique hook identifier
    - `:type` - Hook type atom
    - `:matcher` - Pattern to match events (glob or exact)
    - `:config` - Type-specific configuration map
    - `:timeout` - Execution timeout in milliseconds
    """

    @type t :: %__MODULE__{
      id: String.t(),
      type: :command | :elixir | :channel | :signal | :prompt,
      matcher: String.t(),
      config: map(),
      timeout: pos_integer()
    }

    defstruct [
      :id,
      :type,
      :matcher,
      :config,
      timeout: 5000
    ]
  end
  ```
- [ ] 3.1.1.3 Add `@type` specs for all types
- [ ] 3.1.1.4 Add `@moduledoc` with examples

### 3.1.2 Hook Configuration Structs

Define type-specific configuration structs.

- [ ] 3.1.2.1 Define `CommandHookConfig` struct:
  ```elixir
  defstruct [
    :command,    # Shell command to execute
    :env,        # Environment variables map
    :timeout     # Override default timeout
  ]
  ```
- [ ] 3.1.2.2 Define `ElixirHookConfig` struct:
  ```elixir
  defstruct [
    :module,     # Module name (string or atom)
    :function,   # Function name (string or atom)
    :args        # Additional arguments list
  ]
  ```
- [ ] 3.1.2.3 Define `ChannelHookConfig` struct:
  ```elixir
  defstruct [
    :channel,           # Channel name
    :event,             # Event to push
    :payload_template   # Template with {{var}} interpolation
  ]
  ```
- [ ] 3.1.2.4 Define `SignalHookConfig` struct:
  ```elixir
  defstruct [
    :signal_type,    # Signal type path
    :bus,            # Bus name atom
    :data_template   # Template for signal data
  ]
  ```
- [ ] 3.1.2.5 Define `PromptHookConfig` struct:
  ```elixir
  defstruct [
    :prompt,      # Prompt template
    :model,       # LLM model to use
    :timeout      # Execution timeout
  ]
  ```

---

## 3.2 Hook Registry

Registry for managing hook definitions and lookups.

### 3.2.1 Registry Module

Create the hook registry with ETS storage.

- [ ] 3.2.1.1 Create `lib/jido_code/extensibility/hooks/registry.ex`
- [ ] 3.2.1.2 Use GenServer for registry management
- [ ] 3.2.1.3 Define Registry state:
  ```elixir
  defstruct [
    hooks: %{},          # id => hook
    by_matcher: %{},    # matcher => [hook_ids]
    by_type: %{},       # type => [hook_ids]
    table: nil          # ETS table reference
  ]
  ```
- [ ] 3.2.1.4 Implement `start_link/1` with name registration
- [ ] 3.2.1.5 Implement `init/1` creating ETS table

### 3.2.2 Hook Registration

Implement hook registration functions.

- [ ] 3.2.2.1 Implement `register_hook/2` - Register a hook
- [ ] 3.2.2.2 Validate hook before registration
- [ ] 3.2.2.3 Generate unique ID if not provided
- [ ] 3.2.2.4 Store hook in ETS table
- [ ] 3.2.2.5 Update matcher and type indexes
- [ ] 3.2.2.6 Return `{:ok, hook_id}` or `{:error, reason}`

### 3.2.3 Hook Lookup

Implement hook lookup functions.

- [ ] 3.2.3.1 Implement `get_hook/1` - Get hook by ID
- [ ] 3.2.3.2 Implement `find_hooks/2` - Find hooks matching event
- [ ] 3.2.3.3 Support glob pattern matching in matcher
- [ ] 3.2.3.4 Return list of matching hooks
- [ ] 3.2.3.5 Implement `list_hooks/0` - List all hooks
- [ ] 3.2.3.6 Implement `list_hooks_by_type/1` - List by type

### 3.2.4 Hook Unregistration

Implement hook removal functions.

- [ ] 3.2.4.1 Implement `unregister_hook/1` - Remove hook by ID
- [ ] 3.2.4.2 Remove from ETS table
- [ ] 3.2.4.3 Update matcher and type indexes
- [ ] 3.2.4.4 Return `:ok` or `{:error, :not_found}`

---

## 3.3 Hook Execution Engine

Execute hooks with proper timeout handling and result aggregation.

### 3.3.1 Hook Runner GenServer

Create the hook execution engine.

- [ ] 3.3.1.1 Create `lib/jido_code/extensibility/hooks/runner.ex`
- [ ] 3.3.1.2 Use GenServer for runner management
- [ ] 3.3.1.3 Define Runner state:
  ```elixir
  defstruct [
    registry: nil,      # Hook registry PID
    subscriptions: []  # Active signal subscriptions
  ]
  ```
- [ ] 3.3.1.4 Implement `start_link/1` with opts
- [ ] 3.3.1.5 Implement `init/1` subscribing to lifecycle signals
- [ ] 3.3.1.6 Subscribe to "lifecycle/**" path

### 3.3.2 Signal Handling

Handle incoming lifecycle signals.

- [ ] 3.3.2.1 Implement `handle_info/2` for `:signal` messages
- [ ] 3.3.2.2 Extract event type from signal path
- [ ] 3.3.2.3 Call `find_hooks/2` for matching hooks
- [ ] 3.3.2.4 Execute matching hooks via `execute_hooks/2`
- [ ] 3.3.2.5 Aggregate results via `aggregate_results/1`
- [ ] 3.3.2.6 Return `{:noreply, state}`

### 3.3.3 Command Hook Execution

Implement shell command hook execution.

- [ ] 3.3.3.1 Implement `execute_command_hook/2`
- [ ] 3.3.3.2 Use `System.cmd/3` for execution
- [ ] 3.3.3.3 Build environment from signal data
- [ ] 3.3.3.4 Capture stdout and stderr
- [ ] 3.3.3.5 Parse output for decision (approve/deny/ask)
- [ ] 3.3.3.6 Return `{:ok, result}` or `{:error, reason}`
- [ ] 3.3.3.7 Handle timeout with `Task.await`

### 3.3.4 Elixir Hook Execution

Implement Elixir function hook execution.

- [ ] 3.3.4.1 Implement `execute_elixir_hook/2`
- [ ] 3.3.4.2 Convert module string to atom
- [ ] 3.3.4.3 Convert function string to atom
- [ ] 3.3.4.4 Dynamically call `apply(module, function, args)`
- [ ] 3.3.4.5 Pass signal data as first argument
- [ ] 3.3.4.6 Handle exceptions with try/rescue
- [ ] 3.3.4.7 Return `{:ok, result}` or `{:error, reason}`

### 3.3.5 Channel Hook Execution

Implement Phoenix channel broadcast execution.

- [ ] 3.3.5.1 Implement `execute_channel_hook/2`
- [ ] 3.3.5.2 Interpolate template variables in payload
- [ ] 3.3.5.3 Use `interpolate_template/2` for variable substitution
- [ ] 3.3.5.4 Get channel connection from channel registry
- [ ] 3.3.5.5 Broadcast via Phoenix.Channel or PubSub
- [ ] 3.3.5.6 Return `{:ok, :broadcast_sent}` or `{:error, reason}`

### 3.3.6 Signal Hook Execution

Implement signal emission hook execution.

- [ ] 3.3.6.1 Implement `execute_signal_hook/2`
- [ ] 3.3.6.2 Create new signal from template
- [ ] 3.3.6.3 Interpolate data_template variables
- [ ] 3.3.6.4 Use `Jido.Signal.new/3` for creation
- [ ] 3.3.6.5 Publish to configured bus
- [ ] 3.3.6.6 Return `{:ok, :signal_emitted}` or `{:error, reason}`

### 3.3.7 Prompt Hook Execution

Implement LLM evaluation hook execution.

- [ ] 3.3.7.1 Implement `execute_prompt_hook/2`
- [ ] 3.3.7.2 Interpolate prompt template with signal data
- [ ] 3.3.7.3 Call LLM via JidoAI or configured provider
- [ ] 3.3.7.4 Parse LLM response for decision
- [ ] 3.3.7.5 Support structured output (JSON)
- [ ] 3.3.7.6 Return `{:ok, decision}` or `{:error, reason}`

### 3.3.8 Parallel Execution

Execute hooks in parallel with timeout handling.

- [ ] 3.3.8.1 Implement `execute_hooks/2` function
- [ ] 3.3.8.2 Create Task.async for each hook
- [ ] 3.3.8.3 Use individual hook timeout
- [ ] 3.3.8.4 Await all tasks with `Task.await_many`
- [ ] 3.3.8.5 Handle timeout results as errors
- [ ] 3.3.8.6 Return list of hook results

---

## 3.4 Hook Decision Aggregation

Aggregate results from multiple hooks into a final decision.

### 3.4.1 Decision Module

Create decision aggregation logic.

- [ ] 3.4.1.1 Create `lib/jido_code/extensibility/hooks/decision.ex`
- [ ] 3.4.1.2 Define Decision type:
  ```elixir
  @type decision :: :approve | :deny | :ask | :defer
  ```
- [ ] 3.4.1.3 Define DecisionResult struct:
  ```elixir
  defstruct [
    decision: :defer,
    hook_outputs: [],
    errors: []
  ]
  ```

### 3.4.2 Aggregation Logic

Implement decision aggregation rules.

- [ ] 3.4.2.1 Implement `aggregate/1` function
- [ ] 3.4.2.2 Check for any `:deny` decisions → return `:deny`
- [ ] 3.4.2.3 Check for any `:ask` decisions → return `:ask`
- [ ] 3.4.2.4 Check all are `:approve` → return `:approve`
- [ ] 3.4.2.5 Check empty list → return `:defer`
- [ ] 3.4.2.6 Include hook outputs for ask responses

### 3.4.3 Result Parsing

Parse hook execution results into decisions.

- [ ] 3.4.3.1 Implement `parse_result/1` for command hooks
- [ ] 3.4.3.2 Parse exit code 0 → `:approve`
- [ ] 3.4.3.3 Parse exit code non-zero → `:deny`
- [ ] 3.4.3.4 Implement `parse_result/1` for elixir hooks
- [ ] 3.4.3.5 Parse `:approve`/`:deny`/`:ask` atoms
- [ ] 3.4.3.6 Parse boolean true → `:approve`, false → `:deny`
- [ ] 3.4.3.7 Implement `parse_result/1` for prompt hooks

---

## 3.5 Template Interpolation

Implement variable interpolation for templates.

### 3.5.1 Interpolation Module

Create template interpolation helper.

- [ ] 3.5.1.1 Create `lib/jido_code/extensibility/templates.ex`
- [ ] 3.5.1.2 Implement `interpolate/2` function
- [ ] 3.5.1.3 Parse `{{variable}}` syntax
- [ ] 3.5.1.4 Replace with values from data map
- [ ] 3.5.1.5 Support nested key access `{{user.name}}`
- [ ] 3.5.1.6 Handle missing variables gracefully
- [ ] 3.5.1.7 Return interpolated string

---

## 3.6 Hook Configuration Loading

Load hooks from settings.json and native Elixir modules.

### 3.6.1 JSON Hook Loading

Load hooks from settings configuration.

- [ ] 3.6.1.1 Implement `load_hooks_from_settings/1` in Hook.Loader
- [ ] 3.6.1.2 Parse hooks from settings.hooks map
- [ ] 3.6.1.3 Iterate over event types (PreToolUse, PostToolUse, etc.)
- [ ] 3.6.1.4 Create Hook structs from JSON config
- [ ] 3.6.1.5 Validate each hook configuration
- [ ] 3.6.1.6 Register valid hooks via HookRegistry
- [ ] 3.6.1.7 Return `{:ok, count}` or `{:error, reason}`

### 3.6.2 Native Elixir Hook Loading

Load hooks from .jido_code/hooks/*.ex files.

- [ ] 3.6.2.1 Implement `load_native_hooks/1` function
- [ ] 3.6.2.2 Scan `.jido_code/hooks/` directory
- [ ] 3.6.2.3 Also scan `~/.jido_code/hooks/` directory
- [ ] 3.6.2.4 Compile discovered .ex files
- [ ] 3.6.2.5 Check for `__jido_hook__/0` function
- [ ] 3.6.2.6 Call hook function to get configuration
- [ ] 3.6.2.7 Register hooks with metadata

---

## 3.7 Unit Tests for Hook System

Comprehensive unit tests for hook components.

### 3.7.1 Hook Struct Tests

- [ ] Test Hook struct creation
- [ ] Test CommandHookConfig creation
- [ ] Test ElixirHookConfig creation
- [ ] Test ChannelHookConfig creation
- [ ] Test SignalHookConfig creation
- [ ] Test PromptHookConfig creation

### 3.7.2 Registry Tests

- [ ] Test registry starts successfully
- [ ] Test register_hook stores hook
- [ ] Test register_hook generates ID
- [ ] Test register_hook validates input
- [ ] Test get_hook retrieves by ID
- [ ] Test find_hooks matches by event
- [ ] Test find_hooks supports glob patterns
- [ ] Test unregister_hook removes hook
- [ ] Test list_hooks returns all hooks
- [ ] Test list_hooks_by_type filters correctly

### 3.7.3 Runner Tests

- [ ] Test runner starts and subscribes to signals
- [ ] Test execute_command_hook runs shell command
- [ ] Test execute_command_hook times out
- [ ] Test execute_elixir_hook calls function
- [ ] Test execute_elixir_hook handles exceptions
- [ ] Test execute_channel_hook broadcasts
- [ ] Test execute_channel_hook interpolates template
- [ ] Test execute_signal_hook publishes signal
- [ ] Test execute_prompt_hook calls LLM

### 3.7.4 Decision Tests

- [ ] Test aggregate denies on any deny
- [ ] Test aggregate asks on any ask
- [ ] Test aggregate approves on all approve
- [ ] Test aggregate defers on empty list
- [ ] Test parse_result for command hooks
- [ ] Test parse_result for elixir hooks
- [ ] Test parse_result for prompt hooks

### 3.7.5 Template Tests

- [ ] Test interpolate replaces variables
- [ ] Test interpolate supports nested keys
- [ ] Test interpolate handles missing variables
- [ ] Test interpolate with complex templates

### 3.7.6 Loading Tests

- [ ] Test load_hooks_from_settings parses JSON
- [ ] Test load_hooks_from_settings validates hooks
- [ ] Test load_hooks_from_settings registers hooks
- [ ] Test load_native_hooks scans directory
- [ ] Test load_native_hooks compiles modules
- [ ] Test load_native_hooks calls __jido_hook__/0

---

## 3.8 Phase 3 Integration Tests

Comprehensive integration tests for hook system.

### 3.8.1 Hook Lifecycle Integration

- [ ] Test: Load hooks from settings on startup
- [ ] Test: Hooks execute on lifecycle events
- [ ] Test: Multiple hooks execute in parallel
- [ ] Test: Hook timeouts don't block system
- [ ] Test: Hook errors are logged

### 3.8.2 Hook Decision Integration

- [ ] Test: Deny hook blocks action
- [ ] Test: All approve allows action
- [ ] Test: Ask hook prompts user
- [ ] Test: No hooks defers to default
- [ ] Test: Mixed decisions aggregate correctly

### 3.8.3 Hook Type Integration

- [ ] Test: Command hooks execute shell commands
- [ ] Test: Elixir hooks call module functions
- [ ] Test: Channel hooks broadcast to Phoenix
- [ ] Test: Signal hooks emit to bus
- [ ] Test: Prompt hooks evaluate with LLM

### 3.8.4 End-to-End Hook Flow

- [ ] Test: Tool execution triggers PreToolUse hooks
- [ ] Test: Tool execution triggers PostToolUse hooks
- [ ] Test: Agent state change triggers hooks
- [ ] Test: Command execution triggers hooks
- [ ] Test: Plugin load/unload triggers hooks

---

## Phase 3 Success Criteria

1. **Hook Registry**: ETS-backed registry with fast lookups
2. **Hook Runner**: GenServer executing hooks in parallel
3. **All Hook Types**: Command, Elixir, Channel, Signal, Prompt implemented
4. **Decision Aggregation**: Proper deny > ask > approve > defer priority
5. **Template Interpolation**: Variable replacement works correctly
6. **Test Coverage**: Minimum 80% for Phase 3 modules

---

## Phase 3 Critical Files

**New Files:**
- `lib/jido_code/extensibility/hooks/hook.ex`
- `lib/jido_code/extensibility/hooks/registry.ex`
- `lib/jido_code/extensibility/hooks/runner.ex`
- `lib/jido_code/extensibility/hooks/decision.ex`
- `lib/jido_code/extensibility/templates.ex`
- `lib/jido_code/extensibility/hooks/loader.ex`

**Test Files:**
- `test/jido_code/extensibility/hooks/hook_test.exs`
- `test/jido_code/extensibility/hooks/registry_test.exs`
- `test/jido_code/extensibility/hooks/runner_test.exs`
- `test/jido_code/extensibility/hooks/decision_test.exs`
- `test/jido_code/extensibility/templates_test.exs`
- `test/jido_code/integration/phase3_hooks_test.exs`
