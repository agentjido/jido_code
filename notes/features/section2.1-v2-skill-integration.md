# Section 2.1: Root Extensibility Module + JidoAI v2 Migration

**Document Version**: 1.0
**Date**: 2026-01-09
**Status**: Planning
**Branch**: `feature/section2.1-v2-skill-integration`
**Base Branch**: `extensibility`

---

## Problem Statement

The original section 2.1 plan focused on creating a root extensibility module. However, the discovery that jido_code uses **JidoAI v1 APIs** that no longer exist in the v2 branches significantly expands the scope.

### JidoAI v1 → v2 Breaking Changes

**Old (v1) - what jido_code currently uses:**
- `Jido.AI.Agent` - Agent module
- `Jido.AI.Keyring` - API key management
- `Jido.AI.Model` - Model definitions
- `Jido.AI.Model.Registry.Adapter` - Model registry
- `Jido.AI.Prompt` - Prompt construction
- `Jido.AI.Actions.ReqLlm.ChatCompletion` - LLM actions

**New (v2) - current state:**
- `Jido.AI.Config` - Configuration helpers
- `Jido.AI.Skills.LLM` - LLM skill (Chat/Complete/Embed)
- `Jido.AI.ReActAgent` - ReAct agent macro
- `Jido.Agent` - Base agent from Jido v2
- `Jido.Exec` - Action execution
- `Jido.Signal` - Signal-based communication

### Impact Scope

**Files requiring migration (7):**
1. `lib/jido_code/agents/llm_agent.ex` - Core agent implementation
2. `lib/jido_code/agents/task_agent.ex` - Task sub-agent
3. `lib/jido_code/config.ex` - Configuration management
4. `lib/jido_code/settings.ex` - Settings loading
5. `lib/jido_code/commands.ex` - Command handlers
6. `lib/jido_code/tui.ex` - TUI integration
7. `lib/jido_code/application.ex` - Application supervisor

**Extensibility integration requirements:**
- Design how permissions integrate with Jido v2's action-based architecture
- Design how channel configuration integrates with Jido v2's signal system
- Ensure extensibility configuration can be loaded by Skill-based agents

---

## Solution Overview

### Three-Phase Approach

1. **Phase A: Root Extensibility Module** (Original Section 2.1)
   - Create `JidoCode.Extensibility` root module
   - Implement `load_extensions/1`, `validate_channel_config/1`, `validate_permissions/1`, `check_permission/3`, `defaults/0`
   - Already completed in previous work (committed to extensibility branch)

2. **Phase B: JidoAI v2 API Migration**
   - Update all jido_code files to use JidoAI v2 APIs
   - Replace old Agent patterns with Jido v2's ReActAgent
   - Update model/keyring configuration to use Jido.AI.Config
   - Migrate from direct LLM calls to Skill-based actions

3. **Phase C: Skill System Integration**
   - Design extensibility-aware Skill wrapper
   - Integrate permissions with Jido v2's action execution
   - Enable extensibility configuration loading from Skill-based agents

---

## Agent Consultations Performed

### Research Investigation (Self-Performed)
- Examined JidoAI v2 directory structure and module organization
- Analyzed `Jido.AI.Skills.LLM` skill implementation
- Reviewed `Jido.AI.ReActAgent` macro and usage patterns
- Studied `Jido.AI.Config` for model resolution and provider configuration
- Identified 7 files in jido_code requiring migration

---

## Technical Details

### Phase A: Root Extensibility Module ✅ (Already Complete)

The root extensibility module was implemented in the previous work and committed to the `extensibility branch`:

**Files Created:**
- `lib/jido_code/extensibility.ex` - Root module with public API
- `lib/jido_code/extensibility/error.ex` - Structured error types
- `lib/jido_code/extensibility/component.ex` - Component behavior for lifecycle

**Functions Implemented:**
- `load_extensions/1` - Load and validate extensibility configuration
- `validate_channel_config/1` - Validate channel configuration
- `validate_permissions/1` - Validate permissions configuration
- `check_permission/3` - Check if permission is granted
- `defaults/0` - Return default extensibility configuration

**Test Results:** 159 extensibility tests passing

### Phase B: JidoAI v2 API Migration

#### B.1 Agent Module Migration

**File:** `lib/jido_code/agents/llm_agent.ex` (400+ lines)

**Current (v1) Structure:**
```elixir
defmodule JidoCode.Agents.LLMAgent do
  use GenServer
  alias Jido.AI.Agent, as: AIAgent
  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Prompt
  alias Jido.AI.Actions.ReqLlm.ChatCompletion

  # Direct calls to AIAgent.chat_response/3
  # Direct calls to Keyring.get/2
  # Direct calls to Model.Registry.Adapter.model_exists?/2
end
```

**Target (v2) Structure:**
```elixir
defmodule JidoCode.Agents.LLMAgent do
  use Jido.AI.ReActAgent,
    name: "jido_code_llm",
    description: "JidoCode coding assistant agent",
    tools: [
      JidoCode.Tools.ReadFile,
      JidoCode.Tools.WriteFile,
      # ... other tools
    ],
    system_prompt: @base_system_prompt,
    model: "anthropic:claude-sonnet-4-20250514",
    skills: [
      {JidoCode.Extensibility.Skills.Permissions, []},
      {Jido.AI.Skills.LLM, [default_model: :capable]}
    ]

  # Use Jido.AI.Config for model resolution
  # Use Jido.Signal for communication
  # Use Jido.Exec for action execution
end
```

**Key Changes:**
1. Replace `use GenServer` with `use Jido.AI.ReActAgent`
2. Replace `AIAgent.chat_response/3` with ReAct loop
3. Replace `Keyring.get/2` with `Jido.AI.Config.get_provider/1`
4. Replace `Model.Registry.Adapter` calls with `Jido.AI.Config.resolve_model/1`
5. Integrate extensibility permissions via custom Skill

#### B.2 Configuration Migration

**File:** `lib/jido_code/config.ex`

**Current (v1):**
```elixir
alias Jido.AI.Keyring
alias Jido.AI.Model.Registry.Adapter, as: RegistryAdapter

# Direct calls to RegistryAdapter.model_exists?/2
# Direct calls to Keyring.get/2
```

**Target (v2):**
```elixir
alias Jido.AI.Config

# Use Config.get_provider/1 for provider config
# Use Config.resolve_model/1 for model resolution
# Use Config.defaults/0 for default settings
```

#### B.3 Settings Migration

**File:** `lib/jido_code/settings.ex`

**Current (v1):**
```elixir
alias Jido.AI.Model.Registry
# References to Registry for model validation
```

**Target (v2):**
```elixir
alias Jido.AI.Config
# Use Config.resolve_model/1 for model validation
```

#### B.4 Additional Files

**Files requiring smaller updates:**
- `lib/jido_code/commands.ex` - Update Keyring/Model registry references
- `lib/jido_code/tui.ex` - Update Keyring references
- `lib/jido_code/application.ex` - Remove Model.Registry.Cache references

### Phase C: Skill System Integration

#### C.1 Extensibility Permissions Skill

**New File:** `lib/jido_code/extensibility/skills/permissions_skill.ex`

**Purpose:** Integrate extensibility permissions with Jido v2's action execution

```elixir
defmodule JidoCode.Extensibility.Skills.Permissions do
  @moduledoc """
  Skill for integrating extensibility permissions with Jido agents.

  This skill wraps action execution with permission checks before
  allowing actions to proceed. It reads the extensibility configuration
  and enforces allow/deny/ask decisions.
  """

  use Jido.Skill,
    name: "extensibility_permissions",
    state_key: :ext_perms,
    actions: [],
    description: "Integrates extensibility permission checks with action execution"

  @impl Jido.Skill
  def mount(_agent, config) do
    # Load extensibility configuration from config
    ext_config = Map.get(config, :extensibility, JidoCode.Extensibility.defaults())

    {:ok, %{
      permissions: ext_config.permissions,
      channels: ext_config.channels
    }}
  end

  @impl Jido.Skill
  def on_before_action(_agent, action, params, skill_state) do
    # Check permission before executing action
    category = action_category(action)
    action_name = action_name(params)

    case JidoCode.Extensibility.check_permission(
      skill_state.permissions,
      category,
      action_name
    ) do
      :allow -> {:ok, :continue}
      :deny -> {:error, :permission_denied}
      :ask -> {:ok, :ask_user}
    end
  end

  defp action_category(action), do: # ...
  defp action_name(params), do: # ...
end
```

#### C.2 Extensibility Configuration Loader

**New File:** `lib/jido_code/extensibility/skills/config_loader.ex`

**Purpose:** Load extensibility configuration from settings for Skill-based agents

```elixir
defmodule JidoCode.Extensibility.Skills.ConfigLoader do
  @moduledoc """
  Helper for loading extensibility configuration into Skills.

  Provides functions to load extensibility config from JidoCode.Settings
  and convert it to Skill-compatible format.
  """

  @doc """
  Load extensibility configuration for agent mounting.

  ## Parameters

  - agent_name - Name of the agent (optional, for agent-specific overrides)

  ## Returns

  - Map with :permissions and :channels keys

  ## Examples

      ext_config = ConfigLoader.load_for_agent("llm_agent")
      # => %{permissions: %Permissions{...}, channels: %{...}}
  """
  def load_for_agent(agent_name \\ nil) do
    settings = JidoCode.Settings.get()

    case JidoCode.Extensibility.load_extensions(settings) do
      {:ok, ext} ->
        %{permissions: ext.permissions, channels: ext.channels}

      {:error, _reason} ->
        # Fall back to defaults if loading fails
        JidoCode.Extensibility.defaults()
    end
  end
end
```

#### C.3 Channel Configuration Integration

**New File:** `lib/jido_code/extensibility/skills/channel_broadcaster.ex`

**Purpose:** Integrate channel configuration with Jido v2's signal system

```elixir
defmodule JidoCode.Extensibility.Skills.ChannelBroadcaster do
  @moduledoc """
  Skill for broadcasting events to configured Phoenix channels.

  Integrates extensibility channel configuration with Jido v2's
  signal system for real-time event broadcasting.
  """

  use Jido.Skill,
    name: "channel_broadcaster",
    state_key: :channels,
    description: "Broadcasts agent events to configured Phoenix channels"

  @impl Jido.Skill
  def mount(_agent, config) do
    # Load channel configuration from config or settings
    channels = Map.get(config, :channels, load_default_channels())

    {:ok, %{channels: channels, sockets: %{}}}
  end

  @impl Jido.Skill
  def on_signal(_agent, signal, skill_state) do
    # Broadcast signals to configured channels
    Enum.each(skill_state.channels, fn {name, channel_config} ->
      if should_broadcast?(signal, channel_config) do
        broadcast_to_channel(name, signal, channel_config)
      end
    end)

    {:ok, :continue}
  end

  defp load_default_channels do
    JidoCode.Extensibility.defaults().channels
  end

  defp should_broadcast?(signal, channel_config) do
    # Check if signal type is in broadcast_events list
    signal_type = signal_type(signal)
    Enum.member?(channel_config.broadcast_events || [], signal_type)
  end

  defp broadcast_to_channel(name, signal, config) do
    # Phoenix channel broadcasting implementation
  end
end
```

---

## Success Criteria

### Phase A: Root Extensibility Module ✅ (Complete)
- [x] JidoCode.Extensibility root module exists
- [x] Public API functions implemented
- [x] Error handling follows structured error pattern
- [x] All tests passing (159 tests)

### Phase B: JidoAI v2 API Migration
- [ ] All jido_code files updated to use JidoAI v2 APIs
- [ ] LLMAgent uses Jido.AI.ReActAgent macro
- [ ] Configuration uses Jido.AI.Config
- [ ] Settings uses Jido.AI.Config
- [ ] Commands/Commands/TUI updated for v2 APIs
- [ ] Application supervisor references updated
- [ ] All existing tests updated and passing

### Phase C: Skill System Integration
- [ ] Extensibility Permissions Skill created
- [ ] ConfigLoader helper implemented
- [ ] ChannelBroadcaster skill implemented
- [ ] Skills integrate with Jido v2 agent lifecycle
- [ ] Permission checks work with action execution
- [ ] Channel broadcasting works with signals
- [ ] Integration tests cover Skill-based scenarios

---

## Implementation Plan

### Step 1: Create Planning Document
- [x] Document problem statement and scope
- [x] Research JidoAI v2 API changes
- [x] Design migration approach
- [x] Define success criteria

### Step 2: Study JidoAI v2 Examples
- [ ] Review Jido.AI.ReActAgent examples
- [ ] Study Jido.AI.Skills.LLM implementation
- [ ] Understand Jido.Skill lifecycle callbacks
- [ ] Review Jido.Exec and action execution flow

### Step 3: Implement ConfigLoader Helper
- [ ] Create `lib/jido_code/extensibility/skills/config_loader.ex`
- [ ] Implement `load_for_agent/1`
- [ ] Add tests for ConfigLoader
- [ ] Document integration points

### Step 4: Migrate Configuration Modules
- [ ] Update `lib/jido_code/config.ex` for Jido.AI.Config
- [ ] Update `lib/jido_code/settings.ex` for Jido.AI.Config
- [ ] Update model resolution calls
- [ ] Update provider configuration calls
- [ ] Add tests for configuration migration

### Step 5: Implement Permissions Skill
- [ ] Create `lib/jido_code/extensibility/skills/permissions_skill.ex`
- [ ] Implement `mount/2` callback
- [ ] Implement `on_before_action/4` callback
- [ ] Add permission checking logic
- [ ] Add tests for Permissions Skill
- [ ] Document permission flow

### Step 6: Implement ChannelBroadcaster Skill
- [ ] Create `lib/jido_code/extensibility/skills/channel_broadcaster.ex`
- [ ] Implement `mount/2` callback
- [ ] Implement `on_signal/3` callback
- [ ] Add Phoenix client integration
- [ ] Add tests for ChannelBroadcaster
- [ ] Document broadcast flow

### Step 7: Migrate LLMAgent to ReActAgent
- [ ] Rewrite `lib/jido_code/agents/llm_agent.ex` using Jido.AI.ReActAgent
- [ ] Integrate Permissions Skill
- [ ] Integrate ChannelBroadcaster Skill
- [ ] Update TUI integration for new agent interface
- [ ] Add tests for migrated LLMAgent
- [ ] Update documentation

### Step 8: Migrate TaskAgent
- [ ] Update `lib/jido_code/agents/task_agent.ex` for Jido v2
- [ ] Update tool execution to use Jido.Exec
- [ ] Add extensibility integration
- [ ] Add tests for migrated TaskAgent
- [ ] Update documentation

### Step 9: Update Commands and TUI
- [ ] Update `lib/jido_code/commands.ex` for Jido.AI.Config
- [ ] Update `lib/jido_code/tui.ex` for new agent interface
- [ ] Update Application supervisor
- [ ] Add tests for updated modules

### Step 10: Integration Testing
- [ ] Test full agent lifecycle with extensibility
- [ ] Test permission enforcement in action execution
- [ ] Test channel broadcasting with signals
- [ ] Test configuration loading from settings
- [ ] Test migration compatibility

### Step 11: Documentation
- [ ] Update module documentation
- [ ] Add migration guide for v1 → v2
- [ ] Add extensibility + skills integration guide
- [ ] Update examples and usage patterns

### Step 12: Final Review
- [ ] Run all tests and ensure passing
- [ ] Code review and quality check
- [ ] Performance testing
- [ ] Security review of permission integration

---

## Open Questions

### ✅ Answered

1. **Phoenix Client Integration**: Use **Phoenix.Client** as a dependency for WebSocket connections

2. **Permission Categories**: Use **module names** - action module names become permission categories (e.g., `JidoCode.Tools.ReadFile` → category `"JidoCode.Tools.ReadFile"` or simplified `"ReadFile"`)

3. **Settings Loading**: **Dynamic reload** - Watch settings file and reload when configuration changes

### ✅ Answered (Updated)

4. **Backward Compatibility**: **Hard break** - No compatibility layer; all users must update to new patterns

5. **Permission Denied Errors**: **Ask user workflow** - Permission denied triggers ask workflow in TUI with option to allow for the session (temporary override)

---

## Risk Assessment

### High Risk Items
1. **Breaking Agent API**: ReActAgent macro has different semantics than GenServer-based agents
2. **Signal System Integration**: Jido v2's signal system is new and may have edge cases
3. **TUI Integration**: TUI expects specific agent interfaces that may change

### Medium Risk Items
1. **Configuration Migration**: Model resolution and provider config have changed significantly
2. **Permission Performance**: Permission checks on every action could add latency
3. **Test Coverage**: Many existing tests will need updates

### Mitigation Strategies
1. Incremental migration with feature flags
2. Comprehensive integration testing
3. Performance benchmarking of permission checks
4. Maintain v1 compatibility during transition if needed

---

## Notes

### Jido v2 Architecture Notes

- **Signals**: Jido v2 uses signals for agent communication
- **Actions**: All functionality is exposed as composable actions
- **Skills**: Skills provide grouped actions with lifecycle hooks
- **Strategies**: ReAct is a strategy; others could be added

### Extensibility Design Implications

The extensibility system should:
1. Load configuration from settings before agent starts
2. Inject permissions checking into action execution flow
3. Broadcast events to configured channels via signals
4. Support runtime reconfiguration (future enhancement)

### Next Steps

1. **Research**: Study JidoAI v2 examples and patterns
2. **Prototype**: Create a simple ReActAgent with Permissions skill
3. **Iterate**: Build out integration based on prototype learnings
4. **Test**: Comprehensive testing at each step

---

## Status

**Current Step**: Planning Phase - Research JidoAI v2 APIs
**Next Step**: Study JidoAI v2 examples and create prototype
**Completed**: Phase A (Root Extensibility Module)
**In Progress**: Phase B (JidoAI v2 API Migration) - Planning
**Pending**: Phase C (Skill System Integration)
