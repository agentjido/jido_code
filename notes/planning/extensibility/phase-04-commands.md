# Phase 4: Command System

This phase implements markdown-based slash commands as Jido Actions, with frontmatter parsing, tool permissions, and channel broadcasting. Commands are the primary user-facing extensibility feature.

## Command System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Command Discovery                          │
│  ~/.jido_code/commands/*.md + .jido_code/commands/*.md       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Parse
┌─────────────────────────────────────────────────────────────┐
│                 Frontmatter Parser                           │
│  - name, description, model, tools                           │
│  - jido: schema, channels, signal routing                    │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Generate
┌─────────────────────────────────────────────────────────────┐
│              Dynamic Module Compilation                       │
│  Module.create/3 → Jido.Action compliant module              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Register
┌─────────────────────────────────────────────────────────────┐
│                   Command Registry                            │
│  ETS-backed: name => Command struct                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Execute
┌─────────────────────────────────────────────────────────────┐
│                 Command Dispatcher                           │
│  Emit signal → Execute Action → Broadcast → Complete        │
└─────────────────────────────────────────────────────────────┘
```

---

## 4.1 Command Definition Module

Define the structure and macros for command definitions.

### 4.1.1 Command Macro

Create macro for defining commands as Jido Actions.

- [ ] 4.1.1.1 Create `lib/jido_code/extensibility/command.ex`
- [ ] 4.1.1.2 Define `__using__/1` macro:
  ```elixir
  defmacro __using__(opts) do
    quote do
      use Jido.Action,
        name: unquote(opts[:name]),
        description: unquote(opts[:description]),
        schema: unquote(opts[:schema] || Zoi.object(%{}))

      @command_config unquote(opts)

      @impl true
      def run(params, context) do
        # Command execution logic
      end
    end
  end
  ```
- [ ] 4.1.1.3 Store command config in module attribute
- [ ] 4.1.1.4 Add `__command_config__/0` callback

### 4.1.2 Command Struct

Define the command data structure.

- [ ] 4.1.2.1 Define Command struct:
  ```elixir
  defmodule JidoCode.Extensibility.Command do
    @moduledoc """
    Command definition for slash commands.

    ## Fields

    - `:name` - Command name (used for /command invocation)
    - `:description` - Command description
    - `:module` - Underlying Jido.Action module
    - `:model` - LLM model override (optional)
    - `:tools` - Allowed tools for command execution
    - `:prompt` - Parsed markdown body (system prompt)
    - `:channels` - Channel configuration for broadcasting
    - `:schema` - Zoi schema for parameters
    - `:source_path` - Path to markdown file
    """

    @type t :: %__MODULE__{
      name: String.t(),
      description: String.t(),
      module: module(),
      model: String.t() | nil,
      tools: [String.t()] | nil,
      prompt: String.t(),
      channels: map() | nil,
      schema: term(),
      source_path: String.t() | nil
    }

    defstruct [
      :name,
      :description,
      :module,
      :model,
      :tools,
      :prompt,
      :channels,
      :schema,
      :source_path
    ]
  end
  ```

---

## 4.2 Markdown Command Parser

Parse markdown command files with YAML frontmatter.

### 4.2.1 Frontmatter Parser

Create parser for YAML frontmatter extraction.

- [ ] 4.2.1.1 Create `lib/jido_code/extensibility/parser/frontmatter.ex`
- [ ] 4.2.1.2 Implement `parse/1` function:
  ```elixir
  def parse(content) do
    case String.split(content, ~r/\n---\n/, parts: 2) do
      [frontmatter, body] ->
        yaml = parse_yaml(frontmatter)
        {yaml, String.trim(body)}

      _ ->
        {:error, :no_frontmatter}
    end
  end
  ```
- [ ] 4.2.1.3 Use `YamlElixir` for YAML parsing
- [ ] 4.2.1.4 Handle missing frontmatter gracefully
- [ ] 4.2.1.5 Return `{frontmatter_map, body}` or error

### 4.2.2 Command Frontmatter Fields

Parse command-specific frontmatter fields.

- [ ] 4.2.2.1 Parse `name` field (required)
- [ ] 4.2.2.2 Parse `description` field (required)
- [ ] 4.2.2.3 Parse `model` field (optional, default: "sonnet")
- [ ] 4.2.2.4 Parse `tools` field (comma-separated list)
- [ ] 4.2.2.5 Parse `jido` extension map
- [ ] 4.2.2.6 Validate required fields present

### 4.2.3 Jido Extension Parsing

Parse jido-specific frontmatter fields.

- [ ] 4.2.3.1 Parse `jido.schema` (Zoi schema format)
- [ ] 4.2.3.2 Parse `jido.channels.broadcast_to`
- [ ] 4.2.3.3 Parse `jido.channels.events` map
- [ ] 4.2.3.4 Parse `jido.signals.emit` list
- [ ] 4.2.3.5 Parse `jido.signals.subscribe` list

### 4.2.4 Tool Permission Parsing

Parse tools field into permission rules.

- [ ] 4.2.4.1 Implement `parse_tools/1` function
- [ ] 4.2.4.2 Parse comma-separated list: "Read, Write, Bash(git:*)"
- [ ] 4.2.4.3 Support wildcard patterns in tool names
- [ ] 4.2.4.4 Support parenthetical restrictions: "Bash(git:*)"
- [ ] 4.2.4.5 Return list of tool permission strings

### 4.2.5 Channel Directive Parser

Parse @channel() directives in markdown body.

- [ ] 4.2.5.1 Implement `parse_channel_directives/1` function
- [ ] 4.2.5.2 Match `@channel(event) {payload}` pattern
- [ ] 4.2.5.3 Match `@channel(channel:event) {payload}` variant
- [ ] 4.2.5.4 Extract event name and payload template
- [ ] 4.2.5.5 Return list of `{channel, event, template}` tuples

### 4.2.6 Module Generator

Generate dynamic module from parsed markdown.

- [ ] 4.2.6.1 Implement `from_markdown/1` in Command module
- [ ] 4.2.6.2 Parse frontmatter and body
- [ ] 4.2.6.3 Build unique module name from path:
  ```elixir
  "JidoCode.Extensibility.Commands.#{sanitize_name(Path.basename(path, ".md"))}"
  ```
- [ ] 4.2.6.4 Build Zoi schema from frontmatter
- [ ] 4.2.6.5 Use `Module.create/3` to compile module
- [ ] 4.2.6.6 Return `{:ok, Command struct}` or `{:error, reason}`

---

## 4.3 Command Registry

Registry for managing loaded commands.

### 4.3.1 Registry Module

Create ETS-backed command registry.

- [ ] 4.3.1.1 Create `lib/jido_code/extensibility/command_registry.ex`
- [ ] 4.3.1.2 Use GenServer for registry management
- [ ] 4.3.1.3 Define Registry state:
  ```elixir
  defstruct [
    by_name: %{},      # name => Command struct
    by_module: %{},   # module => Command struct
    table: nil        # ETS table for fast lookups
  ]
  ```
- [ ] 4.3.1.4 Implement `start_link/1`
- [ ] 4.3.1.5 Implement `init/1` creating ETS table

### 4.3.2 Command Registration

Implement command registration functions.

- [ ] 4.3.2.1 Implement `register_command/1`
- [ ] 4.3.2.2 Validate command before registration
- [ ] 4.3.2.3 Check for name conflicts
- [ ] 4.3.2.4 Store in ETS table and state maps
- [ ] 4.3.2.5 Emit `command/registered` signal
- [ ] 4.3.2.6 Return `{:ok, command}` or `{:error, reason}`

### 4.3.3 Command Lookup

Implement command lookup functions.

- [ ] 4.3.3.1 Implement `get_command/1` - Get by name
- [ ] 4.3.3.2 Implement `get_by_module/1` - Get by module
- [ ] 4.3.3.3 Implement `list_commands/0` - List all
- [ ] 4.3.3.4 Implement `find_command/1` - Fuzzy search by name
- [ ] 4.3.3.5 Support partial name matching

### 4.3.4 Command Discovery

Discover and load commands from directories.

- [ ] 4.3.4.1 Implement `scan_commands_directory/1`
- [ ] 4.3.4.2 Scan `~/.jido_code/commands/*.md`
- [ ] 4.3.4.3 Scan `.jido_code/commands/*.md`
- [ ] 4.3.4.4 Parse each markdown file
- [ ] 4.3.4.5 Register valid commands
- [ ] 4.3.4.6 Skip invalid files with warning
- [ ] 4.3.4.7 Return `{loaded, skipped, errors}` summary

### 4.3.5 Command Unloading

Implement command removal.

- [ ] 4.3.5.1 Implement `unregister_command/1`
- [ ] 4.3.5.2 Remove from ETS table
- [ ] 4.3.5.3 Remove from state maps
- [ ] 4.3.5.4 Emit `command/unregistered` signal
- [ ] 4.3.5.5 Return `:ok` or `{:error, :not_found}`

---

## 4.4 Command Execution

Execute commands with proper tool access and channel broadcasting.

### 4.4.1 Command Dispatcher

Create dispatcher for command execution.

- [ ] 4.4.1.1 Create `lib/jido_code/extensibility/command_dispatcher.ex`
- [ ] 4.4.1.2 Implement `dispatch/2` with command name and params
- [ ] 4.4.1.3 Look up command from registry
- [ ] 4.4.1.4 Emit `command/started` signal
- [ ] 4.4.1.5 Execute command action via `Jido.Action.run/2`
- [ ] 4.4.1.6 Emit `command/completed` or `command/failed` signal
- [ ] 4.4.1.7 Broadcast to configured channels
- [ ] 4.4.1.8 Return `{:ok, result}` or `{:error, reason}`

### 4.4.2 Slash Command Parser

Parse slash command syntax.

- [ ] 4.4.2.1 Create `lib/jido_code/extensibility/slash_parser.ex`
- [ ] 4.4.2.2 Implement `parse/1` for slash command strings
- [ ] 4.4.2.3 Parse `/command arg1 arg2` syntax
- [ ] 4.4.2.4 Support quoted arguments: `/cmd "hello world"`
- [ ] 4.4.2.5 Support flag syntax: `/cmd --flag value`
- [ ] 4.4.2.6 Support short flags: `/cmd -f value`
- [ ] 4.4.2.7 Convert to parameter map for action

### 4.4.3 Command Context

Build execution context for commands.

- [ ] 4.4.3.1 Implement `build_context/2` function
- [ ] 4.4.3.2 Include tool permissions in context
- [ ] 4.4.3.3 Include model override in context
- [ ] 4.4.3.4 Include channel config in context
- [ ] 4.4.3.5 Include signal routing in context

### 4.4.4 Channel Broadcasting

Broadcast command execution to channels.

- [ ] 4.4.4.1 Implement `broadcast_execution/4` function
- [ ] 4.4.4.2 Broadcast command_started event
- [ ] 4.4.4.3 Broadcast command_progress event (for long-running)
- [ ] 4.4.4.4 Broadcast command_completed event
- [ ] 4.4.4.5 Include command name and status in payload
- [ ] 4.4.4.6 Handle channel disconnects gracefully

---

## 4.5 Unit Tests for Command System

Comprehensive unit tests for command components.

### 4.5.1 Command Macro Tests

- [ ] Test __using__ generates correct structure
- [ ] Test __command_config__ returns config
- [ ] Test module is Jido.Action compliant

### 4.5.2 Parser Tests

- [ ] Test parse extracts frontmatter and body
- [ ] Test parse handles missing frontmatter
- [ ] Test parse_yaml parses valid YAML
- [ ] Test parse_tools parses tool list
- [ ] Test parse_tools handles wildcards
- [ ] Test parse_tools handles restrictions
- [ ] Test parse_channel_directives finds @channel() calls
- [ ] Test parse_channel_directives extracts event and template

### 4.5.3 Module Generation Tests

- [ ] Test from_markdown generates valid module
- [ ] Test from_markdown includes frontmatter fields
- [ ] Test from_markdown creates unique name
- [ ] Test from_markdown handles invalid input
- [ ] Test generated module can be called

### 4.5.4 Registry Tests

- [ ] Test registry starts successfully
- [ ] Test register_command stores command
- [ ] Test register_command rejects duplicates
- [ ] Test get_command retrieves by name
- [ ] Test get_by_module retrieves by module
- [ ] Test list_commands returns all
- [ ] Test find_command does fuzzy match
- [ ] Test unregister_command removes command

### 4.5.5 Discovery Tests

- [ ] Test scan_commands_directory finds .md files
- [ ] Test scan_commands_directory parses files
- [ ] Test scan_commands_directory registers valid
- [ ] Test scan_commands_directory skips invalid
- [ ] Test scan_commands_directory returns summary
- [ ] Test local overrides global commands

### 4.5.6 Dispatcher Tests

- [ ] Test dispatch looks up command
- [ ] Test dispatch emits started signal
- [ ] Test dispatch executes action
- [ ] Test dispatch emits completed signal
- [ ] Test dispatch broadcasts to channels
- [ ] Test dispatch handles missing command
- [ ] Test dispatch handles execution errors

### 4.5.7 Slash Parser Tests

- [ ] Test parse extracts command name
- [ ] Test parse extracts arguments
- [ ] Test parse handles quoted strings
- [ ] Test parse handles flags
- [ ] Test parse handles short flags
- [ ] Test parse converts to map

---

## 4.6 Phase 4 Integration Tests

Comprehensive integration tests for command system.

### 4.6.1 Command Lifecycle Integration

- [ ] Test: Load command from markdown file
- [ ] Test: Execute command and receive result
- [ ] Test: Local commands override global
- [ ] Test: Invalid commands are rejected
- [ ] Test: Command unregistration works

### 4.6.2 Command Execution Integration

- [ ] Test: Command executes with allowed tools
- [ ] Test: Command denied for disallowed tools
- [ ] Test: Command broadcasts to channels
- [ ] Test: Command errors are handled
- [ ] Test: Command signals are emitted

### 4.6.3 Slash Command Integration

- [ ] Test: Parse slash command string
- [ ] Test: Execute parsed command
- [ ] Test: Handle command with arguments
- [ ] Test: Handle command with flags
- [ ] Test: Handle quoted arguments

### 4.6.4 End-to-End Command Flow

- [ ] Test: Create markdown command file
- [ ] Test: System discovers command
- [ ] Test: User invokes /command
- [ ] Test: Command executes with LLM
- [ ] Test: Result returned to user
- [ ] Test: Channels receive updates

---

## Phase 4 Success Criteria

1. **Command Macro**: Generates Jido.Action compliant modules
2. **Frontmatter Parser**: Extracts all command fields correctly
3. **Module Generator**: Creates valid dynamic modules
4. **Command Registry**: ETS-backed with fast lookups
5. **Command Dispatcher**: Executes with signals and broadcasting
6. **Slash Parser**: Handles all argument formats
7. **Test Coverage**: Minimum 80% for Phase 4 modules

---

## Phase 4 Critical Files

**New Files:**
- `lib/jido_code/extensibility/command.ex`
- `lib/jido_code/extensibility/parser/frontmatter.ex`
- `lib/jido_code/extensibility/command_registry.ex`
- `lib/jido_code/extensibility/command_dispatcher.ex`
- `lib/jido_code/extensibility/slash_parser.ex`

**Test Files:**
- `test/jido_code/extensibility/command_test.exs`
- `test/jido_code/extensibility/parser/frontmatter_test.exs`
- `test/jido_code/extensibility/command_registry_test.exs`
- `test/jido_code/extensibility/command_dispatcher_test.exs`
- `test/jido_code/extensibility/slash_parser_test.exs`
- `test/jido_code/integration/phase4_commands_test.exs`
