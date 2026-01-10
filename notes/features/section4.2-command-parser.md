# Feature Planning: Section 4.2 - Markdown Command Parser

## 1. Problem Statement

JidoCode needs a parser for markdown-based command definitions that can be converted into Jido.Action-compliant modules. While the `AgentParser` exists for SubAgent definitions, a separate `CommandParser` is needed for Commands because:

1. Commands use `Jido.Action` instead of `Jido.Agent` as the base
2. Commands have different frontmatter requirements
3. Commands need different module generation logic
4. Commands may have command-specific parsing needs (tool permissions, etc.)

### Current State
- `AgentParser` exists and parses markdown to `SubAgent` structs
- `Command` struct exists with the Command macro (section 4.1 complete)
- No parser exists for markdown -> Command conversion

### Goals
1. Create `CommandParser` module similar to `AgentParser`
2. Reuse frontmatter parsing logic from `AgentParser`
3. Generate Jido.Action-compliant modules from markdown files
4. Support all Command struct fields from frontmatter

## 2. Solution Overview

Create a `CommandParser` module that:
- Mirrors the `AgentParser` pattern for consistency
- Parses markdown files with YAML frontmatter into `Command` structs
- Generates dynamic modules using the Command macro from section 4.1
- Provides `parse_file/1`, `generate_module/1`, and `load_and_generate/1` functions

### Key Design Decisions

1. **Reuse over Copy**: Extract shared frontmatter parsing to a `Frontmatter` module
2. **Consistent API**: `CommandParser` follows the same API pattern as `AgentParser`
3. **Module Naming**: Generated modules follow pattern `JidoCode.Extensibility.Commands.<SanitizedName>`

## 3. Technical Details

### File Structure
```
lib/jido_code/extensibility/
  command_parser.ex       # Command-specific markdown parsing
  parser/
    frontmatter.ex        # Shared YAML frontmatter parsing (extracted from AgentParser)
```

### Dependencies
- `Jido.Action` - Base action behavior
- `JidoCode.Extensibility.Command` - Command struct and macro from section 4.1
- `Zoi` - Schema validation

### Frontmatter Schema for Commands

#### Required Fields
- `name` (string): Command identifier (kebab-case, unique)
- `description` (string): Human-readable description

#### Optional Fields
- `model` (string): LLM model identifier (default: from config)
- `tools` (list of string): Allowed tool names (default: [])

#### Nested `jido` Section
- `jido.schema` (map): NimbleOptions schema definition for command parameters
- `jido.channels` (map): Channel broadcasting configuration
- `jido.signals` (map): Signal emit/subscribe configuration

## 4. Success Criteria

1. **CommandParser module** created with parsing functions
2. **parse_file/1** parses markdown files into Command structs
3. **generate_module/1** creates Jido.Action-compliant modules
4. **load_and_generate/1** combines parsing and module generation
5. **Test coverage** > 80%
6. **All tests pass**

## 5. Implementation Plan

### Step 1: Create Shared Frontmatter Parser Module
- [ ] 4.2.1.1 Create `lib/jido_code/extensibility/parser/frontmatter.ex`
- [ ] 4.2.1.2 Extract frontmatter parsing logic from AgentParser
- [ ] 4.2.1.3 Extract YAML parsing logic to shared module
- [ ] 4.2.1.4 Extract schema conversion logic
- [ ] 4.2.1.5 Add tests for frontmatter module

### Step 2: Create CommandParser Module
- [ ] 4.2.2.1 Create `lib/jido_code/extensibility/command_parser.ex`
- [ ] 4.2.2.2 Implement `parse_file/1` function
- [ ] 4.2.2.3 Implement `parse_frontmatter/1` (delegates to Frontmatter module)
- [ ] 4.2.2.4 Implement `build_command_attrs/3` function
- [ ] 4.2.2.5 Implement schema parsing for Commands

### Step 3: Implement Module Generation
- [ ] 4.2.3.1 Implement `generate_module/1` function
- [ ] 4.2.3.2 Build macro options from Command struct
- [ ] 4.2.3.3 Use `Module.create/3` with Command macro
- [ ] 4.2.3.4 Handle module creation errors

### Step 4: Convenience Functions
- [ ] 4.2.4.1 Implement `load_and_generate/1` function
- [ ] 4.2.4.2 Add documentation examples

### Step 5: Write Tests
- [ ] 4.2.5.1 Test parse_file with valid command markdown
- [ ] 4.2.5.2 Test parse_file with minimal frontmatter
- [ ] 4.2.5.3 Test parse_file handles missing frontmatter
- [ ] 4.2.5.4 Test parse_file handles missing required fields
- [ ] 4.2.5.5 Test generate_module creates valid module
- [ ] 4.2.5.6 Test generated module is Jido.Action-compliant
- [ ] 4.2.5.7 Test load_and_generate combines parsing and generation
- [ ] 4.2.5.8 Test schema parsing works correctly

### Step 6: Refactor AgentParser
- [ ] 4.2.6.1 Update AgentParser to use shared Frontmatter module
- [ ] 4.2.6.2 Ensure AgentParser tests still pass
- [ ] 4.2.6.3 Update AgentParser documentation

### Step 7: Documentation
- [ ] 4.2.7.1 Add @moduledoc to CommandParser
- [ ] 4.2.7.2 Add examples in documentation
- [ ] 4.2.7.3 Document frontmatter schema

## 6. Notes and Considerations

### 6.1 Reuse from AgentParser
The CommandParser should mirror AgentParser's structure:
- Same function signatures where applicable
- Same error handling patterns
- Same module generation approach

### 6.2 Differences from AgentParser

| Aspect | AgentParser | CommandParser |
|--------|-------------|---------------|
| Struct | SubAgent | Command |
| Base Behavior | Jido.Agent | Jido.Action |
| Callback | on_before_cmd/2 | run/2 |
| Module Namespace | JidoCode.Extensibility.Agents.* | JidoCode.Extensibility.Commands.* |
| Name Sanitization | snake_case for Agent | snake_case for Action name |

### 6.3 Module Naming
Both use the same sanitization function (kebab-case -> CamelCase):
- `my-command` -> `JidoCode.Extensibility.Commands.MyCommand`
- `my-command` -> `JidoCode.Extensibility.Agents.MyCommand`

### 6.4 Future Work (Not in Scope)
- Command registry (section 4.3)
- Command dispatcher (section 4.4)
- Slash parser (section 4.4)

## 7. Implementation Status

**Current Status**: Complete

### Completed Steps
- [x] Planning document created
- [x] Feature branch created
- [x] 4.2.1 Shared Frontmatter parser module
- [x] 4.2.2 CommandParser module
- [x] 4.2.3 Module generation
- [x] 4.2.4 Convenience functions
- [x] 4.2.5 Tests (91 tests total: 60 for CommandParser/Frontmatter, 31 for AgentParser)
- [x] 4.2.6 AgentParser refactored to use Frontmatter
- [x] 4.2.7 Documentation

### Files Created
- `lib/jido_code/extensibility/parser/frontmatter.ex` - Shared YAML frontmatter parser (350+ lines)
- `lib/jido_code/extensibility/command_parser.ex` - Command-specific markdown parser (200+ lines)
- `test/jido_code/extensibility/parser/frontmatter_test.exs` - Frontmatter tests (350+ lines)
- `test/jido_code/extensibility/command_parser_test.exs` - CommandParser tests (470+ lines)

### Files Modified
- `lib/jido_code/extensibility/agent_parser.ex` - Refactored to use shared Frontmatter module (reduced from 592 to 321 lines)
