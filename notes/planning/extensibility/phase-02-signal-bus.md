# Phase 2: Signal Bus Integration

This phase integrates JidoSignal.Bus as the central event system for extensibility, with Phoenix channel dispatch adapters for real-time broadcasting. The bus implements CloudEvents v1.0.2 specification for signal format.

## Signal Bus Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Application Startup                      │
│  ┌───────────────────────────────────────────────────────┐  │
│  │  JidoSignal.Bus (name: :jido_code_bus)               │  │
│  │  - Router: Path-based ("plugin/loaded", "tool/**")    │  │
│  │  - Middleware: Logger, Recorder                       │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Dispatch Adapters                           │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ Phoenix      │  │ PubSub       │  │ Hook         │       │
│  │ Channel      │  │ (Phoenix)    │  │ Trigger      │       │
│  └──────────────┘  └──────────────┘  └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## 2.1 Bus Initialization

Initialize JidoSignal.Bus as part of the application supervision tree.

### 2.1.1 Bus Child Specification

Add the bus to the application children.

- [ ] 2.1.1.1 Update `lib/jido_code/application.ex`
- [ ] 2.1.1.2 Add bus to children list:
  ```elixir
  {JidoSignal.Bus, [
    name: :jido_code_bus,
    middleware: [
      {JidoSignal.Bus.Middleware.Logger, level: :info}
    ]
  ]}
  ```
- [ ] 2.1.1.3 Ensure bus starts before other extensibility components
- [ ] 2.1.1.4 Add bus to supervisor children list

### 2.1.2 Bus Configuration Module

Create centralized bus configuration.

- [ ] 2.1.2.1 Create `lib/jido_code/extensibility/bus_config.ex`
- [ ] 2.1.2.2 Define `bus_name/0` function returning `:jido_code_bus`
- [ ] 2.1.2.3 Define `middleware/0` function returning middleware list
- [ ] 2.1.2.4 Define `router_options/0` function
- [ ] 2.1.2.5 Add `@moduledoc` with configuration examples

### 2.1.3 Bus Lifecycle Management

Create supervisor for bus-related processes.

- [ ] 2.1.3.1 Create `lib/jido_code/extensibility/bus_supervisor.ex`
- [ ] 2.1.3.2 Use `DynamicSupervisor` for child management
- [ ] 2.1.3.3 Implement `start_link/1` with strategy: :one_for_one
- [ ] 2.1.3.4 Add `child_spec/1` for application inclusion
- [ ] 2.1.3.5 Name supervisor `JidoCode.Extensibility.BusSupervisor`

### 2.1.4 Bus Health Check

Add health check functionality for the bus.

- [ ] 2.1.4.1 Implement `healthy?/0` function
- [ ] 2.1.4.2 Check if bus process is alive
- [ ] 2.1.4.3 Verify bus is responsive
- [ ] 2.1.4.4 Return `true` or `false`

---

## 2.2 Signal Dispatch Adapters

Create dispatch adapters for integrating the bus with Phoenix channels and other systems.

### 2.2.1 Phoenix Channel Dispatch Adapter

Adapter for broadcasting signals to Phoenix channels.

- [ ] 2.2.1.1 Create `lib/jido_code/extensibility/dispatch/phoenix_channel.ex`
- [ ] 2.2.1.2 Implement `Jido.Signal.Dispatch.Adapter` behavior:
  ```elixir
  defmodule JidoCode.Extensibility.Dispatch.PhoenixChannel do
    @moduledoc """
    Dispatch adapter for broadcasting signals to Phoenix channels.

    ## Configuration

        {:phoenix_channel, channel: :ui_state, event: "agent_update"}

    ## Options

    - `:channel` - Atom channel name to broadcast on
    - `:event` - String event name to push
    """
  ```
- [ ] 2.2.1.3 Implement `init/1` for adapter initialization
- [ ] 2.2.1.4 Implement `dispatch/2` for signal broadcasting
- [ ] 2.2.1.5 Use `Phoenix.PubSub.broadcast/3` for delivery
- [ ] 2.2.1.6 Handle connection failures gracefully

### 2.2.2 PubSub Dispatch Adapter

Adapter for Phoenix.PubSub integration.

- [ ] 2.2.2.1 Create `lib/jido_code/extensibility/dispatch/pubsub_ex.ex`
- [ ] 2.2.2.2 Implement `Jido.Signal.Dispatch.Adapter` behavior
- [ ] 2.2.2.3 Implement `init/1` for topic configuration
- [ ] 2.2.2.4 Implement `dispatch/2` for PubSub broadcasting
- [ ] 2.2.2.5 Support optional message filtering
- [ ] 2.2.2.6 Add `@moduledoc` with usage examples

### 2.2.3 Hook Dispatch Adapter

Adapter to trigger hook execution from signals.

- [ ] 2.2.3.1 Create `lib/jido_code/extensibility/dispatch/hook.ex`
- [ ] 2.2.3.2 Implement `Jido.Signal.Dispatch.Adapter` behavior
- [ ] 2.2.3.3 Implement `init/1` for hook configuration
- [ ] 2.2.3.4 Implement `dispatch/2` to call hook runner
- [ ] 2.2.3.5 Pass signal data to hook handlers
- [ ] 2.2.3.6 Handle hook execution results

---

## 2.3 Signal Types and Paths

Define standard signal types for extensibility events using path-based routing.

### 2.3.1 Lifecycle Signals

Signals for plugin and agent lifecycle events.

- [ ] 2.3.1.1 Create `lib/jido_code/extensibility/signals/lifecycle.ex`
- [ ] 2.3.1.2 Define `plugin_loaded/2` helper:
  ```elixir
  def plugin_loaded(plugin_name, attrs \\ %{}) do
    {:ok, signal} = Jido.Signal.new(
      "plugin/loaded",
      Map.merge(%{plugin_name: plugin_name}, attrs),
      source: "/extensibility/plugin"
    )
  end
  ```
- [ ] 2.3.1.3 Define `plugin_unloaded/1` helper
- [ ] 2.3.1.4 Define `plugin_error/2` helper
- [ ] 2.3.1.5 Define `agent_started/2` helper
- [ ] 2.3.1.6 Define `agent_stopped/2` helper
- [ ] 2.3.1.7 Define `agent_state_changed/3` helper

### 2.3.2 Tool Signals

Signals for tool execution lifecycle.

- [ ] 2.3.2.1 Create `lib/jido_code/extensibility/signals/tool.ex`
- [ ] 2.3.2.2 Define `tool_before_use/3` helper:
  ```elixir
  def tool_before_use(tool_name, params, context) do
    {:ok, signal} = Jido.Signal.new(
      "tool/before_use",
      %{
        tool_name: tool_name,
        params: params,
        context: context
      },
      source: "/extensibility/tool"
    )
  end
  ```
- [ ] 2.3.2.3 Define `tool_after_use/4` helper (with result)
- [ ] 2.3.2.4 Define `tool_error/4` helper (with error)

### 2.3.3 Command Signals

Signals for command execution lifecycle.

- [ ] 2.3.3.1 Create `lib/jido_code/extensibility/signals/command.ex`
- [ ] 2.3.3.2 Define `command_started/2` helper
- [ ] 2.3.3.3 Define `command_completed/3` helper
- [ ] 2.3.3.4 Define `command_failed/3` helper

---

## 2.4 Bus Subscription Helpers

Helper functions for subscribing to extensibility signal paths.

### 2.4.1 Subscription Module

Create module for subscription management.

- [ ] 2.4.1.1 Create `lib/jido_code/extensibility/bus_subscriptions.ex`
- [ ] 2.4.1.2 Implement `subscribe_lifecycle/2` for lifecycle signals
- [ ] 2.4.1.3 Implement `subscribe_tools/2` for tool signals
- [ ] 2.4.1.4 Implement `subscribe_commands/2` for command signals
- [ ] 2.4.1.5 Implement `subscribe_all/2` for all extensibility signals

### 2.4.2 Path Constants

Define signal path constants for type safety.

- [ ] 2.4.2.1 Define `@plugin_paths` module attribute
- [ ] 2.4.2.2 Define `@tool_paths` module attribute
- [ ] 2.4.2.3 Define `@command_paths` module attribute
- [ ] 2.4.2.4 Export path constants

---

## 2.5 Unit Tests for Signal Bus

Comprehensive unit tests for bus integration.

### 2.5.1 Bus Configuration Tests

- [ ] Test bus_name/0 returns :jido_code_bus
- [ ] Test middleware/0 returns expected middleware
- [ ] Test router_options/0 returns valid options
- [ ] Test bus starts with application

### 2.5.2 Dispatch Adapter Tests

- [ ] Test PhoenixChannel adapter init
- [ ] Test PhoenixChannel adapter dispatch
- [ ] Test PubSubEx adapter init
- [ ] Test PubSubEx adapter dispatch
- [ ] Test Hook adapter init
- [ ] Test Hook adapter dispatch

### 2.5.3 Signal Helper Tests

- [ ] Test plugin_loaded creates valid signal
- [ ] Test plugin_unloaded creates valid signal
- [ ] Test plugin_error creates valid signal
- [ ] Test agent_started creates valid signal
- [ ] Test agent_stopped creates valid signal
- [ ] Test agent_state_changed creates valid signal
- [ ] Test tool_before_use creates valid signal
- [ ] Test tool_after_use creates valid signal
- [ ] Test tool_error creates valid signal
- [ ] Test command_started creates valid signal
- [ ] Test command_completed creates valid signal
- [ ] Test command_failed creates valid signal

### 2.5.4 Subscription Tests

- [ ] Test subscribe_lifecycle subscribes to plugin paths
- [ ] Test subscribe_tools subscribes to tool paths
- [ ] Test subscribe_commands subscribes to command paths
- [ ] Test subscribe_all subscribes to all paths
- [ ] Test subscriptions receive matching signals

---

## 2.6 Phase 2 Integration Tests

Comprehensive integration tests for signal bus functionality.

### 2.6.1 Bus Operations Integration

- [ ] Test: Bus starts with application
- [ ] Test: Subscribe to signal paths
- [ ] Test: Publish signals to bus
- [ ] Test: Signal dispatch to Phoenix channels
- [ ] Test: Signal dispatch to hooks
- [ ] Test: Multiple subscribers receive signals

### 2.6.2 Signal Routing Integration

- [ ] Test: Path-based routing with exact match
- [ ] Test: Path-based routing with wildcard (*)
- [ ] Test: Path-based routing with double wildcard (**)
- [ ] Test: Multiple subscribers to same path
- [ ] Test: Unsubscribe removes listener
- [ ] Test: Middleware processes signals

### 2.6.3 Signal Dispatch Integration

- [ ] Test: PhoenixChannel adapter broadcasts to PubSub
- [ ] Test: PubSubEx adapter delivers to topic
- [ ] Test: Hook adapter triggers hook execution
- [ ] Test: Adapter handles connection failures
- [ ] Test: Adapter retries on transient failures

### 2.6.4 CloudEvents Compliance

- [ ] Test: All signals include specversion: "1.0.2"
- [ ] Test: All signals include unique id
- [ ] Test: All signals include source
- [ ] Test: All signals include type (path)
- [ ] Test: All signals include time (timestamp)
- [ ] Test: Signals serialize to CloudEvents JSON

---

## Phase 2 Success Criteria

1. **Bus Initialization**: JidoSignal.Bus starts with application
2. **Dispatch Adapters**: Phoenix channel, PubSub, and hook adapters implemented
3. **Signal Types**: Lifecycle, tool, and command signal helpers defined
4. **Path-Based Routing**: All signals use path format (e.g., "plugin/loaded")
5. **CloudEvents Compliance**: All signals v1.0.2 compliant
6. **Test Coverage**: Minimum 80% for Phase 2 modules

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_code/extensibility/bus_config.ex`
- `lib/jido_code/extensibility/bus_supervisor.ex`
- `lib/jido_code/extensibility/dispatch/phoenix_channel.ex`
- `lib/jido_code/extensibility/dispatch/pubsub_ex.ex`
- `lib/jido_code/extensibility/dispatch/hook.ex`
- `lib/jido_code/extensibility/signals/lifecycle.ex`
- `lib/jido_code/extensibility/signals/tool.ex`
- `lib/jido_code/extensibility/signals/command.ex`
- `lib/jido_code/extensibility/bus_subscriptions.ex`

**Modified Files:**
- `lib/jido_code/application.ex`

**Test Files:**
- `test/jido_code/extensibility/bus_config_test.exs`
- `test/jido_code/extensibility/dispatch/phoenix_channel_test.exs`
- `test/jido_code/extensibility/dispatch/pubsub_ex_test.exs`
- `test/jido_code/extensibility/dispatch/hook_test.exs`
- `test/jido_code/extensibility/signals/lifecycle_test.exs`
- `test/jido_code/extensibility/signals/tool_test.exs`
- `test/jido_code/extensibility/signals/command_test.exs`
- `test/jido_code/integration/phase2_signal_bus_test.exs`
