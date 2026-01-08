# Phase 5: Plugin Registry

This phase implements plugin discovery, loading, lifecycle management, and dependency resolution. Plugins are bundles of commands, agents, skills, and hooks that can be distributed and installed.

## Plugin System Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Plugin Discovery                           │
│  ~/.jido_code/plugins/*/.jido-plugin/plugin.json             │
│  .jido_code/plugins/*/.jido-plugin/plugin.json               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Parse Manifest
┌─────────────────────────────────────────────────────────────┐
│                   Plugin Manifest                             │
│  - name, version, description, author, license               │
│  - elixir: application, mix_deps                             │
│  - components: commands, agents, skills, hooks paths         │
│  - channels, signals, mcp_servers                            │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Validate & Resolve
┌─────────────────────────────────────────────────────────────┐
│              Dependency Resolution                            │
│  - Build dependency graph                                    │
│  - Detect circular dependencies                              │
│  - Determine load order                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Load
┌─────────────────────────────────────────────────────────────┐
│                 Plugin Loader                                 │
│  - Load components (commands, agents, skills, hooks)         │
│  - Register with respective registries                       │
│  - Track plugin state                                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼ Manage
┌─────────────────────────────────────────────────────────────┐
│                 Plugin Lifecycle                              │
│  enable → disable → reload → unload                          │
└─────────────────────────────────────────────────────────────┘
```

---

## 5.1 Plugin Manifest Schema

Define the plugin manifest structure and validation.

### 5.1.1 Manifest Struct

Create the plugin manifest data structure.

- [ ] 5.1.1.1 Create `lib/jido_code/extensibility/plugin/manifest.ex`
- [ ] 5.1.1.2 Define Manifest struct:
  ```elixir
  defmodule JidoCode.Extensibility.Plugin.Manifest do
    @moduledoc """
    Plugin manifest defining plugin metadata and components.

    ## Fields

    - `:name` - Unique plugin identifier
    - `:version` - Semantic version
    - `:description` - Plugin description
    - `:author` - Author information (map with name, email)
    - `:license` - License identifier (SPDX)
    - `:repository` - Repository URL
    - `:keywords` - List of keywords for discovery
    - `:elixir` - Elixir-specific configuration
    - `:commands` - Path to commands directory
    - `:agents` - Path or list of agent definitions
    - `:skills` - Path to skills directory
    - `:hooks` - Path to hooks configuration
    - `:channels` - Required and optional channels
    - `:signals` - Emits and subscribes signal paths
    - `:mcp_servers` - MCP server configurations
    - `:source_path` - Path to plugin root
    """

    @type t :: %__MODULE__{
      name: String.t(),
      version: String.t(),
      description: String.t(),
      author: map() | nil,
      license: String.t() | nil,
      repository: String.t() | nil,
      keywords: [String.t()] | nil,
      elixir: map() | nil,
      commands: String.t() | nil,
      agents: String.t() | [String.t()] | nil,
      skills: String.t() | nil,
      hooks: String.t() | nil,
      channels: map() | nil,
      signals: map() | nil,
      mcp_servers: map() | nil,
      source_path: String.t() | nil
    }

    defstruct [
      :name,
      :version,
      :description,
      :author,
      :license,
      :repository,
      :keywords,
      :elixir,
      :commands,
      :agents,
      :skills,
      :hooks,
      :channels,
      :signals,
      :mcp_servers,
      :source_path
    ]
  end
  ```

### 5.1.2 Elixir Configuration Schema

Define Elixir-specific configuration structure.

- [ ] 5.1.2.1 Define elixir config map structure:
  ```elixir
  %{
    "application" => "MyPluginApp",        # OTP app name
    "mix_deps" => [                        # Dependencies
      {:jido, "~> 2.0"},
      {:other_dep, "~> 1.0"}
    ]
  }
  ```
- [ ] 5.1.2.2 Validate application name is valid atom
- [ ] 5.1.2.3 Validate mix_deps format

### 5.1.3 Channels Configuration Schema

Define channels configuration structure.

- [ ] 5.1.3.1 Define channels config map:
  ```elixir
  %{
    "required" => ["ui_state"],           # Required channels
    "optional" => ["notifications"]       # Optional channels
  }
  ```
- [ ] 5.1.3.2 Validate channel names
- [ ] 5.1.3.3 Check availability of required channels

### 5.1.4 Signals Configuration Schema

Define signals configuration structure.

- [ ] 5.1.4.1 Define signals config map:
  ```elixir
  %{
    "emits" => [
      "plugin/event",
      "custom/signal"
    ],
    "subscribes" => [
      "lifecycle/**",
      "tool/**"
    ]
  }
  ```
- [ ] 5.1.4.2 Validate signal path format
- [ ] 5.1.4.3 Register subscriptions on load

---

## 5.2 Plugin Registry

Central registry for managing loaded plugins.

### 5.2.1 Plugin Registry GenServer

Create the plugin registry.

- [ ] 5.2.1.1 Create `lib/jido_code/extensibility/plugin/registry.ex`
- [ ] 5.2.1.2 Use GenServer for registry management
- [ ] 5.2.1.3 Define Registry state:
  ```elixir
  defstruct [
    plugins: %{},           # name => Plugin struct
    by_status: %{},        # status => [plugin_names]
    dependencies: %{},      # name => [dependency_names]
    dependents: %{},       # name => [dependent_names]
    table: nil             # ETS table for fast lookups
  ]
  ```
- [ ] 5.2.1.4 Implement `start_link/1`
- [ ] 5.2.1.5 Implement `init/1` creating ETS table

### 5.2.2 Plugin Registration

Implement plugin registration functions.

- [ ] 5.2.2.1 Implement `register_plugin/1`
- [ ] 5.2.2.2 Parse and validate manifest
- [ ] 5.2.2.3 Check for name conflicts
- [ ] 5.2.2.4 Check dependency availability
- [ ] 5.2.2.5 Create Plugin struct with status: :loaded
- [ ] 5.2.2.6 Store in registry
- [ ] 5.2.2.7 Emit `plugin/loaded` signal on success
- [ ] 5.2.2.8 Emit `plugin/error` signal on failure

### 5.2.3 Plugin Queries

Implement plugin lookup functions.

- [ ] 5.2.3.1 Implement `get_plugin/1` - Get by name
- [ ] 5.2.3.2 Implement `list_plugins/0` - List all
- [ ] 5.2.3.3 Implement `list_plugins_by_status/1` - Filter by status
- [ ] 5.2.3.4 Implement `get_plugin_capabilities/1` - Get capabilities
- [ ] 5.2.3.5 Implement `plugin_enabled?/1` - Check if enabled
- [ ] 5.2.3.6 Implement `get_plugin_dependencies/1` - Get dependencies

### 5.2.4 Plugin State Management

Manage plugin state transitions.

- [ ] 5.2.4.1 Implement `set_plugin_status/2` - Change status
- [ ] 5.2.4.2 Update status in plugins map
- [ ] 5.2.4.3 Update by_status index
- [ ] 5.2.4.4 Emit status change signal
- [ ] 5.2.4.5 Return `{:ok, plugin}` or `{:error, reason}`

---

## 5.3 Plugin Loader

Load plugin components from manifest.

### 5.3.1 Loader Module

Create the plugin loader.

- [ ] 5.3.1.1 Create `lib/jido_code/extensibility/plugin/loader.ex`
- [ ] 5.3.1.2 Define Loader struct:
  ```elixir
  defstruct [
    registry: nil,        # Plugin registry PID
    command_registry: nil,
    agent_registry: nil,
    skill_registry: nil,
    hook_registry: nil
  ]
  ```

### 5.3.2 Component Discovery

Discover and load plugin components.

- [ ] 5.3.2.1 Implement `load_commands/2` - Load command components
- [ ] 5.3.2.2 Scan plugin commands directory
- [ ] 5.3.2.3 Parse each command markdown file
- [ ] 5.3.2.4 Register with CommandRegistry
- [ ] 5.3.2.5 Return loaded count

- [ ] 5.3.2.6 Implement `load_agents/2` - Load agent components
- [ ] 5.3.2.7 Scan plugin agents directory
- [ ] 5.3.2.8 Parse each agent markdown file
- [ ] 5.3.2.9 Register with AgentRegistry
- [ ] 5.3.2.10 Return loaded count

- [ ] 5.3.2.11 Implement `load_skills/2` - Load skill components
- [ ] 5.3.2.12 Scan plugin skills directory
- [ ] 5.3.2.13 Parse each skill markdown file
- [ ] 5.3.2.14 Register with SkillRegistry
- [ ] 5.3.2.15 Return loaded count

- [ ] 5.3.2.16 Implement `load_hooks/2` - Load hook components
- [ ] 5.3.2.17 Read hooks configuration file
- [ ] 5.3.2.18 Parse hooks JSON
- [ ] 5.3.2.19 Register with HookRegistry
- [ ] 5.3.2.20 Return loaded count

### 5.3.3 Dependency Management

Resolve and manage plugin dependencies.

- [ ] 5.3.3.1 Implement `resolve_dependencies/1`
- [ ] 5.3.3.2 Build dependency graph from manifests
- [ ] 5.3.3.3 Use `libgraph` for graph operations
- [ ] 5.3.3.4 Detect circular dependencies
- [ ] 5.3.3.5 Return topological sort order
- [ ] 5.3.3.6 Return `{:ok, order}` or `{:error, :circular_deps}`

### 5.3.4 Plugin Lifecycle

Implement plugin lifecycle operations.

- [ ] 5.3.4.1 Implement `enable_plugin/2`
- [ ] 5.3.4.2 Check dependencies are enabled
- [ ] 5.3.4.3 Load all plugin components
- [ ] 5.3.4.4 Set status to :enabled
- [ ] 5.3.4.5 Return `{:ok, plugin}` or `{:error, reason}`

- [ ] 5.3.4.6 Implement `disable_plugin/2`
- [ ] 5.3.4.7 Unload plugin components
- [ ] 5.3.4.8 Check dependent plugins
- [ ] 5.3.4.9 Set status to :disabled
- [ ] 5.3.4.10 Return `:ok` or `{:error, reason}`

- [ ] 5.3.4.11 Implement `reload_plugin/2`
- [ ] 5.3.4.12 Disable plugin
- [ ] 5.3.4.13 Reload manifest from disk
- [ ] 5.3.4.14 Enable plugin
- [ ] 5.3.4.15 Return `{:ok, plugin}` or `{:error, reason}`

- [ ] 5.3.4.16 Implement `unload_plugin/2`
- [ ] 5.3.4.17 Disable plugin
- [ ] 5.3.4.18 Unregister from registry
- [ ] 5.3.4.19 Set status to :unloaded
- [ ] 5.3.4.20 Emit `plugin/unloaded` signal

---

## 5.4 Plugin Discovery

Discover plugins from configured directories.

### 5.4.1 Directory Scanning

Scan plugin directories for manifests.

- [ ] 5.4.1.1 Create `lib/jido_code/extensibility/plugin/discovery.ex`
- [ ] 5.4.1.2 Implement `scan_plugins_directory/1`
- [ ] 5.4.1.3 Scan `~/.jido_code/plugins/*/` directories
- [ ] 5.4.1.4 Look for `.jido-plugin/plugin.json` in each
- [ ] 5.4.1.5 Scan `.jido_code/plugins/*/` directories
- [ ] 5.4.1.6 Parse each found manifest
- [ ] 5.4.1.7 Skip invalid manifests with warning
- [ ] 5.4.1.8 Return list of valid manifests
- [ ] 5.4.1.9 Emit `plugin/discovered` signal for each

### 5.4.2 Marketplace Integration

Support plugin marketplace operations.

- [ ] 5.4.2.1 Create `lib/jido_code/extensibility/plugin/marketplace.ex`
- [ ] 5.4.2.2 Define Marketplace struct:
  ```elixir
  defstruct [
    :name,
    :source,          # :github, :git, :local
    :url,            # Repository URL
    :ref             # Git ref (branch, tag, commit)
  ]
  ```
- [ ] 5.4.2.3 Implement `fetch_plugin_list/1` for marketplace
- [ ] 5.4.2.4 Support GitHub repository listing
- [ ] 5.4.2.5 Parse plugin metadata from repo
- [ ] 5.4.2.6 Return list of available plugins

### 5.4.3 Plugin Installation

Install plugins from marketplace.

- [ ] 5.4.3.1 Implement `install_plugin/3` - Install from marketplace
- [ ] 5.4.3.2 Clone repository to plugins directory
- [ ] 5.4.3.3 Verify plugin.json exists
- [ ] 5.4.3.4 Parse and validate manifest
- [ ] 5.4.3.5 Register plugin
- [ ] 5.4.3.6 Return `{:ok, plugin}` or `{:error, reason}`

### 5.4.4 Plugin Updates

Check for and install plugin updates.

- [ ] 5.4.4.1 Implement `check_updates/0` - Check all plugins
- [ ] 5.4.4.2 Fetch latest version from repository
- [ ] 5.4.4.3 Compare with installed version
- [ ] 5.4.4.4 Return list of updatable plugins
- [ ] 5.4.4.5 Implement `update_plugin/2` - Update specific plugin
- [ ] 5.4.4.6 Git pull latest changes
- [ ] 5.4.4.7 Reload plugin

---

## 5.5 Unit Tests for Plugin System

Comprehensive unit tests for plugin components.

### 5.5.1 Manifest Tests

- [ ] Test Manifest struct creation
- [ ] Test parse_manifest/1 loads JSON
- [ ] Test parse_manifest/1 validates required fields
- [ ] Test parse_manifest/1 rejects invalid version
- [ ] Test parse_manifest/1 validates mix_deps format
- [ ] Test parse_manifest/1 validates signal paths

### 5.5.2 Registry Tests

- [ ] Test registry starts successfully
- [ ] Test register_plugin stores plugin
- [ ] Test register_plugin rejects duplicates
- [ ] Test register_plugin checks dependencies
- [ ] Test get_plugin retrieves by name
- [ ] Test list_plugins returns all
- [ ] Test list_plugins_by_status filters
- [ ] Test get_plugin_capabilities returns components
- [ ] Test set_plugin_status updates status
- [ ] Test unregister_plugin removes plugin

### 5.5.3 Loader Tests

- [ ] Test load_commands scans directory
- [ ] Test load_commands registers commands
- [ ] Test load_agents scans directory
- [ ] Test load_agents registers agents
- [ ] Test load_skills scans directory
- [ ] Test load_skills registers skills
- [ ] Test load_hooks parses config
- [ ] Test load_hooks registers hooks

### 5.5.4 Dependency Tests

- [ ] Test resolve_dependencies builds graph
- [ ] Test resolve_dependencies detects cycles
- [ ] Test resolve_dependencies returns order
- [ ] Test enable_plugin checks dependencies
- [ ] Test disable_plugin checks dependents

### 5.5.5 Discovery Tests

- [ ] Test scan_plugins_directory finds plugins
- [ ] Test scan_plugins_directory parses manifests
- [ ] Test scan_plugins_directory skips invalid
- [ ] Test fetch_plugin_list returns plugins
- [ ] Test install_plugin clones repo
- [ ] Test install_plugin registers plugin

### 5.5.6 Lifecycle Tests

- [ ] Test enable_plugin loads components
- [ ] Test enable_plugin sets status
- [ ] Test disable_plugin unloads components
- [ ] Test reload_plugin refreshes manifest
- [ ] Test unload_plugin removes from registry

---

## 5.6 Phase 5 Integration Tests

Comprehensive integration tests for plugin system.

### 5.6.1 Plugin Lifecycle Integration

- [ ] Test: Load plugin from manifest
- [ ] Test: Plugin components are registered
- [ ] Test: Enable plugin activates components
- [ ] Test: Disable plugin deactivates components
- [ ] Test: Plugin dependencies load in correct order
- [ ] Test: Circular dependencies detected

### 5.6.2 Plugin Discovery Integration

- [ ] Test: Discover plugins from global directory
- [ ] Test: Discover plugins from local directory
- [ ] Test: Invalid plugins are skipped
- [ ] Test: Plugin manifests parsed correctly
- [ ] Test: Duplicate plugin names handled

### 5.6.3 Marketplace Integration

- [ ] Test: Fetch plugin list from GitHub
- [ ] Test: Install plugin from marketplace
- [ ] Test: Installed plugin loads correctly
- [ ] Test: Check for updates
- [ ] Test: Update plugin to new version

### 5.6.4 End-to-End Plugin Flow

- [ ] Test: Install plugin from marketplace
- [ ] Test: Plugin loads components
- [ ] Test: Use plugin command
- [ ] Test: Use plugin agent
- [ ] Test: Disable plugin
- [ ] Test: Components removed
- [ ] Test: Uninstall plugin

---

## Phase 5 Success Criteria

1. **Manifest Schema**: Complete plugin metadata structure
2. **Plugin Registry**: ETS-backed with status tracking
3. **Component Loading**: Commands, agents, skills, hooks all load
4. **Dependency Resolution**: Graph-based ordering, cycle detection
5. **Lifecycle Management**: Enable/disable/reload/unload operations
6. **Marketplace Integration**: GitHub-based plugin discovery
7. **Test Coverage**: Minimum 80% for Phase 5 modules

---

## Phase 5 Critical Files

**New Files:**
- `lib/jido_code/extensibility/plugin/manifest.ex`
- `lib/jido_code/extensibility/plugin/registry.ex`
- `lib/jido_code/extensibility/plugin/loader.ex`
- `lib/jido_code/extensibility/plugin/discovery.ex`
- `lib/jido_code/extensibility/plugin/marketplace.ex`

**Test Files:**
- `test/jido_code/extensibility/plugin/manifest_test.exs`
- `test/jido_code/extensibility/plugin/registry_test.exs`
- `test/jido_code/extensibility/plugin/loader_test.exs`
- `test/jido_code/extensibility/plugin/discovery_test.exs`
- `test/jido_code/extensibility/plugin/marketplace_test.exs`
- `test/jido_code/integration/phase5_plugins_test.exs`
