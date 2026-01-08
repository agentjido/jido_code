# Phase 9: TermUI Integration

This phase implements TermUI components for visualizing extensibility state, including loaded plugins, active hooks, and agent status. The panel integrates with the main TUI using Elm Architecture patterns.

## TermUI Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Main TUI (TermUI.Application)                │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  ExtensibilityPanel (Ctrl+E to toggle)               │    │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────┐  │    │
│  │  │ Agent Status │  │ Recent Hooks │  │ Plugins  │  │    │
│  │  │ - id         │  │ - name       │  │ - name   │  │    │
│  │  │ - state      │  │ - event      │  │ - version│  │    │
│  │  │ - update     │  │ - timestamp  │  │ - status │  │    │
│  │  └──────────────┘  └──────────────┘  └──────────┘  │    │
│  │  ┌──────────────────────────────────────────────┐   │    │
│  │  │ Channel Status: Connected | Disconnected     │   │    │
│  │  └──────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Phoenix.Channel
┌─────────────────────────────────────────────────────────────┐
│                   Real-time Updates                           │
│  - agent_state_changed → Update agent status                 │
│  - hook_triggered → Add to recent hooks                      │
│  - plugin_loaded → Add to plugins list                      │
└─────────────────────────────────────────────────────────────┘
```

---

## 9.1 Extensibility Panel Component

Main panel for displaying extensibility information.

### 9.1.1 Panel Module

Create the extensibility panel.

- [ ] 9.1.1.1 Create `lib/jido_code/tui/extensibility_panel.ex`
- [ ] 9.1.1.2 Use TermUI.Element protocol
- [ ] 9.1.1.3 Define Panel struct:
  ```elixir
  defmodule JidoCode.TUI.ExtensibilityPanel do
    @moduledoc """
    TermUI panel for displaying extensibility state.

    Follows Elm Architecture: init, update, view, event_to_msg
    """

    defstruct [
      agents: %{},           # agent_id => %{status, last_update, context}
      active_hooks: [],      # recent hook executions
      loaded_plugins: [],    # loaded plugins
      channel_status: :disconnected,
      visible: false,
      selected_section: :agents
    ]
  end
  ```
- [ ] 9.1.1.4 Implement `init/1` for initial state
- [ ] 9.1.1.5 Implement `event_to_msg/2` for channel events
- [ ] 9.1.1.6 Implement `update/2` for state changes
- [ ] 9.1.1.7 Implement `view/1` for rendering

### 9.1.2 Panel Initialization

Initialize panel with current state.

- [ ] 9.1.2.1 Implement `init/1` function
- [ ] 9.1.2.2 Query current running agents
- [ ] 9.1.2.3 Query loaded plugins
- [ ] 9.1.2.4 Check channel connection status
- [ ] 9.1.2.5 Return initial state struct

### 9.1.3 Event to Message Conversion

Convert Phoenix channel events to panel messages.

- [ ] 9.1.3.1 Implement `event_to_msg/2`
- [ ] 9.1.3.2 Handle `{:channel_event, "agent_state"}` → `{:agent_state_update, payload}`
- [ ] 9.1.3.3 Handle `{:channel_event, "hook_triggered"}` → `{:hook_triggered, payload}`
- [ ] 9.1.3.4 Handle `{:channel_event, "plugin_loaded"}` → `{:plugin_loaded, payload}`
- [ ] 9.1.3.5 Handle `{:channel_event, "plugin_unloaded"}` → `{:plugin_unloaded, payload}`
- [ ] 9.1.3.6 Handle `{:channel_event, "channel_status"}` → `{:channel_status, status}`
- [ ] 9.1.3.7 Return `{:msg, message}` or `:ignore`

### 9.1.4 State Updates

Update panel state based on messages.

- [ ] 9.1.4.1 Implement `update({:agent_state_update, payload}, state)`
- [ ] 9.1.4.2 Update agent in agents map
- [ ] 9.1.4.3 Include timestamp
- [ ] 9.1.4.4 Return `{new_state, []}`

- [ ] 9.1.4.5 Implement `update({:hook_triggered, payload}, state)`
- [ ] 9.1.4.6 Create hook entry with timestamp
- [ ] 9.1.4.7 Prepend to active_hooks list
- [ ] 9.1.4.8 Keep last 10 hooks only
- [ ] 9.1.4.9 Return `{new_state, []}`

- [ ] 9.1.4.10 Implement `update({:plugin_loaded, payload}, state)`
- [ ] 9.1.4.11 Add plugin to loaded_plugins
- [ ] 9.1.4.12 Sort by name
- [ ] 9.1.4.13 Return `{new_state, []}`

- [ ] 9.1.4.14 Implement `update({:toggle_visibility}, state)`
- [ ] 9.1.4.15 Flip visible flag
- [ ] 9.1.4.16 Return `{new_state, []}`

- [ ] 9.1.4.17 Implement `update({:select_section, section}, state)`
- [ ] 9.1.4.18 Update selected_section
- [ ] 9.1.4.19 Return `{new_state, []}`

### 9.1.5 Panel Rendering

Render the panel view.

- [ ] 9.1.5.1 Implement `view/1` function
- [ ] 9.1.5.2 Return empty if not visible
- [ ] 9.1.5.3 Import TermUI.Elements
- [ ] 9.1.5.4 Create stacked layout:
  ```elixir
  stack(:vertical, [
    panel("Agent Status", agent_status_view(state.agents)),
    panel("Recent Hooks", hooks_view(state.active_hooks)),
    panel("Loaded Plugins", plugins_view(state.loaded_plugins)),
    status_bar(state.channel_status)
  ])
  ```
- [ ] 9.1.5.5 Return TermUI element tree

---

## 9.2 Agent Status Component

Display agent information with color-coded status.

### 9.2.1 Agent Status View

Create agent status rendering.

- [ ] 9.2.1.1 Implement `agent_status_view/1` function
- [ ] 9.2.1.2 Handle empty agent list
- [ ] 9.2.1.3 For each agent, create row with:
  - Agent ID (truncated to 12 chars)
  - Status with color coding
  - Last update (relative time)
- [ ] 9.2.1.4 Use TermUI.Elements.row/1
- [ ] 9.2.1.5 Use TermUI.Renderer.Style for colors
- [ ] 9.2.1.6 Stack rows vertically

### 9.2.2 Status Color Coding

Apply color coding based on status.

- [ ] 9.2.2.1 Define `status_color/1` function
- [ ] 9.2.2.2 `:idle` → green (Style.new(fg: :green))
- [ ] 9.2.2.3 `:executing` → yellow with bold (Style.new(fg: :yellow, attrs: [:bold]))
- [ ] 9.2.2.4 `:error` → red (Style.new(fg: :red))
- [ ] 9.2.2.5 `:initialized` → cyan (Style.new(fg: :cyan))

### 9.2.3 Time Formatting

Format timestamps for display.

- [ ] 9.2.3.1 Implement `format_time/1` function
- [ ] 9.2.3.2 Handle nil timestamps
- [ ] 9.2.3.3 Show "just now" for < 1 minute
- [ ] 9.2.3.4 Show "Xm ago" for < 1 hour
- [ ] 9.2.3.5 Show "Xh ago" for < 1 day
- [ ] 9.2.3.6 Show date for older

---

## 9.3 Hooks Display Component

Display recent hook executions.

### 9.3.1 Hooks View

Create hooks rendering.

- [ ] 9.3.1.1 Implement `hooks_view/1` function
- [ ] 9.3.1.2 Handle empty hooks list
- [ ] 9.3.1.3 For each hook, create row with:
  - Hook name (truncated)
  - Triggered event
  - Timestamp (relative)
- [ ] 9.3.1.4 Color code by hook type
- [ ] 9.3.1.5 Stack rows vertically

### 9.3.2 Hook Type Colors

Apply colors based on hook type.

- [ ] 9.3.2.1 Define `hook_type_color/1` function
- [ ] 9.3.2.2 `:command` → magenta
- [ ] 9.3.2.3 `:elixir` → blue
- [ ] 9.3.2.4 `:channel` → cyan
- [ ] 9.3.2.5 `:signal` → green
- [ ] 9.3.2.6 `:prompt` → yellow

---

## 9.4 Plugins Display Component

Display loaded plugin information.

### 9.4.1 Plugins View

Create plugins rendering.

- [ ] 9.4.1.1 Implement `plugins_view/1` function
- [ ] 9.4.1.2 Handle empty plugins list
- [ ] 9.4.1.3 For each plugin, create row with:
  - Plugin name
  - Version
  - Status (enabled/disabled/errored)
  - Component counts (optional)
- [ ] 9.4.1.4 Color code by status
- [ ] 9.4.1.5 Stack rows vertically

### 9.4.2 Plugin Status Colors

Apply colors based on plugin status.

- [ ] 9.4.2.1 Define `plugin_status_color/1` function
- [ ] 9.4.2.2 `:enabled` → green
- [ ] 9.4.2.3 `:disabled` → gray
- [ ] 9.4.2.4 `:errored` → red
- [ ] 9.4.2.5 `:loaded` → cyan

---

## 9.5 Panel Integration

Integrate extensibility panel into main TUI.

### 9.5.1 TUI Event Integration

Subscribe to Phoenix channel events.

- [ ] 9.5.1.1 Add panel to main TUI state
- [ ] 9.5.1.2 Subscribe to agent_state channel
- [ ] 9.5.1.3 Subscribe to ui_events channel
- [ ] 9.5.1.4 Route events to panel via event_to_msg
- [ ] 9.5.1.5 Update TUI state with panel updates

### 9.5.2 Keyboard Shortcuts

Add keyboard shortcuts for panel control.

- [ ] 9.5.2.1 Add `Ctrl+E` to toggle panel visibility
- [ ] 9.5.2.2 Add `Tab` to cycle through sections
- [ ] 9.5.2.3 Add `Shift+Tab` to cycle backwards
- [ ] 9.5.2.4 Add `Enter` to view details of selected item
- [ ] 9.5.2.5 Add `Esc` to close details view

### 9.5.3 Details View

Add detailed view for selected items.

- [ ] 9.5.3.1 Implement `details_view/2` for agent details
- [ ] 9.5.3.2 Show full agent state
- [ ] 9.5.3.3 Show recent actions
- [ ] 9.5.3.4 Implement `details_view/2` for plugin details
- [ ] 9.5.3.5 Show plugin manifest
- [ ] 9.5.3.6 Show component counts

### 9.5.4 Status Bar

Create status bar for channel connection.

- [ ] 9.5.4.1 Implement `status_bar/1` function
- [ ] 9.5.4.2 Show "Connected: jido:agent" if connected
- [ ] 9.5.4.3 Show "Disconnected" if not connected
- [ ] 9.5.4.4 Use green for connected
- [ ] 9.5.4.5 Use red for disconnected

---

## 9.6 Unit Tests for TermUI Integration

Comprehensive unit tests for TUI components.

### 9.6.1 Panel Tests

- [ ] Test init/1 creates initial state
- [ ] Test event_to_msg converts events
- [ ] Test event_to_msg ignores unknown events
- [ ] Test update handles agent_state_update
- [ ] Test update handles hook_triggered
- [ ] Test update handles plugin_loaded
- [ ] Test update handles toggle_visibility
- [ ] Test update handles select_section
- [ ] Test view renders when visible
- [ ] Test view returns empty when not visible

### 9.6.2 Agent Status Tests

- [ ] Test agent_status_view handles empty list
- [ ] Test agent_status_view renders agents
- [ ] Test status_color returns correct colors
- [ ] Test format_time shows "just now"
- [ ] Test format_time shows "Xm ago"
- [ ] Test format_time shows "Xh ago"
- [ ] Test format_time handles nil

### 9.6.3 Hooks View Tests

- [ ] Test hooks_view handles empty list
- [ ] Test hooks_view renders hooks
- [ ] Test hooks_view limits to 10
- [ ] Test hook_type_color returns correct colors
- [ ] Test hooks ordered by timestamp

### 9.6.4 Plugins View Tests

- [ ] Test plugins_view handles empty list
- [ ] Test plugins_view renders plugins
- [ ] Test plugin_status_color returns correct colors
- [ ] Test plugins sorted by name

### 9.6.5 Integration Tests

- [ ] Test panel receives agent events
- [ ] Test panel receives hook events
- [ ] Test panel receives plugin events
- [ ] Test keyboard shortcuts toggle visibility
- [ ] Test status bar shows connection status

---

## 9.7 Phase 9 Integration Tests

Comprehensive integration tests for TUI integration.

### 9.7.1 Panel Display Integration

- [ ] Test: Panel displays on toggle
- [ ] Test: Agent status updates in real-time
- [ ] Test: Hooks appear when triggered
- [ ] Test: Plugins list updates on load/unload
- [ ] Test: Panel closes on toggle

### 9.7.2 Channel Integration

- [ ] Test: Panel receives agent state events
- [ ] Test: Panel receives hook events
- [ ] Test: Panel receives plugin events
- [ ] Test: Multiple panels can subscribe
- [ ] Test: Channel status updates correctly

### 9.7.3 Keyboard Integration

- [ ] Test: Ctrl+E toggles panel
- [ ] Test: Tab cycles sections
- [ ] Test: Enter shows details
- [ ] Test: Esc closes details

### 9.7.4 End-to-End TUI Flow

- [ ] Test: Start TUI application
- [ ] Test: Toggle extensibility panel
- [ ] Test: Start agent via command
- [ ] Test: Observe agent status in panel
- [ ] Test: Trigger hook
- [ ] Test: Observe hook in panel
- [ ] Test: Load plugin
- [ ] Test: Observe plugin in panel

---

## Phase 9 Success Criteria

1. **ExtensibilityPanel**: Elm Architecture component
2. **Agent Status**: Real-time agent state display
3. **Hooks View**: Recent hook executions
4. **Plugins View**: Loaded plugin list
5. **Channel Integration**: Real-time updates from Phoenix
6. **Keyboard Shortcuts**: Ctrl+E, Tab, Enter, Esc
7. **Test Coverage**: Minimum 80% for Phase 9 modules

---

## Phase 9 Critical Files

**New Files:**
- `lib/jido_code/tui/extensibility_panel.ex`

**Modified Files:**
- `lib/jido_code/tui/app.ex` - Add panel to main TUI

**Test Files:**
- `test/jido_code/tui/extensibility_panel_test.exs`
- `test/jido_code/integration/phase9_tui_test.exs`

---

## Summary: All Phases Complete

Upon completion of Phase 9, the entire extensibility system will be implemented:

1. **Configuration & Settings** - Extended settings with channels, permissions, hooks
2. **Signal Bus Integration** - JidoSignal.Bus with dispatch adapters
3. **Hook System** - Lifecycle hooks with 5 types
4. **Command System** - Markdown-based slash commands
5. **Plugin Registry** - Plugin discovery and lifecycle
6. **Sub-Agent System** - Markdown-based agents
7. **Skills Framework** - Composable capabilities
8. **Phoenix Channels** - Real-time communication
9. **TermUI Integration** - Visual extensibility panel

**Total New Modules**: ~40 modules
**Total Test Files**: ~45 test files
**Estimated Test Count**: 800+ tests
