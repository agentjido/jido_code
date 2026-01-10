# Feature Planning: Section 4.4 - Command Execution

## 1. Problem Statement

JidoCode needs a way to execute registered commands by name. Users should be able to invoke commands via slash syntax (e.g., `/commit` or `/review --mode strict`), and the system should dispatch the command to the appropriate Jido.Action with proper context, signals, and channel broadcasting.

### Current State
- Command struct and macro exist (section 4.1 complete)
- CommandParser can load commands from markdown (section 4.2 complete)
- CommandRegistry manages loaded commands (section 4.3 complete)
- No dispatcher or slash parser exists yet

### Goals
1. Create SlashParser for parsing slash command syntax
2. Create CommandDispatcher for executing commands
3. Support arguments, flags, and quoted strings
4. Emit signals for command lifecycle events
5. Broadcast to configured channels

## 2. Solution Overview

Create two modules for command execution:

1. **SlashParser** - Parse slash command strings into structured data
   - Extract command name
   - Parse positional arguments
   - Parse flags (`--flag value`) and short flags (`-f value`)
   - Handle quoted strings (`"hello world"`)

2. **CommandDispatcher** - Execute parsed commands
   - Look up command from registry
   - Build execution context
   - Execute the Jido.Action
   - Emit signals (started, completed, failed)
   - Broadcast to channels

## 3. Technical Details

### File Structure
```
lib/jido_code/extensibility/
  slash_parser.ex          # Parse slash command syntax
  command_dispatcher.ex     # Execute commands
```

### Dependencies
- `JidoCode.Extensibility.CommandRegistry` - Command lookup
- `Jido.Action` - Command execution
- `Phoenix.PubSub` - Signal emission and broadcasting

### SlashParser API

```elixir
%ParsedCommand{
  command: "commit",
  args: ["file1.ex", "file2.ex"],
  flags: %{"amend" => true, "message" => "fix bug"}
}
```

### CommandDispatcher API

```elixir
{:ok, result} = CommandDispatcher.dispatch(%ParsedCommand{}, context)
{:error, {:not_found, "unknown"}} = CommandDispatcher.dispatch(...)
```

## 4. Success Criteria

1. **SlashParser module** created with full parsing support
2. **CommandDispatcher module** created with execution flow
3. **Argument parsing** handles positional args, flags, quoted strings
4. **Command lookup** via registry
5. **Signal emission** for started/completed/failed events
6. **Channel broadcasting** to configured channels
7. **Test coverage** > 80%
8. **All tests pass**

## 5. Implementation Plan

### Step 1: Create SlashParser Module
- [x] 4.4.2.1 Create `lib/jido_code/extensibility/slash_parser.ex`
- [x] 4.4.2.2 Define ParsedCommand struct
- [x] 4.4.2.3 Implement `parse/1` for basic command extraction
- [x] 4.4.2.4 Implement positional argument parsing
- [x] 4.4.2.5 Implement flag parsing (`--flag value`)
- [x] 4.4.2.6 Implement short flag parsing (`-f value`)
- [x] 4.4.2.7 Implement quoted string parsing
- [x] 4.4.2.8 Handle edge cases (empty input, malformed input)

### Step 2: Create CommandDispatcher Module
- [x] 4.4.1.1 Create `lib/jido_code/extensibility/command_dispatcher.ex`
- [x] 4.4.1.2 Implement `dispatch/2` with parsed command and context
- [x] 4.4.1.3 Add command lookup from registry
- [x] 4.4.1.4 Add signal emission for lifecycle events
- [x] 4.4.1.5 Add Jido.Action execution
- [x] 4.4.1.6 Add error handling for missing commands
- [x] 4.4.1.7 Add error handling for execution failures

### Step 3: Implement Context Building
- [x] 4.4.3.1 Implement `build_context/2` function
- [x] 4.4.3.2 Add tool permissions from command config
- [x] 4.4.3.3 Add model override from command config
- [x] 4.4.3.4 Add channel config to context
- [x] 4.4.3.5 Add signal routing to context

### Step 4: Implement Channel Broadcasting
- [x] 4.4.4.1 Implement `broadcast_execution/4` function
- [x] 4.4.4.2 Broadcast command_started event
- [x] 4.4.4.3 Broadcast command_completed event
- [x] 4.4.4.4 Broadcast command_failed event
- [x] 4.4.4.5 Include command name and status in payload

### Step 5: Write Tests
- [x] 4.5.6.1 Test dispatcher looks up command
- [x] 4.5.6.2 Test dispatch emits started signal
- [x] 4.5.6.3 Test dispatch executes action
- [x] 4.5.6.4 Test dispatch emits completed signal
- [x] 4.5.6.5 Test dispatch broadcasts to channels
- [x] 4.5.6.6 Test dispatch handles missing command
- [x] 4.5.6.7 Test dispatch handles execution errors
- [x] 4.5.7.1 Test slash parser extracts command name
- [x] 4.5.7.2 Test slash parser extracts arguments
- [x] 4.5.7.3 Test slash parser handles quoted strings
- [x] 4.5.7.4 Test slash parser handles flags
- [x] 4.5.7.5 Test slash parser handles short flags
- [x] 4.5.7.6 Test slash parser converts to map
- [x] 4.5.7.7 Test slash parser handles edge cases

### Step 6: Documentation
- [x] 4.4.x.1 Add @moduledoc to SlashParser
- [x] 4.4.x.2 Add @moduledoc to CommandDispatcher
- [x] 4.4.x.3 Add examples in documentation
- [x] 4.4.x.4 Document public API functions

## 6. Notes and Considerations

### 6.1 Slash Command Syntax

Supported syntax:
- `/command` - Command only
- `/command arg1 arg2` - With positional arguments
- `/command --flag value` - With long flag
- `/command -f value` - With short flag
- `/command "quoted string"` - With quoted string
- `/commit --amend -m "fix bug" src/` - Combined syntax

### 6.2 Flag Syntax

- Long flags: `--flag value` (requires value)
- Boolean flags: `--flag` (treated as true)
- Short flags: `-f value` (single character)
- Short boolean: `-f` (treated as true)

### 6.3 Context Building

The execution context should include:
- Tool permissions from command config
- Model override (if specified)
- Channel configuration
- Signal routing configuration
- User-provided parameters

### 6.4 Signal Types

Emitted signals:
- `{"command:started", %{command: name, params: params}}`
- `{"command:completed", %{command: name, result: result}}`
- `{"command:failed", %{command: name, error: reason}}`

### 6.5 Channel Broadcasting

Broadcast to channels specified in command config:
- `command_started` - When command begins execution
- `command_progress` - During execution (for long-running commands)
- `command_completed` - When command succeeds
- `command_failed` - When command errors

### 6.6 Future Work (Not in Scope)
- Command help system
- Command aliases
- Command composition (piping commands)
- Interactive command prompts
- Command timeout handling

## 7. Implementation Status

**Current Status**: Complete

### Completed Steps
- [x] Planning document created
- [x] Feature branch created
- [x] 4.4.2 SlashParser module (37 tests passing)
- [x] 4.4.1 CommandDispatcher module (26 tests passing)
- [x] 4.4.3 Context building
- [x] 4.4.4 Channel broadcasting
- [x] 4.4.x Tests (63 total tests, all passing)
- [x] 4.4.x Documentation

### Files Created
- `lib/jido_code/extensibility/slash_parser.ex` - Slash command parsing (256 lines)
- `lib/jido_code/extensibility/command_dispatcher.ex` - Command execution dispatcher (360 lines)
- `test/jido_code/extensibility/slash_parser_test.exs` - SlashParser tests (270 lines)
- `test/jido_code/extensibility/command_dispatcher_test.exs` - CommandDispatcher tests (441 lines)
