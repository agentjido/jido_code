# Settings Schema Extension Feature Planning

**Feature**: Section 1.3 & 1.4 - Settings Schema Extension & Merge Strategy (Extensibility Configuration)
**Branch**: feature/settings-schema-extension
**Status**: Complete
**Created**: 2026-01-09
**Completed**: 2026-01-09

## Problem Statement

The existing JidoCode Settings module only supports core LLM configuration (provider, model, providers list, models map). The extensibility system needs to store configuration for:

1. **Channels** - Phoenix channel configurations for real-time communication
2. **Permissions** - Access control patterns for extensibility components
3. **Hooks** - Event-driven hook configurations
4. **Agents** - Agent-specific settings
5. **Plugins** - Plugin management configuration

Without extending the settings schema, these extensibility configurations would need separate storage mechanisms, breaking the unified settings approach.

## Solution Overview

Extend the existing `JidoCode.Settings` module to include extensibility fields while maintaining backward compatibility:

1. Add new valid keys to `@valid_keys` map
2. Update type spec to include extensibility fields
3. Extend `deep_merge/2` to handle extensibility field merging with custom logic
4. Add validation for extensibility sub-fields

### Merge Strategy

- **channels**: Local overrides global (simple map merge)
- **permissions**: Local extends global (concatenate allow/deny/ask lists)
- **hooks**: Concatenate hook lists by event type
- **agents**: Local overrides global (simple map merge)
- **plugins**: Union enabled lists, keep disabled from both

## Technical Details

### File Locations

- **Module to modify**: `lib/jido_code/settings.ex`
- **Tests**: `test/jido_code/settings_test.exs` (create new)
- **Feature Plan**: `notes/features/settings-schema-extension.md` (this file)

### Dependencies

- `JidoCode.Extensibility.ChannelConfig` - Channel configuration validation
- `JidoCode.Extensibility.Permissions` - Permission parsing (if needed)

### Data Structures

#### Settings Schema Extension

```elixir
@valid_keys Map.merge(previous_keys, %{
  "channels" => :map_of_channel_configs,
  "permissions" => :permissions_config,
  "hooks" => :map_of_hook_lists,
  "agents" => :map_of_agent_configs,
  "plugins" => :plugins_config
})
```

#### Channel Config Format

```json
{
  "channels": {
    "ui_state": {
      "socket": "ws://localhost:4000/socket",
      "topic": "jido:ui",
      "auth": {"type": "token", "token": "${CHANNEL_TOKEN}"},
      "broadcast_events": ["state_change", "progress"]
    }
  }
}
```

#### Permissions Format

```json
{
  "permissions": {
    "allow": ["Read:*", "Write:*"],
    "deny": ["*delete*"],
    "ask": ["run_command:*"]
  }
}
```

#### Hooks Format

```json
{
  "hooks": {
    "Edit": [
      {
        "matcher": "Edit",
        "hooks": [
          {
            "type": "command",
            "command": "mix format --stdin-formatter-file $FILE"
          }
        ]
      }
    ]
  }
}
```

#### Plugins Format

```json
{
  "plugins": {
    "enabled": ["github", "git"],
    "disabled": ["experimental"],
    "marketplaces": {
      "community": {
        "source": "github",
        "repo": "jidocode/plugin-marketplace"
      }
    }
  }
}
```

## Success Criteria

1. ✅ Settings module updated with extensibility fields
2. ✅ Settings.validate/1 accepts extensibility fields
3. ✅ Settings.deep_merge/2 properly merges extensibility configurations
4. ✅ Backward compatibility maintained (old settings files still work)
5. ✅ 100% test coverage for new functionality
6. ✅ All tests pass
7. ✅ Credo shows no issues
8. ✅ Dialyzer shows no warnings

## Implementation Plan

### Step 1: Update valid_keys and Type Spec

- [ ] 1.1 Add extensibility fields to `@valid_keys` module attribute
- [ ] 1.2 Define new type validators for extensibility fields
- [ ] 1.3 Update `@type t()` to include extensibility fields

### Step 2: Add Validation Functions

- [ ] 2.1 Implement `validate_channels/1` - validates channel config map
- [ ] 2.2 Implement `validate_permissions/1` - validates permissions structure
- [ ] 2.3 Implement `validate_hooks/1` - validates hooks configuration
- [ ] 2.4 Implement `validate_agents/1` - validates agent config map
- [ ] 2.5 Implement `validate_plugins/1` - validates plugins configuration

### Step 3: Update Merge Logic

- [ ] 3.1 Extend `deep_merge/2` to handle extensibility fields
- [ ] 3.2 Implement `merge_channels/2` - local overrides global
- [ ] 3.3 Implement `merge_permissions/2` - concatenate permission lists
- [ ] 3.4 Implement `merge_hooks/2` - concatenate hook lists by event
- [ ] 3.5 Implement `merge_agents/2` - local overrides global
- [ ] 3.6 Implement `merge_plugins/2` - union enabled, intersection disabled

### Step 4: Update Documentation

- [ ] 4.1 Update `@moduledoc` with extensibility field documentation
- [ ] 4.2 Add examples for extensibility settings
- [ ] 4.3 Document merge behavior for extensibility fields

### Step 5: Create Tests

- [ ] 5.1 Test Settings.validate/1 with extensibility fields
- [ ] 5.2 Test Settings.load() merges extensibility fields correctly
- [ ] 5.3 Test each merge function individually
- [ ] 5.4 Test backward compatibility (missing extensibility fields)
- [ ] 5.5 Test invalid extensibility configurations

### Step 6: Verification

- [ ] 6.1 Run `mix compile` - no warnings
- [ ] 6.2 Run `mix credo --strict` - no issues
- [ ] 6.3 Run `mix dialyzer` - no warnings for new code
- [ ] 6.4 Run `mix test` - all tests pass

## Agent Consultations Performed

None required - this extends existing Settings module with well-understood patterns.

## Notes/Considerations

### Backward Compatibility

All extensibility fields are optional. Old settings files without these fields should continue to work exactly as before.

### Merge Semantics

Different extensibility fields have different merge semantics:
- **channels**: Local completely replaces global per-channel
- **permissions**: Lists are concatenated (local extends global)
- **hooks**: Hook lists are concatenated by event type
- **agents**: Local completely replaces global per-agent
- **plugins**: Enabled lists are unioned, disabled lists are merged

### Validation Approach

For simplicity, extensibility fields are validated at the top level (map structure). Deep validation of nested structures (like ChannelConfig) is deferred to when those modules are actually used. This keeps Settings.validate/1 fast while still catching type errors.

### Future Enhancements

1. Add settings migration system for schema version bumps
2. Add settings validation hooks for extensibility modules
3. Add hot-reload of extensibility settings
4. Add settings export/import functionality

## References

- **Existing Settings**: `lib/jido_code/settings.ex`
- **ChannelConfig**: `lib/jido_code/extensibility/channel_config.ex`
- **Permissions**: `lib/jido_code/extensibility/permissions.ex`
- **Extensibility Plan**: `notes/planning/extensibility/phase-01-configuration.md`
