# Phase 7: Skills Framework

This phase implements composable skills with action bundling, path-based routing, and result transformation. Skills bundle related actions together with routing logic for signal-based execution.

## Skills Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Skill Discovery                            │
│  ~/.jido_code/skills/*/SKILL.md                              │
│  .jido_code/skills/*/SKILL.md                                │
│  plugins/*/skills/*/SKILL.md                                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Parse
┌─────────────────────────────────────────────────────────────┐
│                 Skill Frontmatter Parser                      │
│  - name, description, version, allowed-tools                 │
│  - jido: actions, router, channels                           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Generate
┌─────────────────────────────────────────────────────────────┐
│              Jido.Skill Compliant Module                       │
│  - mount/2: Initialize skill state                           │
│  - router/1: Path → action mappings                          │
│  - handle_signal/2: Intercept signals                        │
│  - transform_result/3: Wrap results                          │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Mount
┌─────────────────────────────────────────────────────────────┐
│                   Skill Registry                               │
│  Skills mounted to agents, providing actions                 │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Route
┌─────────────────────────────────────────────────────────────┐
│              Signal → Action Router                           │
│  Path-based matching: "pdf/extract/text" → ExtractPdfText    │
└─────────────────────────────────────────────────────────────┘
```

---

## 7.1 Skill Definition Module

Define the structure for skill definitions.

### 7.1.1 Skill Macro

Create macro for defining skills as Jido Skills.

- [ ] 7.1.1.1 Create `lib/jido_code/extensibility/skill.ex`
- [ ] 7.1.1.2 Define `__using__/1` macro:
  ```elixir
  defmacro __using__(opts) do
    quote do
      use Jido.Skill,
        name: unquote(opts[:name]),
        state_key: unquote(opts[:state_key]),
        actions: unquote(opts[:actions] || [])

      @description unquote(opts[:description])
      @version unquote(opts[:version])
      @channel_config unquote(opts[:channels])
      @router_config unquote(opts[:router])
      @skill_doc unquote(opts[:skill_doc])

      @impl Jido.Skill
      def mount(agent, config) do
        {:ok, %{initialized_at: DateTime.utc_now()}}
      end

      @impl Jido.Skill
      def router(_config) do
        Enum.map(@router_config, fn {path, action} ->
          {path, %Jido.Instruction{action: action}}
        end)
      end

      @impl Jido.Skill
      def handle_signal(signal, _skill_opts) do
        case find_matching_route(signal.type, @router_config) do
          nil -> {:skip, signal}
          action -> {:ok, %Jido.Instruction{action: action, params: signal.data}}
        end
      end

      @impl Jido.Skill
      def transform_result(result, _action, _skill_opts) do
        if @channel_config do
          {:ok, result, [emit_channel_directive(result, @channel_config)]}
        else
          {:ok, result, []}
        end
      end
    end
  end
  ```
- [ ] 7.1.1.3 Include Jido.Skill behavior
- [ ] 7.1.1.4 Add skill documentation storage
- [ ] 7.1.1.5 Add router configuration

### 7.1.2 Skill Struct

Define the skill data structure.

- [ ] 7.1.2.1 Define Skill struct:
  ```elixir
  defmodule JidoCode.Extensibility.Skill do
    @moduledoc """
    Skill definition for composable capabilities.

    ## Fields

    - `:name` - Skill identifier
    - `:description` - Skill description
    - `:version` - Semantic version
    - `:module` - Generated Jido.Skill module
    - `:actions` - List of action modules
    - `:state_key` - Key for skill state in agent
    - `:router` - Path → action mappings
    - `:channels` - Channel configuration
    - `:documentation` - Skill documentation body
    - `:source_path` - Path to SKILL.md
    """

    @type t :: %__MODULE__{
      name: String.t(),
      description: String.t(),
      version: String.t(),
      module: module(),
      actions: [module()],
      state_key: atom(),
      router: [{String.t(), module()}],
      channels: map() | nil,
      documentation: String.t(),
      source_path: String.t() | nil
    }

    defstruct [
      :name,
      :description,
      :version,
      :module,
      :actions,
      :state_key,
      :router,
      :channels,
      :documentation,
      :source_path
    ]
  end
  ```

---

## 7.2 Skill Parser

Parse markdown skill definitions.

### 7.2.1 Skill Frontmatter Parser

Extend parser for skill-specific fields.

- [ ] 7.2.1.1 Add skill field parsing to frontmatter parser
- [ ] 7.2.1.2 Parse `name` (required)
- [ ] 7.2.1.3 Parse `description` (required)
- [ ] 7.2.1.4 Parse `version` (required, semver)
- [ ] 7.2.1.5 Parse `allowed-tools` (optional, comma-separated)
- [ ] 7.2.1.6 Parse `jido` extension map

### 7.2.2 Jido Skill Extensions

Parse jido-specific skill fields.

- [ ] 7.2.2.1 Parse `jido.skill_module` for custom module
- [ ] 7.2.2.2 Parse `jido.actions` list of action modules
- [ ] 7.2.2.3 Parse `jido.router` path → action mappings:
  ```yaml
  jido:
    router:
      - "pdf/extract/text": ExtractPdfText
      - "pdf/extract/tables": ExtractPdfTables
  ```
- [ ] 7.2.2.4 Parse `jido.channels.broadcast_to`
- [ ] 7.2.2.5 Parse `jido.channels.progress_events` (boolean)

### 7.2.3 Skill Module Generator

Generate Jido.Skill compliant module.

- [ ] 7.2.3.1 Implement `from_markdown/1` in Skill module
- [ ] 7.2.3.2 Parse SKILL.md frontmatter and body
- [ ] 7.2.3.3 Build unique module name:
  ```elixir
  skill_dir = Path.dirname(path)
  skill_name = Path.basename(Path.dirname(path))
  "JidoCode.Extensibility.Skills.#{sanitize_name(skill_name)}"
  ```
- [ ] 7.2.3.4 Build router from config
- [ ] 7.2.3.5 Build actions list from config
- [ ] 7.2.3.6 Use `Module.create/3` to compile
- [ ] 7.2.3.7 Return `{:ok, Skill struct}` or `{:error, reason}`

---

## 7.3 Skill Registry

Registry for managing skills.

### 7.3.1 Registry Module

Create ETS-backed skill registry.

- [ ] 7.3.1.1 Create `lib/jido_code/extensibility/skill_registry.ex`
- [ ] 7.3.1.2 Use GenServer for registry management
- [ ] 7.3.1.3 Define Registry state:
  ```elixir
  defstruct [
    by_name: %{},      # name => Skill struct
    by_module: %{},   # module => Skill struct
    by_action: %{},   # action => [skill_names]
    table: nil        # ETS table
  ]
  ```
- [ ] 7.3.1.4 Implement `start_link/1`
- [ ] 7.3.1.5 Implement `init/1` creating ETS table

### 7.3.2 Skill Registration

Implement skill registration functions.

- [ ] 7.3.2.1 Implement `register_skill/1`
- [ ] 7.3.2.2 Validate skill before registration
- [ ] 7.3.2.3 Check for name conflicts
- [ ] 7.3.2.4 Store in ETS table and state maps
- [ ] 7.3.2.5 Index by action modules
- [ ] 7.3.2.6 Emit `skill/registered` signal
- [ ] 7.3.2.7 Return `{:ok, skill}` or `{:error, reason}`

### 7.3.3 Skill Lookup

Implement skill lookup functions.

- [ ] 7.3.3.1 Implement `get_skill/1` - Get by name
- [ ] 7.3.3.2 Implement `get_by_module/1` - Get by module
- [ ] 7.3.3.3 Implement `list_skills/0` - List all
- [ ] 7.3.3.4 Implement `find_skill_by_action/1` - Find providing skill
- [ ] 7.3.3.5 Implement `get_skill_actions/1` - Get skill's actions

### 7.3.4 Skill Discovery

Discover and load skills from directories.

- [ ] 7.3.4.1 Implement `scan_skills_directory/1`
- [ ] 7.3.4.2 Scan `~/.jido_code/skills/*/SKILL.md`
- [ ] 7.3.4.3 Scan `.jido_code/skills/*/SKILL.md`
- [ ] 7.3.4.4 Scan plugin skill directories
- [ ] 7.3.4.5 Parse each SKILL.md file
- [ ] 7.3.4.6 Load associated script files if present
- [ ] 7.3.4.7 Register valid skills
- [ ] 7.3.4.8 Return `{loaded, skipped, errors}` summary

---

## 7.4 Skill Execution

Execute skill actions through agent routing.

### 7.4.1 Skill Router

Create router for path-based signal routing.

- [ ] 7.4.1.1 Create `lib/jido_code/extensibility/skill_router.ex`
- [ ] 7.4.1.2 Implement `route_signal/2` - Route signal to action
- [ ] 7.4.1.3 Get all skills from registry
- [ ] 7.4.1.4 Match signal path against skill routers
- [ ] 7.4.1.5 Support exact path match
- [ ] 7.4.1.6 Support wildcard segments: `pdf/*`
- [ ] 7.4.1.7 Support double wildcard: `**`
- [ ] 7.4.1.8 Return `{:ok, skill, action}` or `:no_match`

### 7.4.2 Path Matching

Implement path-based matching logic.

- [ ] 7.4.2.1 Implement `match_path/2` - Match path to pattern
- [ ] 7.4.2.2 Split paths by `/`
- [ ] 7.4.2.3 Match segments one by one
- [ ] 7.4.2.4 Handle `*` wildcard (single segment)
- [ ] 7.4.2.5 Handle `**` wildcard (multiple segments)
- [ ] 7.4.2.6 Return `{:ok, bindings}` or `:no_match`

### 7.4.3 Skill Result Transformation

Transform action results with channel broadcasting.

- [ ] 7.4.3.1 Implement `transform_result/3`
- [ ] 7.4.3.2 Check if skill has channel config
- [ ] 7.4.3.3 Create channel broadcast directive
- [ ] 7.4.3.4 Include skill context in broadcast
- [ ] 7.4.3.5 Include result in payload
- [ ] 7.4.3.6 Return `{:ok, result, directives}`

### 7.4.4 Skill Mounting

Mount skills to agents.

- [ ] 7.4.4.1 Implement `mount_skill/3` - Mount skill to agent
- [ ] 7.4.4.2 Get skill definition from registry
- [ ] 7.4.4.3 Call skill's mount/2 callback
- [ ] 7.4.4.4 Merge skill state into agent
- [ ] 7.4.4.5 Register skill's router
- [ ] 7.4.4.6 Return `{:ok, agent}` or `{:error, reason}`

---

## 7.5 Unit Tests for Skills Framework

Comprehensive unit tests for skill components.

### 7.5.1 Skill Macro Tests

- [ ] Test __using__ generates Jido.Skill compliant module
- [ ] Test mount/2 returns initialized state
- [ ] Test router/1 returns path mappings
- [ ] Test handle_signal/2 routes to actions
- [ ] Test transform_result/3 wraps with directives

### 7.5.2 Parser Tests

- [ ] Test from_markdown generates valid module
- [ ] Test from_markdown includes all frontmatter fields
- [ ] Test from_markdown parses router config
- [ ] Test from_markdown parses actions list
- [ ] Test from_markdown handles invalid input

### 7.5.3 Registry Tests

- [ ] Test registry starts successfully
- [ ] Test register_skill stores skill
- [ ] Test register_skill indexes by action
- [ ] Test get_skill retrieves by name
- [ ] Test get_by_module retrieves by module
- [ ] Test find_skill_by_action finds provider
- [ ] Test list_skills returns all
- [ ] Test unregister_skill removes skill

### 7.5.4 Router Tests

- [ ] Test route_signal finds matching skill
- [ ] Test route_signal handles exact match
- [ ] Test route_signal handles wildcard match
- [ ] Test route_signal handles double wildcard
- [ ] Test route_signal returns :no_match when none
- [ ] Test match_path matches exact paths
- [ ] Test match_path matches * wildcard
- [ ] Test match_path matches ** wildcard

### 7.5.5 Discovery Tests

- [ ] Test scan_skills_directory finds SKILL.md files
- [ ] Test scan_skills_directory parses skills
- [ ] Test scan_skills_directory loads scripts
- [ ] Test scan_skills_directory registers valid
- [ ] Test scan_skills_directory skips invalid

---

## 7.6 Phase 7 Integration Tests

Comprehensive integration tests for skills framework.

### 7.6.1 Skill Lifecycle Integration

- [ ] Test: Load skill from markdown
- [ ] Test: Mount skill to agent
- [ ] Test: Skill state initializes correctly
- [ ] Test: Skill actions available to agent
- [ ] Test: Unmount skill removes actions

### 7.6.2 Skill Routing Integration

- [ ] Test: Exact path match routes correctly
- [ ] Test: Wildcard path match routes correctly
- [ ] Test: Double wildcard routes correctly
- [ ] Test: Multiple skills with overlapping paths
- [ ] Test: Skill router precedence

### 7.6.3 Skill Execution Integration

- [ ] Test: Route signal through skill
- [ ] Test: Execute skill action
- [ ] Test: Transform result with channel broadcast
- [ ] Test: Skill error handling
- [ ] Test: Skill state updates

### 7.6.4 End-to-End Skill Flow

- [ ] Test: Define skill in SKILL.md
- [ ] Test: System discovers skill
- [ ] Test: User sends matching signal
- [ ] Test: Skill action executes
- [ ] Test: Result returned with broadcast
- [ ] Test: Channel receives update

---

## Phase 7 Success Criteria

1. **Skill Macro**: Generates Jido.Skill compliant modules
2. **Parser**: Extracts all skill fields correctly
3. **Registry**: ETS-backed with action indexing
4. **Router**: Path-based routing with wildcards
5. **Mounting**: Skills integrate with agent state
6. **Transformation**: Results wrapped with channel directives
7. **Test Coverage**: Minimum 80% for Phase 7 modules

---

## Phase 7 Critical Files

**New Files:**
- `lib/jido_code/extensibility/skill.ex`
- `lib/jido_code/extensibility/skill_registry.ex`
- `lib/jido_code/extensibility/skill_router.ex`

**Test Files:**
- `test/jido_code/extensibility/skill_test.exs`
- `test/jido_code/extensibility/skill_registry_test.exs`
- `test/jido_code/extensibility/skill_router_test.exs`
- `test/jido_code/integration/phase7_skills_test.exs`
