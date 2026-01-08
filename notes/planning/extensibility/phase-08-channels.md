# Phase 8: Phoenix Channels

This phase implements Phoenix channel integration for real-time state synchronization, event broadcasting, and UI updates. Channels bridge the JidoSignal.Bus to connected clients.

## Phoenix Channel Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Phoenix.Endpoint                            │
│  WebSocket endpoint: ws://localhost:4000/socket              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Socket Connection
┌─────────────────────────────────────────────────────────────┐
│                   JidoCode.Extensibility.Socket               │
│  - Token authentication                                      │
│  - Connection validation                                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Channel Join
┌─────────────────────────────────────────────────────────────┐
│                     Channel Routes                            │
│  - "jido:agent:*" - Agent-specific updates                   │
│  - "jido:ui" - UI events and progress                        │
│  - "jido:hooks" - Hook execution events                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Signal Bridge
┌─────────────────────────────────────────────────────────────┐
│                   SignalBridge GenServer                      │
│  Subscribe to bus paths → Broadcast to channels              │
└─────────────────────────────────────────────────────────────┘
```

---

## 8.1 Channel Socket Definition

Define the Phoenix socket for extensibility events.

### 8.1.1 Socket Module

Create the Phoenix socket.

- [ ] 8.1.1.1 Create `lib/jido_code/extensibility/socket.ex`
- [ ] 8.1.1.2 Use `Phoenix.Socket`
- [ ] 8.1.1.3 Define socket:
  ```elixir
  defmodule JidoCode.Extensibility.Socket do
    use Phoenix.Socket

    ## Channels
    channel "jido:agent:*", JidoCode.Extensibility.Channels.AgentState
    channel "jido:ui", JidoCode.Extensibility.Channels.UIEvents
    channel "jido:hooks", JidoCode.Extensibility.Channels.HookEvents

    ## Transports
    transport :websocket, Phoenix.Transports.WebSocket

    # Authentication
    def connect(_params, socket, connect_info) do
      # Validate connection
      {:ok, socket}
    end

    # Socket ID assignment
    def id(_socket), do: nil
  end
  ```
- [ ] 8.1.1.4 Configure channel routes
- [ ] 8.1.1.5 Add WebSocket transport
- [ ] 8.1.1.6 Add connection validation

### 8.1.2 Token Authentication

Add token-based authentication.

- [ ] 8.1.2.1 Implement `connect/3` with token validation
- [ ] 8.1.2.2 Read token from params or headers
- [ ] 8.1.2.3 Validate against configured tokens
- [ ] 8.1.2.4 Support environment variable tokens
- [ ] 8.1.2.5 Return `{:ok, socket}` or `:error`

### 8.1.3 Endpoint Configuration

Update endpoint for socket configuration.

- [ ] 8.1.3.1 Create or update `lib/jido_code/endpoint.ex`
- [ ] 8.1.3.2 Add socket configuration:
  ```elixir
  socket "/socket", JidoCode.Extensibility.Socket,
    websocket: true,
    longpoll: false
  ```
- [ ] 8.1.3.3 Configure for development (allow origins)
- [ ] 8.1.3.4 Configure for production (SSL, compression)
- [ ] 8.1.3.5 Add heartbeat interval

---

## 8.2 Agent State Channel

Channel for real-time agent state updates.

### 8.2.1 Agent State Channel Module

Create agent-specific channel.

- [ ] 8.2.1.1 Create `lib/jido_code/extensibility/channels/agent_state.ex`
- [ ] 8.2.1.2 Use `Phoenix.Channel`
- [ ] 8.2.1.3 Implement `join/3`:
  ```elixir
  def join("jido:agent:" <> agent_id, _params, socket) do
    # Subscribe to agent-specific signals
    Bus.subscribe(:jido_code_bus, "agent/#{agent_id}",
      dispatch: {:pid, target: self()})

    {:ok, assign(socket, :agent_id, agent_id)}
  end
  ```
- [ ] 8.2.1.4 Handle invalid agent IDs
- [ ] 8.2.1.5 Return `{:ok, socket}` or `{:error, reason}`

### 8.2.2 Channel Event Handlers

Handle incoming signals and push to clients.

- [ ] 8.2.2.1 Implement `handle_info/2` for `:signal` messages
- [ ] 8.2.2.2 Extract agent_id from socket assigns
- [ ] 8.2.2.3 Match signal type to event name
- [ ] 8.2.2.4 Push event to channel:
  ```elixir
  push(socket, event_name, signal.data)
  ```
- [ ] 8.2.2.5 Return `{:noreply, socket}`

### 8.2.3 Agent Event Mapping

Map signal types to channel events.

- [ ] 8.2.3.1 Map `agent/started` → `agent_started` event
- [ ] 8.2.3.2 Map `agent/stopped` → `agent_stopped` event
- [ ] 8.2.3.3 Map `agent/state_changed` → `state_update` event
- [ ] 8.2.3.4 Map `agent/error` → `agent_error` event
- [ ] 8.2.3.5 Include full agent state in payload

### 8.2.4 Client Message Handling

Handle incoming client messages.

- [ ] 8.2.4.1 Implement `handle_in/3` for `"get_state"` message
- [ ] 8.2.4.2 Retrieve current agent state
- [ ] 8.2.4.3 Push state to client
- [ ] 8.2.4.4 Implement `handle_in/3` for `"execute"` message
- [ ] 8.2.4.5 Execute action on agent
- [ ] 8.2.4.6 Return execution result

---

## 8.3 UI Events Channel

Channel for UI-related events.

### 8.3.1 UI Events Channel Module

Create UI events channel.

- [ ] 8.3.1.1 Create `lib/jido_code/extensibility/channels/ui_events.ex`
- [ ] 8.3.1.2 Use `Phoenix.Channel`
- [ ] 8.3.1.3 Implement `join/3`:
  ```elixir
  def join("jido:ui", _params, socket) do
    # Subscribe to all UI signals
    Bus.subscribe(:jido_code_bus, "ui",
      dispatch: {:pid, target: self()})

    Bus.subscribe(:jido_code_bus, "tool/**",
      dispatch: {:pid, target: self()})

    {:ok, socket}
  end
  ```

### 8.3.2 UI Event Handlers

Handle UI-related signals.

- [ ] 8.3.2.1 Implement `handle_info/2` for `:signal` messages
- [ ] 8.3.2.2 Map `tool/started` → `tool_started` event
- [ ] 8.3.2.3 Map `tool/completed` → `tool_completed` event
- [ ] 8.3.2.4 Map `tool/error` → `tool_error` event
- [ ] 8.3.2.5 Map `hook/triggered` → `hook_triggered` event
- [ ] 8.3.2.6 Map `command/started` → `command_started` event
- [ ] 8.3.2.7 Map `command/completed` → `command_completed` event
- [ ] 8.3.2.8 Push events to all subscribers

### 8.3.3 Progress Events

Handle progress update events.

- [ ] 8.3.3.1 Implement progress event handling
- [ ] 8.3.3.2 Map `progress` signals to `progress` event
- [ ] 8.3.3.3 Include progress percentage
- [ ] 8.3.3.4 Include current step info
- [ ] 8.3.3.5 Include ETA if available

---

## 8.4 Hook Events Channel

Channel for hook execution events.

### 8.4.1 Hook Events Channel Module

Create hook events channel.

- [ ] 8.4.1.1 Create `lib/jido_code/extensibility/channels/hook_events.ex`
- [ ] 8.4.1.2 Use `Phoenix.Channel`
- [ ] 8.4.1.3 Implement `join/3`
- [ ] 8.4.1.4 Subscribe to hook lifecycle signals
- [ ] 8.4.1.5 Return `{:ok, socket}`

### 8.4.2 Hook Event Handlers

Handle hook execution signals.

- [ ] 8.4.2.1 Map `hook/started` → `hook_started` event
- [ ] 8.4.2.2 Map `hook/completed` → `hook_completed` event
- [ ] 8.4.2.3 Map `hook/failed` → `hook_failed` event
- [ ] 8.4.2.4 Include hook type in payload
- [ ] 8.4.2.5 Include execution duration

---

## 8.5 Channel Signal Bridge

Bridge between JidoSignal.Bus and Phoenix channels.

### 8.5.1 Signal Bridge GenServer

Create the signal bridge.

- [ ] 8.5.1.1 Create `lib/jido_code/extensibility/signal_bridge.ex`
- [ ] 8.5.1.2 Use GenServer for bridge management
- [ ] 8.5.1.3 Define Bridge state:
  ```elixir
  defstruct [
    subscriptions: [],    # Active signal subscriptions
    channel_mappings: %{}, # signal_path => [channel_topics]
    bus: nil              # Bus name
  ]
  ```
- [ ] 8.5.1.4 Implement `start_link/1` with opts
- [ ] 8.5.1.5 Implement `init/1` setting up subscriptions

### 8.5.2 Signal Subscription

Subscribe to signals for bridge forwarding.

- [ ] 8.5.2.1 Implement `subscribe_to_signals/1`
- [ ] 8.5.2.2 Subscribe to `agent/**` paths
- [ ] 8.5.2.3 Subscribe to `tool/**` paths
- [ ] 8.5.2.4 Subscribe to `command/**` paths
- [ ] 8.5.2.5 Subscribe to `hook/**` paths
- [ ] 8.5.2.6 Subscribe to `plugin/**` paths
- [ ] 8.5.2.7 Store subscription references

### 8.5.3 Signal Broadcasting

Broadcast signals to matching channels.

- [ ] 8.5.3.1 Implement `handle_info/2` for `:signal` messages
- [ ] 8.5.3.2 Extract signal path and type
- [ ] 8.5.3.3 Find matching channel topics
- [ ] 8.5.3.4 Broadcast to each matching channel:
  ```elixir
  Phoenix.PubSub.broadcast(JidoCode.PubSub, topic, {
    __MODULE__, :broadcast, signal
  })
  ```
- [ ] 8.5.3.5 Handle broadcast errors
- [ ] 8.5.3.6 Return `{:noreply, state}`

### 8.5.4 Bidirectional Communication

Handle incoming channel messages as signals.

- [ ] 8.5.4.1 Implement `handle_channel_message/3`
- [ ] 8.5.4.2 Convert channel message to signal
- [ ] 8.5.4.3 Use signal type from message
- [ ] 8.5.4.4 Include channel topic in source
- [ ] 8.5.4.5 Publish to bus
- [ ] 8.5.4.6 Return `:ok` or `{:error, reason}`

---

## 8.6 Unit Tests for Phoenix Channels

Comprehensive unit tests for channel components.

### 8.6.1 Socket Tests

- [ ] Test socket configuration
- [ ] Test connect/3 with valid token
- [ ] Test connect/3 with invalid token
- [ ] Test connect/3 with env var token
- [ ] Test socket ID assignment

### 8.6.2 Agent Channel Tests

- [ ] Test join with valid agent_id
- [ ] Test join with invalid agent_id
- [ ] Test join subscribes to signals
- [ ] Test handle_info pushes agent events
- [ ] Test handle_in get_state returns state
- [ ] Test handle_in execute runs action

### 8.6.3 UI Channel Tests

- [ ] Test join subscribes to UI signals
- [ ] Test handle_info pushes tool events
- [ ] Test handle_info pushes hook events
- [ ] Test handle_info pushes command events
- [ ] Test handle_info pushes progress events

### 8.6.4 Hook Channel Tests

- [ ] Test join subscribes to hook signals
- [ ] Test handle_info pushes hook events
- [ ] Test handle_info includes execution data

### 8.6.5 Bridge Tests

- [ ] Test bridge starts and subscribes
- [ ] Test subscribe_to_signals registers subscriptions
- [ ] Test handle_info broadcasts to channels
- [ ] Test handle_channel_message publishes to bus
- [ ] Test bridge handles multiple signals

---

## 8.7 Phase 8 Integration Tests

Comprehensive integration tests for Phoenix channels.

### 8.7.1 Channel Communication Integration

- [ ] Test: Client connects to agent channel
- [ ] Test: Client receives agent state updates
- [ ] Test: Client connects to UI channel
- [ ] Test: Client receives UI events
- [ ] Test: Signal bridge forwards signals

### 8.7.2 Real-time Updates Integration

- [ ] Test: Agent state changes broadcast to subscribers
- [ ] Test: Tool execution events broadcast
- [ ] Test: Hook triggers broadcast
- [ ] Test: Progress updates broadcast
- [ ] Test: Multiple subscribers receive events

### 8.7.3 Bidirectional Communication Integration

- [ ] Test: Client message converts to signal
- [ ] Test: Signal publishes to bus
- [ ] Test: Bus subscribers receive signal
- [ ] Test: Response returns to client

### 8.7.4 End-to-End Channel Flow

- [ ] Test: Connect WebSocket client
- [ ] Test: Join agent channel
- [ ] Test: Trigger agent state change
- [ ] Test: Receive state update
- [ ] Test: Send execute message
- [ ] Test: Receive execution result

---

## Phase 8 Success Criteria

1. **Socket**: Phoenix socket with authentication
2. **Agent Channel**: Agent-specific state updates
3. **UI Channel**: Tool, command, hook events
4. **Hook Channel**: Hook execution events
5. **Signal Bridge**: Bus → Channel forwarding
6. **Bidirectional**: Channel → Bus conversion
7. **Test Coverage**: Minimum 80% for Phase 8 modules

---

## Phase 8 Critical Files

**New Files:**
- `lib/jido_code/extensibility/socket.ex`
- `lib/jido_code/extensibility/channels/agent_state.ex`
- `lib/jido_code/extensibility/channels/ui_events.ex`
- `lib/jido_code/extensibility/channels/hook_events.ex`
- `lib/jido_code/extensibility/signal_bridge.ex`
- `lib/jido_code/endpoint.ex`

**Test Files:**
- `test/jido_code/extensibility/socket_test.exs`
- `test/jido_code/extensibility/channels/agent_state_test.exs`
- `test/jido_code/extensibility/channels/ui_events_test.exs`
- `test/jido_code/extensibility/channels/hook_events_test.exs`
- `test/jido_code/extensibility/signal_bridge_test.exs`
- `test/jido_code/integration/phase8_channels_test.exs`
