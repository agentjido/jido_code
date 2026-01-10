# Feature Planning: Section 4.1 - Command Definition Module

## 1. Problem Statement

JidoCode needs a flexible, markdown-based command system that allows users to define custom slash commands (like `/commit`, `/review`) as declarative markdown files. These commands should be compiled into Jido.Action-compliant modules that can be executed with proper tool permissions, signal emission, and channel broadcasting.

### Current Limitations
- Commands are hardcoded in the application
- No way for users to define custom commands
- No tool permission system for commands
- No signal emission integration for command lifecycle

### Goals
1. Enable markdown-based command definitions
2. Generate Jido.Action-compliant modules dynamically
3. Support tool permissions and restrictions
4. Integrate with signal system for lifecycle events
5. Support channel broadcasting for command progress

## 2. Solution Overview

Build a Command Definition Module similar to the SubAgent module, with:
- **Command struct** to hold parsed command definition
- **`__using__/1` macro** to generate Jido.Action-compliant modules
- Helper functions for module naming and sanitization

This mirrors the SubAgent pattern already implemented in section 2.2, providing consistency in the codebase.

## 3. Technical Details

### File Structure
```
lib/jido_code/extensibility/
  command.ex              # Command struct and __using__ macro
  parser/
    frontmatter.ex        # YAML frontmatter parsing (reused from AgentParser)
  command_parser.ex       # Command-specific markdown parsing
```

### Dependencies
- `Jido.Action` - Base action module from Jido v2
- `Zoi` - Schema validation
- `Jido.Signal` - Signal emission for command lifecycle

### Key Design Decisions

#### 3.1 Command Struct Fields
```elixir
%JidoCode.Extensibility.Command{
  name: "commit",           # Command name (for /commit invocation)
  description: "Create git commit",
  module: MyCommandModule,  # Generated Jido.Action module
  model: "anthropic:...",   # Optional LLM override
  tools: ["read_file"],     # Allowed tools
  prompt: "System prompt",  # From markdown body
  schema: [...],            # Parameter schema
  channels: [...],          # Channel config
  signals: [...],           # Signal config
  source_path: "/path/to/command.md"
}
```

#### 3.2 Macro Design
The `__using__/1` macro will:
1. Use `Jido.Action` with provided configuration
2. Store command config as module attributes
3. Implement `run/2` callback with signal emission
4. Provide accessor functions

#### 3.3 Naming Convention
- Module names: `JidoCode.Extensibility.Commands.<SanitizedName>`
- Sanitization: kebab-case/snake_case → CamelCase

### 4. Success Criteria

1. **Command struct** defined with Zoi schema
2. **`__using__/1` macro** generates Jido.Action-compliant modules
3. **Helper functions** for naming and struct operations
4. **Test coverage** > 80%
5. **All tests pass**

## 5. Implementation Plan

### Step 1: Create Command Struct
- [ ] 4.1.2.1 Define `lib/jido_code/extensibility/command.ex`
- [ ] 4.1.2.2 Define Zoi schema for Command struct
- [ ] 4.1.2.3 Add `new/1` and `new!/1` functions
- [ ] 4.1.2.4 Add `to_map/1` for serialization

### Step 2: Implement Command Macro
- [ ] 4.1.1.1 Implement `__using__/1` macro
- [ ] 4.1.1.2 Store config as module attributes
- [ ] 4.1.1.3 Implement `run/2` callback wrapper
- [ ] 4.1.1.4 Add signal emission in callbacks
- [ ] 4.1.1.5 Provide accessor functions

### Step 3: Add Helper Functions
- [ ] 4.1.3.1 `sanitize_module_name/1` - name to CamelCase
- [ ] 4.1.3.2 `module_name/1` - full module path
- [ ] 4.1.3.3 Document helper functions

### Step 4: Write Tests
- [ ] 4.1.4.1 Test struct creation and validation
- [ ] 4.1.4.2 Test macro generates Jido.Action-compliant module
- [ ] 4.1.4.3 Test accessor functions
- [ ] 4.1.4.4 Test signal emission
- [ ] 4.1.4.5 Test naming functions

### Step 5: Documentation
- [ ] 4.1.5.1 Add @moduledoc to Command module
- [ ] 4.1.5.2 Add examples in documentation
- [ ] 4.1.5.3 Document macro options

## 6. Notes and Considerations

### 6.1 Reuse from SubAgent
The Command module should reuse patterns from SubAgent:
- Similar Zoi schema approach
- Similar `__using__/1` macro structure
- Same naming conventions

### 6.2 Differences from SubAgent
| Aspect | SubAgent | Command |
|--------|----------|---------|
| Base | `Jido.Agent` | `Jido.Action` |
| Callback | `on_before_cmd/2` | `run/2` |
| Purpose | Long-running agent | Single action |

### 6.3 Future Work (Not in Scope)
- Command parser (section 4.2)
- Command registry (section 4.3)
- Command dispatcher (section 4.4)
- Slash parser (section 4.4)

## 7. Implementation Status

**Current Status**: Complete

### Completed Steps
- [x] Planning document created
- [x] Feature branch created
- [x] 4.1.2 Command struct definition
- [x] 4.1.1 Command macro implementation
- [x] 4.1.3 Helper functions
- [x] 4.1.4 Tests (21 tests, all passing)
- [x] 4.1.5 Documentation

### Files Created
- `lib/jido_code/extensibility/command.ex` - Command struct and macro (366 lines)
- `test/jido_code/extensibility/command_test.exs` - Comprehensive test suite (227 lines)
