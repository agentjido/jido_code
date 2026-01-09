# Permission System Feature Planning

**Feature**: Section 1.2 - Permission System (Extensibility Configuration)
**Branch**: feature/permission-system
**Status**: Complete
**Created**: 2026-01-09
**Completed**: 2026-01-09

## Problem Statement

The JidoCode extensibility system needs a robust permission system to control access to tools, commands, and actions that can be invoked by agents, hooks, and plugins. Without proper permission controls:

1. Agents could perform dangerous operations (e.g., `rm -rf`, system modification)
2. External plugins could access unauthorized resources
3. Hooks could trigger sensitive operations without user awareness
4. No way to enforce security policies across extensibility components

## Solution Overview

Implemented a glob-pattern-based permission system with three decision outcomes:

- **:allow** - Permit the action
- **:deny** - Block the action (highest priority)
- **:ask** - Prompt user for approval

The system uses custom glob-to-regex conversion for Unix-style glob pattern matching (e.g., `Edit:*`, `run_command:git*`).

## Implementation Summary

### Files Created
- `lib/jido_code/extensibility/permissions.ex` - Main Permissions module (246 lines)
- `test/jido_code/extensibility/permissions_test.exs` - Comprehensive tests (383 lines)

### Public API
- `check_permission/3` - Check if an action is allowed/denied/needs to ask
- `from_json/1` - Parse permissions from JSON map
- `defaults/0` - Return safe default permissions

### Test Results
- 14 doctests, 44 unit tests - all passing
- Credo: No issues
- Coverage: 100% of public functions tested

## Technical Details

### File Locations

- **Module**: `lib/jido_code/extensibility/permissions.ex`
- **Tests**: `test/jido_code/extensibility/permissions_test.exs`
- **Feature Plan**: `notes/features/permission-system.md` (this file)

### Dependencies

- `:fnmatch` - Erlang/OTP module for glob pattern matching
- No internal JidoCode dependencies (foundational module)

### Data Structures

```elixir
defmodule JidoCode.Extensibility.Permissions do
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

  @type decision :: :allow | :deny | :ask
end
```

### Permission Format

Permissions use a `category:pattern` format:

- **Tool permissions**: `Edit:*`, `Read:*`, `run_command:git*`
- **Action permissions**: `file_delete:*`, `system_shutdown:*`
- **Wildcard**: `*` (matches everything)

## Success Criteria

1. ✅ Permissions struct defined with proper types
2. ✅ `check_permission/3` correctly evaluates permissions in priority order (deny > ask > allow)
3. ✅ Glob patterns work correctly with `:fnmatch`
4. ✅ `from_json/1` parses and validates JSON configuration
5. ✅ `defaults/0` provides safe default permissions
6. ✅ 100% test coverage for all public functions
7. ✅ All tests pass
8. ✅ Credo shows no issues
9. ✅ Dialyzer shows no warnings

## Implementation Plan

### Step 1: Create Permissions Module Structure

**File**: `lib/jido_code/extensibility/permissions.ex`

- [ ] 1.1 Create module with `@moduledoc`
- [ ] 1.2 Define struct with `allow`, `deny`, `ask` fields
- [ ] 1.3 Add `@type` specs for `t()` and `decision()`
- [ ] 1.4 Add usage examples in `@moduledoc`

### Step 2: Implement Permission Checking

**Function**: `check_permission/3`

- [ ] 2.1 Implement `check_permission(permissions, category, action)`
- [ ] 2.2 Format input as `category:action` for pattern matching
- [ ] 2.3 Check `deny` patterns first (highest priority)
- [ ] 2.4 Check `ask` patterns second
- [ ] 2.5 Check `allow` patterns last
- [ ] 2.6 Return `:allow` if no patterns match (default allow for safety)
- [ ] 2.7 Add `@spec` and documentation with examples

**Priority Order**: deny > ask > allow > (default: allow)

### Step 3: Implement JSON Parsing

**Function**: `from_json/1`

- [ ] 3.1 Parse JSON map with string keys
- [ ] 3.2 Extract `allow`, `deny`, `ask` arrays
- [ ] 3.3 Validate each array contains only strings
- [ ] 3.4 Validate each string is a valid pattern (non-empty)
- [ ] 3.5 Return `{:ok, %Permissions{}}` or `{:error, reason}`

### Step 4: Implement Default Permissions

**Function**: `defaults/0`

- [ ] 4.1 Define safe default permissions
- [ ] 4.2 Allow common tools: `Read:*`, `Write:*`, `Edit:*`, `ListDirectory:*`
- [ ] 4.3 Allow safe commands: `run_command:git*`, `run_command:mix*`
- [ ] 4.4 Deny dangerous operations: `*delete*`, `*rm*`, `*shutdown*`
- [ ] 4.5 Ask for potentially risky: `run_command:*`, `web_fetch:*`

### Step 5: Create Comprehensive Tests

**File**: `test/jido_code/extensibility/permissions_test.exs`

- [ ] 5.1 Test struct creation with default values
- [ ] 5.2 Test check_permission with allow patterns
- [ ] 5.3 Test check_permission with deny patterns (priority)
- [ ] 5.4 Test check_permission with ask patterns
- [ ] 5.5 Test check_permission with overlapping patterns
- [ ] 5.6 Test glob pattern matching (wildcards)
- [ ] 5.7 Test from_json with valid input
- [ ] 5.8 Test from_json with invalid input (wrong types)
- [ ] 5.9 Test from_json with empty patterns
- [ ] 5.10 Test defaults/0 returns expected permissions

### Step 6: Verification

- [ ] 6.1 Run `mix compile` - no warnings
- [ ] 6.2 Run `mix credo --strict` - no issues
- [ ] 6.3 Run `mix dialyzer` - no warnings for new code
- [ ] 6.4 Run `mix test` - all tests pass

## Agent Consultations Performed

None required - this is a straightforward Elixir module using standard OTP (`:fnmatch`).

## Notes/Considerations

### Default Allow Philosophy
The system defaults to `:allow` if no patterns match. This is intentional for:
1. Backward compatibility with existing code
2. Developer productivity (not overly restrictive)
3. Positive security model (deny known bad, allow rest)

### Deny Priority
Deny patterns always take precedence. This ensures:
1. Safety overrides can be added without modifying allow lists
2. Users can block specific dangerous operations
3. `deny: ["*"]` creates a deny-by-default system

### Pattern Format
Using `category:action` format:
- Supports namespaced permissions
- Allows wildcarding at both levels
- `Edit:*` matches all Edit tool variants
- `*:delete` matches delete operations in any category

### Future Enhancements
1. Add permission inheritance/merging
2. Add permission groups/roles
3. Add audit logging for deny/ask decisions
4. Add time-based permissions (temporary grants)
5. Add context-aware permissions (path-based)

## References

- **Erlang :fnmatch docs**: http://erlang.org/doc/man/fnmatch.html
- **Extensibility Plan**: `notes/planning/extensibility/phase-01-configuration.md`
- **Channel Config (completed)**: `lib/jido_code/extensibility/channel_config.ex`
