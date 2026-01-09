# Phase 1: Configuration & Settings

This phase extends the existing two-level JSON settings system to support extensibility configuration including channels, permissions, hooks, agents, and plugins. The system maintains backward compatibility with existing settings.

## Two-Level Configuration Architecture

The extensibility system uses the same two-tier configuration approach as the core settings system:

```
┌─────────────────────────────────────────────────────────────┐
│  Global Settings (~/.jido_code/settings.json)               │
│  - Default channel configurations                            │
│  - Global permissions                                        │
│  - System-wide hooks                                         │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Merge
┌─────────────────────────────────────────────────────────────┐
│  Local Settings (.jido_code/settings.json)                  │
│  - Project-specific channels (override)                      │
│  - Project permissions (merge)                               │
│  - Project hooks (concatenate)                               │
└─────────────────────────────────────────────────────────────┘
```

## Settings Schema Extension

The existing settings schema is extended with extensibility fields while maintaining backward compatibility.

---

## 1.1 Channel Configuration

Phoenix channel configuration for real-time event broadcasting.

### 1.1.1 Channel Configuration Struct

Create the channel configuration data structure.

- [x] 1.1.1.1 Create `lib/jido_code/extensibility/channel_config.ex`
- [x] 1.1.1.2 Define ChannelConfig struct:
  ```elixir
  defmodule JidoCode.Extensibility.ChannelConfig do
    @moduledoc """
    Configuration for Phoenix channel connections.

    ## Fields

    - `:socket` - WebSocket URL (e.g., "ws://localhost:4000/socket")
    - `:topic` - Channel topic (e.g., "jido:agent")
    - `:auth` - Authentication configuration
    - `:broadcast_events` - List of events to broadcast on this channel
    """

    defstruct [
      :socket,
      :topic,
      :auth,
      :broadcast_events
    ]

    @type t :: %__MODULE__{
      socket: String.t() | nil,
      topic: String.t() | nil,
      auth: map() | nil,
      broadcast_events: [String.t()] | nil
    }
  end
  ```
- [x] 1.1.1.3 Add `@doc false` for internal helper functions
- [x] 1.1.1.4 Add `@spec` for all public functions

### 1.1.2 Channel Configuration Validation

Add validation for channel configuration values.

- [x] 1.1.2.1 Implement `validate/1` function
- [x] 1.1.2.2 Validate socket URL format (ws:// or wss://)
- [x] 1.1.2.3 Validate topic format (alphanumeric with colons)
- [x] 1.1.2.4 Validate auth configuration structure
- [x] 1.1.2.5 Return `{:ok, config}` or `{:error, reason}`

### 1.1.3 Environment Variable Expansion

Support environment variable expansion in channel auth tokens.

- [x] 1.1.3.1 Implement `expand_env_vars/1` function
- [x] 1.1.3.2 Parse `${VAR_NAME}` syntax in token values
- [x] 1.1.3.3 Look up variables via `System.fetch_env/1`
- [x] 1.1.3.4 Support default values: `${VAR:-default}`
- [x] 1.1.3.5 Return expanded configuration

### 1.1.4 Default Channel Configurations

Define default channel configurations for standard channels.

- [x] 1.1.4.1 Create `defaults/0` function
- [x] 1.1.4.2 Define default "ui_state" channel
- [x] 1.1.4.3 Define default "agent" channel
- [x] 1.1.4.4 Define default "hooks" channel
- [x] 1.1.4.5 Return map of default configurations

---

## 1.2 Permission System

Permission system for controlling extensibility component access.

### 1.2.1 Permission Struct

Create the permission data structure.

- [x] 1.2.1.1 Create `lib/jido_code/extensibility/permissions.ex`
- [x] 1.2.1.2 Define Permission struct:
  ```elixir
  defmodule JidoCode.Extensibility.Permissions do
    @moduledoc """
    Permission configuration for extensibility components.

    Permission matching follows glob patterns with three outcomes:
    - `:allow` - Permit the action
    - `:deny` - Block the action
    - `:ask` - Prompt user for approval

    ## Fields

    - `:allow` - List of allowed patterns
    - `:deny` - List of denied patterns (takes precedence)
    - `:ask` - List of patterns requiring user confirmation
    """

    defstruct [
      allow: [],
      deny: [],
      ask: []
    ]

    @type t :: %__MODULE__{
      allow: [String.t()],
      deny: [String.t()],
      ask: [String.t()]
    }
  end
  ```
- [x] 1.2.1.3 Add `@type` specs for all types
- [x] 1.2.1.4 Add `@moduledoc` examples

### 1.2.2 Permission Matching

Implement glob pattern matching for permissions.

- [x] 1.2.2.1 Implement `check_permission/3` function
- [x] 1.2.2.2 Use custom glob-to-regex pattern matching (since :fnmatch not available)
- [x] 1.2.2.3 Check deny patterns first (highest priority)
- [x] 1.2.2.4 Check ask patterns second
- [x] 1.2.2.5 Check allow patterns last
- [x] 1.2.2.6 Return `:allow`, `:deny`, or `:ask`

### 1.2.3 Permission Parsing

Parse permission configuration from JSON.

- [x] 1.2.3.1 Implement `from_json/1` function
- [x] 1.2.3.2 Parse allow/deny/ask arrays from JSON
- [x] 1.2.3.3 Validate pattern format
- [x] 1.2.3.4 Return `{:ok, permissions}` or `{:error, reason}`

### 1.2.4 Permission Defaults

Define default permission configurations.

- [x] 1.2.4.1 Create `defaults/0` function
- [x] 1.2.4.2 Define safe default permissions
- [x] 1.2.4.3 Allow common tools (Read, Write, Edit)
- [x] 1.2.4.4 Deny dangerous operations (rm -rf, etc.)
- [x] 1.2.4.5 Return default Permission struct

---

## 1.3 Settings Schema Extension

Update the existing settings schema to include extensibility fields.

### 1.3.1 Schema Module Updates

Update `lib/jido_code/settings.ex` with extensibility fields.

- [x] 1.3.1.1 Add `:channels` field (map of String.t() => ChannelConfig.t())
- [x] 1.3.1.2 Add `:permissions` field (Permissions.t())
- [x] 1.3.1.3 Add `:hooks` field (map of event_type => list of hook configs)
- [x] 1.3.1.4 Add `:agents` field (map of agent_name => agent_config)
- [x] 1.3.1.5 Add `:plugins` field (plugin configuration map)
- [x] 1.3.1.6 Mark all extensibility fields as optional (backward compatibility)

### 1.3.2 Plugin Configuration Schema

Define the plugin configuration schema.

- [x] 1.3.2.1 Add `:enabled` field (list of plugin names)
- [x] 1.3.2.2 Add `:disabled` field (list of plugin names)
- [x] 1.3.2.3 Add `:marketplaces` field (map of marketplace configs)
- [x] 1.3.2.4 Define marketplace config structure:
  ```elixir
  %{
    "community" => %{
      "source" => "github",
      "repo" => "jidocode/plugin-marketplace"
    }
  }
  ```

### 1.3.3 Hook Configuration Schema

Define the hook configuration schema for settings.

- [x] 1.3.3.1 Define hook config structure:
  ```elixir
  %{
    "matcher" => "Edit",           # Tool/action to match
    "hooks" => [
      %{
        "type" => "command",       # command, elixir, channel, signal, prompt
        "command" => "...",        # Type-specific fields
        "timeout" => 5000
      }
    ]
  }
  ```
- [x] 1.3.3.2 Add validation for hook types
- [x] 1.3.3.3 Add validation for required fields per hook type

### 1.3.4 Agent Configuration Schema

Define the agent configuration schema.

- [x] 1.3.4.1 Define agent config structure:
  ```elixir
  %{
    "default_model" => "sonnet",
    "max_concurrent" => 5
  }
  ```
- [x] 1.3.4.2 Add validation for model names
- [x] 1.3.4.3 Add validation for numeric limits

---

## 1.4 Settings Merge Strategy

Extend the settings merge logic to handle extensibility fields.

### 1.4.1 Merge Function Updates

Update `JidoCode.Settings.deep_merge/2` for extensibility fields.

- [x] 1.4.1.1 Add pattern matching for extensibility fields
- [x] 1.4.1.2 Implement channel merge (local overrides global)
- [x] 1.4.1.3 Implement permission merge (local extends global)
- [x] 1.4.1.4 Implement hook merge (concatenate lists)
- [x] 1.4.1.5 Implement plugin merge (union of enabled, concatenate disabled)

### 1.4.2 Deep Merge for Hooks

Implement deep merge logic for hook configurations.

- [x] 1.4.2.1 Implement `merge_hooks/2` function
- [x] 1.4.2.2 Match on event type keys
- [x] 1.4.2.3 Concatenate hook lists by event type
- [x] 1.4.2.4 Preserve order (global hooks first, then local)
- [x] 1.4.2.5 Return merged hooks map

### 1.4.3 Array Merge for Plugins

Implement array merge logic for plugin lists.

- [x] 1.4.3.1 Implement `merge_plugins/2` function
- [x] 1.4.3.2 Union enabled lists (remove duplicates)
- [x] 1.4.3.3 Keep disabled lists from both sources
- [x] 1.4.3.4 Local disabled merged with global
- [x] 1.4.3.5 Return merged plugin configuration

### 1.4.4 Backward Compatibility

Ensure settings work without extensibility fields.

- [x] 1.4.4.1 Handle missing extensibility fields gracefully
- [x] 1.4.4.2 Provide empty defaults for all extensibility fields
- [x] 1.4.4.3 Test with old settings.json files
- [x] 1.4.4.4 Verify existing functionality unchanged

---

## 1.5 Unit Tests for Configuration

Comprehensive unit tests for configuration components.

### 1.5.1 ChannelConfig Tests

- [x] Test ChannelConfig struct creation
- [x] Test validate/1 with valid socket URL
- [x] Test validate/1 rejects invalid socket URL
- [x] Test validate/1 rejects invalid topic format
- [x] Test expand_env_vars/1 expands ${VAR} syntax
- [x] Test expand_env_vars/1 supports defaults ${VAR:-default}
- [x] Test expand_env_vars/1 handles missing variables
- [x] Test defaults/0 returns expected channel configs

### 1.5.2 Permissions Tests

- [x] Test Permissions struct creation
- [x] Test check_permission/3 allows matching pattern
- [x] Test check_permission/3 denies matching deny pattern
- [x] Test check_permission/3 asks matching ask pattern
- [x] Test check_permission/3 deny takes precedence over allow
- [x] Test check_permission/3 wildcards match correctly
- [x] Test from_json/1 parses valid JSON
- [x] Test from_json/1 rejects invalid format
- [x] Test defaults/0 returns safe permissions

### 1.5.3 Settings Merge Tests

- [x] Test merge adds extensibility fields
- [x] Test merge_channels/2 uses local over global
- [x] Test merge_permissions/2 extends global with local
- [x] Test merge_hooks/2 concatenates hook lists
- [x] Test merge_plugin_lists/2 unions enabled lists
- [x] Test merge with missing extensibility fields
- [x] Test merge with empty local settings

### 1.5.4 Backward Compatibility Tests

- [x] Test settings load without extensibility fields
- [x] Test settings save includes extensibility fields
- [x] Test existing settings files still work
- [x] Test defaults are applied for missing fields

---

## 1.6 Phase 1 Integration Tests

Comprehensive integration tests for settings system extensibility support.

### 1.6.1 Settings Loading Integration

- [x] Test: Load global settings with extensibility config
- [x] Test: Load local settings with extensibility config
- [x] Test: Merge global and local extensibility settings
- [x] Test: Local channel config overrides global
- [x] Test: Local permissions extend global
- [x] Test: Hooks concatenate from both sources
- [x] Test: Plugins merge correctly

### 1.6.2 Permission System Integration

- [x] Test: Allow permission permits matching action
- [x] Test: Deny permission blocks matching action
- [x] Test: Ask permission returns ask decision
- [x] Test: Deny takes precedence over allow
- [x] Test: Multiple patterns match correctly
- [x] Test: Wildcard patterns work as expected
- [x] Test: No matching pattern returns default

### 1.6.3 Channel Configuration Integration

- [x] Test: Channel config loads from settings
- [x] Test: Environment variables expand in auth
- [x] Test: Invalid channel config rejected
- [x] Test: Default channels used when not specified
- [x] Test: Channel validation works

### 1.6.4 Backward Compatibility Integration

- [x] Test: Old settings files without extensibility load
- [x] Test: Settings save includes extensibility structure
- [x] Test: Existing settings functionality unchanged
- [x] Test: Migration from old to new format

---

## Phase 1 Success Criteria

1. **ChannelConfig**: Struct defined with validation and env expansion
2. **Permissions**: Glob-based matching with allow/deny/ask outcomes
3. **Settings Schema**: Extended with extensibility fields
4. **Merge Strategy**: Proper merging of all extensibility fields
5. **Backward Compatibility**: Old settings files still work
6. **Test Coverage**: Minimum 80% for Phase 1 modules

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_code/extensibility/channel_config.ex`
- `lib/jido_code/extensibility/permissions.ex`
- `lib/jido_code/settings/schema.ex` (update)

**Test Files:**
- `test/jido_code/extensibility/channel_config_test.exs`
- `test/jido_code/extensibility/permissions_test.exs`
- `test/jido_code/settings/schema_test.exs` (update)
- `test/jido_code/integration/phase1_config_test.exs`
