# Feature Planning: Section 4.3 - Command Registry

## 1. Problem Statement

JidoCode needs a centralized registry to manage dynamically loaded commands. The CommandParser can generate modules from markdown files, but we need a way to:

1. Register commands in a centralized location
2. Look up commands by name or module
3. List all available commands
4. Support fuzzy search for command discovery
5. Automatically discover and load commands from directories
6. Unload commands when no longer needed

### Current State
- CommandParser exists and can generate modules from markdown (section 4.2 complete)
- Command struct exists with the Command macro (section 4.1 complete)
- No registry exists to manage loaded commands

### Goals
1. Create ETS-backed CommandRegistry for fast lookups
2. Implement command registration/unregistration
3. Support command lookup by name and module
4. Implement automatic command discovery from directories
5. Emit signals on registration/unregistration

## 2. Solution Overview

Create a `CommandRegistry` GenServer that:
- Uses ETS for O(1) command lookups
- Maintains name-based and module-based indexes
- Scans predefined directories for markdown command files
- Registers valid commands automatically
- Emits signals on registry changes

### Key Design Decisions

1. **GenServer-based**: Use GenServer for state management with ETS for fast lookups
2. **Dual indexes**: Maintain both by_name and by_module maps for flexibility
3. **Automatic discovery**: Scan ~/.jido_code/commands/*.md and .jido_code/commands/*.md
4. **Local overrides global**: Local .jido_code/ commands take precedence over global
5. **Signal emission**: Emit `command:registered` and `command:unregistered` signals

## 3. Technical Details

### File Structure
```
lib/jido_code/extensibility/
  command_registry.ex     # GenServer-based registry
```

### Dependencies
- `GenServer` - For state management
- `ETS` - For fast O(1) lookups
- `JidoCode.Extensibility.CommandParser` - For loading commands from files
- `Jido.Signal` - For emitting registration events

### Registry State

```elixir
defstruct [
  by_name: %{},      # name => Command struct
  by_module: %{},   # module => Command struct
  table: nil        # ETS table for fast lookups
]
```

### ETS Table

- **Name**: `:jido_command_registry`
- **Type**: `:set` (unique keys)
- **Read concurrency**: `true`
- **Access**: `:protected`

## 4. Success Criteria

1. **CommandRegistry GenServer** created with ETS backing
2. **register_command/1** stores and validates commands
3. **get_command/1** retrieves by name
4. **get_by_module/1** retrieves by module
5. **list_commands/0** returns all registered commands
6. **find_command/1** performs fuzzy search
7. **scan_commands_directory/1** discovers and loads commands
8. **unregister_command/1** removes commands
9. **Test coverage** > 80%
10. **All tests pass**

## 5. Implementation Plan

### Step 1: Create CommandRegistry GenServer
- [ ] 4.3.1.1 Create `lib/jido_code/extensibility/command_registry.ex`
- [ ] 4.3.1.2 Define Registry state struct
- [ ] 4.3.1.3 Implement `start_link/1` with GenServer
- [ ] 4.3.1.4 Implement `init/1` creating ETS table
- [ ] 4.3.1.5 Implement `terminate/2` for cleanup

### Step 2: Implement Command Registration
- [ ] 4.3.2.1 Implement `register_command/1` public API
- [ ] 4.3.2.2 Validate command before registration
- [ ] 4.3.2.3 Check for name conflicts
- [ ] 4.3.2.4 Store in ETS table and state maps
- [ ] 4.3.2.5 Emit `command:registered` signal
- [ ] 4.3.2.6 Return `{:ok, command}` or `{:error, reason}`

### Step 3: Implement Command Lookup
- [ ] 4.3.3.1 Implement `get_command/1` - Get by name (check ETS first)
- [ ] 4.3.3.2 Implement `get_by_module/1` - Get by module
- [ ] 4.3.3.3 Implement `list_commands/0` - List all commands
- [ ] 4.3.3.4 Implement `find_command/1` - Fuzzy search by name
- [ ] 4.3.3.5 Implement `registered?/1` - Check if command is registered

### Step 4: Implement Command Discovery
- [ ] 4.3.4.1 Implement `scan_commands_directory/1` public API
- [ ] 4.3.4.2 Implement `scan_all_commands/0` for global + local dirs
- [ ] 4.3.4.3 Handle directory not found gracefully
- [ ] 4.3.4.4 Parse each markdown file with CommandParser
- [ ] 4.3.4.5 Generate and register valid commands
- [ ] 4.3.4.6 Skip invalid files with warning
- [ ] 4.3.4.7 Return `{loaded, skipped, errors}` summary

### Step 5: Implement Command Unloading
- [ ] 4.3.5.1 Implement `unregister_command/1` public API
- [ ] 4.3.5.2 Remove from ETS table
- [ ] 4.3.5.3 Remove from state maps
- [ ] 4.3.5.4 Emit `command:unregistered` signal
- [ ] 4.3.5.5 Return `:ok` or `{:error, :not_found}`

### Step 6: Write Tests
- [ ] 4.3.6.1 Test registry starts and stops successfully
- [ ] 4.3.6.2 Test register_command stores command
- [ ] 4.3.6.3 Test register_command rejects duplicates
- [ ] 4.3.6.4 Test get_command retrieves by name
- [ ] 4.3.6.5 Test get_by_module retrieves by module
- [ ] 4.3.6.6 Test list_commands returns all
- [ ] 4.3.6.7 Test find_command does fuzzy matching
- [ ] 4.3.6.8 Test registered? checks command existence
- [ ] 4.3.6.9 Test unregister_command removes command
- [ ] 4.3.6.10 Test scan_commands_directory finds files
- [ ] 4.3.6.11 Test scan_commands_directory returns summary
- [ ] 4.3.6.12 Test local overrides global commands

### Step 7: Documentation
- [ ] 4.3.7.1 Add @moduledoc to CommandRegistry
- [ ] 4.3.7.2 Add examples in documentation
- [ ] 4.3.7.3 Document public API functions
- [ ] 4.3.7.4 Document signal emission

## 6. Notes and Considerations

### 6.1 Command Directories

Commands are discovered from two locations:
1. **Global**: `~/.jido_code/commands/*.md`
2. **Local**: `.jido_code/commands/*.md` (project-specific)

Local commands override global commands with the same name.

### 6.2 Name Conflicts

When registering a command with an existing name:
- Return `{:error, {:already_registered, name}}`
- Allow explicit force-replace via `register_command(command, force: true)`

### 6.3 Module Unloading

Generated modules cannot be truly unloaded in BEAM. The registry:
- Removes the command from lookup tables
- Clears ETS entries
- Emits unregistered signal
- The module remains in memory but inaccessible via registry

### 6.4 Signal Types

Emitted signals:
- `{"command:registered", %{name: name, command: command}}`
- `{"command:unregistered", %{name: name}}`

### 6.5 Future Work (Not in Scope)
- Command hot-reloading
- Command dependencies
- Command versioning
- Command sandboxing
- Command dispatcher (section 4.4)
- Slash parser (section 4.4)

## 7. Implementation Status

**Current Status**: Complete

### Completed Steps
- [x] Planning document created
- [x] Feature branch created
- [x] 4.3.1 CommandRegistry GenServer
- [x] 4.3.2 Command registration
- [x] 4.3.3 Command lookup
- [x] 4.3.4 Command discovery
- [x] 4.3.5 Command unloading
- [x] 4.3.6 Tests (31 tests, all passing)
- [x] 4.3.7 Documentation

### Files Created
- `lib/jido_code/extensibility/command_registry.ex` - GenServer-based ETS-backed registry (480+ lines)
- `test/jido_code/extensibility/command_registry_test.exs` - Comprehensive test suite (455 lines)
