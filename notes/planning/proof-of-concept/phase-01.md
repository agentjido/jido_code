# Phase 1: Project Foundation and Core Infrastructure

This phase establishes the Elixir project structure, dependency management, and core OTP supervision tree. The foundation must support fault-tolerant operation with proper process isolation, enabling the TUI, agents, and infrastructure services to operate independently while communicating through Phoenix PubSub.

## 1.1 Project Initialization

The project initialization creates the standard Elixir application structure with proper configuration for all required dependencies. The project name `jido_code` reflects its purpose as a coding assistant built on the Jido framework.

### 1.1.1 Create Elixir Project Structure
- [ ] **Task 1.1.1 Complete**

Generate the base Elixir application with supervision tree support and configure mix.exs with all required dependencies.

- [ ] 1.1.1.1 Run `mix new jido_code --sup` to create supervised application
- [ ] 1.1.1.2 Configure mix.exs with dependencies: jido (~> 1.1.0), jido_ai (~> 0.5.0), term_ui, phoenix_pubsub (~> 2.1), jason, rdf (~> 2.0), libgraph (~> 0.16)
- [ ] 1.1.1.3 Add development dependencies: ex_doc, credo, dialyxir
- [ ] 1.1.1.4 Create config/config.exs with base configuration structure
- [ ] 1.1.1.5 Create config/runtime.exs for environment-specific LLM configuration
- [ ] 1.1.1.6 Run `mix deps.get` and verify all dependencies compile (success: `mix compile` exits 0)

### 1.1.2 Configure LLM Provider Settings
- [ ] **Task 1.1.2 Complete**

Establish the configuration schema for LLM providers using JidoAI's Keyring and Model systems. JidoAI supports 50+ providers through ReqLLM integration - any provider returned by `Jido.AI.Provider.providers/0` is valid.

- [ ] 1.1.2.1 Define `:jido_code, :llm` configuration key with provider, model, temperature, max_tokens options
- [ ] 1.1.2.2 Create `JidoCode.Config` module to read and validate LLM configuration
- [ ] 1.1.2.3 Implement `Config.get_llm_config/0` returning validated `{provider, opts}` tuple
- [ ] 1.1.2.4 Validate provider exists via `Jido.AI.Provider.providers/0` (supports 50+ providers via ReqLLM)
- [ ] 1.1.2.5 Support environment variable overrides: `JIDO_CODE_PROVIDER`, `JIDO_CODE_MODEL`, provider-specific API key env vars
- [ ] 1.1.2.6 Add runtime validation that API key exists for configured provider via Keyring
- [ ] 1.1.2.7 Require explicit provider configuration (no default) - error on startup if not configured
- [ ] 1.1.2.8 Write config tests verifying provider switching and validation (success: tests pass)

## 1.2 OTP Supervision Tree

The supervision tree implements fault isolation between infrastructure services, agents, and the TUI layer. Using `:one_for_one` strategy at the top level ensures that a crash in one subsystem doesn't cascade.

### 1.2.1 Application Supervisor Structure
- [ ] **Task 1.2.1 Complete**

Implement the main application supervisor with proper child ordering and restart strategies.

- [ ] 1.2.1.1 Create `JidoCode.Application` module with `start/2` callback
- [ ] 1.2.1.2 Add Phoenix.PubSub as first child: `{Phoenix.PubSub, name: JidoCode.PubSub}`
- [ ] 1.2.1.3 Add Registry for agent lookup: `{Registry, keys: :unique, name: JidoCode.AgentRegistry}`
- [ ] 1.2.1.4 Add `JidoCode.AgentSupervisor` as DynamicSupervisor for agent processes
- [ ] 1.2.1.5 Configure top-level supervisor with `strategy: :one_for_one`
- [ ] 1.2.1.6 Verify supervision tree starts correctly via `mix run --no-halt` (success: no errors for 5s)

### 1.2.2 Agent Supervisor Implementation
- [ ] **Task 1.2.2 Complete**

Create the agent supervisor that manages LLM agent lifecycle with proper restart policies.

- [ ] 1.2.2.1 Create `JidoCode.AgentSupervisor` as DynamicSupervisor
- [ ] 1.2.2.2 Implement `start_agent/1` to spawn supervised agent processes
- [ ] 1.2.2.3 Implement `stop_agent/1` for graceful agent termination
- [ ] 1.2.2.4 Configure agent restart strategy: `restart: :transient` (restart on abnormal exit only)
- [ ] 1.2.2.5 Add agent process registration via AgentRegistry
- [ ] 1.2.2.6 Write tests for agent start/stop/restart behavior (success: agent recovers from crash)
