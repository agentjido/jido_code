# Phase 3: Tool Integration

This phase updates the tool execution pipeline to be session-aware. All tool handlers will receive session context and use the session's Manager for path validation and file operations. The LLMAgent is also integrated into the per-session supervisor.

---

## 3.1 Tool Executor Updates

Update the Tools.Executor to require and propagate session context.

### 3.1.1 Context Requirements
- [x] **Task 3.1.1**

Define and enforce session context requirements in Executor.

- [x] 3.1.1.1 Update `@type context()` to include session_id:
  ```elixir
  @type context :: %{
    session_id: String.t(),
    project_root: String.t(),
    timeout: pos_integer()
  }
  ```
- [x] 3.1.1.2 Update `execute/2` to validate session_id presence (with backwards-compatible deprecation warning)
- [x] 3.1.1.3 Return `{:error, :missing_session_id}` if not provided (via `enrich_context/1`)
- [x] 3.1.1.4 Fetch project_root from Session.Manager if not in context
- [x] 3.1.1.5 Document context requirements in module doc
- [x] 3.1.1.6 Write unit tests for context validation

### 3.1.2 Context Building Helper
- [x] **Task 3.1.2**

Create helper for building execution context from session.

- [x] 3.1.2.1 Implement `build_context/1` accepting session_id:
  ```elixir
  def build_context(session_id, opts \\ []) do
    with {:ok, project_root} <- Session.Manager.project_root(session_id) do
      {:ok, %{
        session_id: session_id,
        project_root: project_root,
        timeout: opts[:timeout] || 30_000
      }}
    end
  end
  ```
- [x] 3.1.2.2 Handle missing session gracefully
- [x] 3.1.2.3 Allow timeout override via opts
- [x] 3.1.2.4 Write unit tests for context building

### 3.1.3 PubSub Integration
- [x] **Task 3.1.3**

Update tool result broadcasting to use session topic.

- [x] 3.1.3.1 Update `broadcast_result/3` to use session-specific topic (already implemented)
- [x] 3.1.3.2 Build topic from session_id: `"tui.events.#{session_id}"` (already implemented)
- [x] 3.1.3.3 Include session_id in broadcast payload
- [x] 3.1.3.4 Update `broadcast_tool_call/4` similarly
- [x] 3.1.3.5 Write unit tests for broadcast routing

**Unit Tests for Section 3.1:**
- Test `execute/2` requires session_id in context
- Test `execute/2` returns error for missing session_id
- Test `build_context/1` fetches project_root from Manager
- Test `build_context/1` handles invalid session_id
- Test broadcasts go to session-specific topic

---

## 3.2 Handler Updates

Update all tool handlers to consistently use session context.

### 3.2.1 FileSystem Handlers
- [ ] **Task 3.2.1**

Update filesystem handlers to use session context.

- [ ] 3.2.1.1 Update `ReadFile.execute/2` to use `context.session_id`:
  ```elixir
  def execute(args, context) do
    with {:ok, safe_path} <- Session.Manager.validate_path(
           context.session_id, args["path"]
         ),
         {:ok, content} <- File.read(safe_path) do
      {:ok, content}
    end
  end
  ```
- [ ] 3.2.1.2 Update `WriteFile.execute/2` similarly
- [ ] 3.2.1.3 Update `EditFile.execute/2` similarly
- [ ] 3.2.1.4 Update `ListDirectory.execute/2` similarly
- [ ] 3.2.1.5 Update `FileInfo.execute/2` similarly
- [ ] 3.2.1.6 Update `CreateDirectory.execute/2` similarly
- [ ] 3.2.1.7 Update `DeleteFile.execute/2` similarly
- [ ] 3.2.1.8 Write unit tests for each handler with session context

### 3.2.2 Search Handlers
- [ ] **Task 3.2.2**

Update search handlers to use session context.

- [ ] 3.2.2.1 Update `Grep.execute/2` to use session's project_root
- [ ] 3.2.2.2 Update `FindFiles.execute/2` similarly
- [ ] 3.2.2.3 Ensure search paths validated against session boundary
- [ ] 3.2.2.4 Write unit tests for search handlers

### 3.2.3 Shell Handler
- [ ] **Task 3.2.3**

Update shell handler to use session context.

- [ ] 3.2.3.1 Update `RunCommand.execute/2` to use session's project_root as cwd
- [ ] 3.2.3.2 Validate command arguments don't escape project boundary
- [ ] 3.2.3.3 Set working directory to session's project_root
- [ ] 3.2.3.4 Write unit tests for shell handler

### 3.2.4 Web Handlers
- [ ] **Task 3.2.4**

Update web handlers to include session context in results.

- [ ] 3.2.4.1 Update `Fetch.execute/2` to include session_id in result metadata
- [ ] 3.2.4.2 Update `Search.execute/2` similarly
- [ ] 3.2.4.3 Web handlers don't need path validation but should track session
- [ ] 3.2.4.4 Write unit tests for web handlers

### 3.2.5 Livebook Handler
- [ ] **Task 3.2.5**

Update Livebook handler to use session context.

- [ ] 3.2.5.1 Update `EditCell.execute/2` to validate notebook path
- [ ] 3.2.5.2 Use Session.Manager.validate_path for notebook files
- [ ] 3.2.5.3 Write unit tests for Livebook handler

### 3.2.6 Todo Handler
- [ ] **Task 3.2.6**

Update Todo handler to store todos in session state.

- [ ] 3.2.6.1 Update `Todo.execute/2` to use Session.State:
  ```elixir
  def execute(args, context) do
    Session.State.update_todos(context.session_id, args["todos"])
    {:ok, %{updated: true}}
  end
  ```
- [ ] 3.2.6.2 Todos stored in session-specific state, not global
- [ ] 3.2.6.3 Write unit tests for Todo handler

### 3.2.7 Task Handler
- [ ] **Task 3.2.7**

Update Task handler to spawn tasks within session context.

- [ ] 3.2.7.1 Update `Task.execute/2` to include session context in spawned task
- [ ] 3.2.7.2 Pass session_id to sub-agent for proper isolation
- [ ] 3.2.7.3 Sub-tasks should operate within same session boundary
- [ ] 3.2.7.4 Write unit tests for Task handler

**Unit Tests for Section 3.2:**
- Test ReadFile uses Session.Manager.validate_path
- Test WriteFile validates path via session
- Test Grep searches within session boundary
- Test FindFiles searches within session boundary
- Test RunCommand uses session's project_root as cwd
- Test Web handlers include session_id in metadata
- Test Todo handler updates Session.State
- Test Task handler passes session context to sub-agents

---

## 3.3 LLMAgent Integration

Integrate LLMAgent into per-session supervision and tool execution.

### 3.3.1 Agent Session Awareness
- [ ] **Task 3.3.1**

Update LLMAgent to be fully session-aware.

- [ ] 3.3.1.1 Add `session_id` to LLMAgent state (already partially exists)
- [ ] 3.3.1.2 Implement `via/1` for Registry naming by session:
  ```elixir
  defp via(session_id) do
    {:via, Registry, {JidoCode.Registry, {:session_agent, session_id}}}
  end
  ```
- [ ] 3.3.1.3 Update `start_link/1` to accept session_id in opts
- [ ] 3.3.1.4 Build tool execution context from session_id
- [ ] 3.3.1.5 Write unit tests for session-aware agent

### 3.3.2 Agent Integration with Session Supervisor
- [ ] **Task 3.3.2**

Add LLMAgent to per-session supervision tree.

- [ ] 3.3.2.1 Update `Session.Supervisor.init/1` to include LLMAgent:
  ```elixir
  children = [
    {JidoCode.Session.Manager, session: session},
    {JidoCode.Session.State, session: session},
    {JidoCode.Agents.LLMAgent, session_id: session.id, config: session.config}
  ]
  ```
- [ ] 3.3.2.2 Agent should start after Manager (depends on path validation)
- [ ] 3.3.2.3 Pass session config to agent for LLM configuration
- [ ] 3.3.2.4 Write integration tests for supervised agent

### 3.3.3 Agent Tool Execution
- [ ] **Task 3.3.3**

Update agent's tool execution to use session context.

- [ ] 3.3.3.1 Update tool call handling to build context from session:
  ```elixir
  defp execute_tool(tool_call, state) do
    {:ok, context} = Tools.Executor.build_context(state.session_id)
    Tools.Executor.execute(tool_call, context: context)
  end
  ```
- [ ] 3.3.3.2 Ensure all tool calls go through session-scoped executor
- [ ] 3.3.3.3 Handle tool execution errors properly
- [ ] 3.3.3.4 Write unit tests for agent tool execution

### 3.3.4 Agent Streaming with Session
- [ ] **Task 3.3.4**

Update streaming to route through Session.State.

- [ ] 3.3.4.1 Update stream chunk handling to update Session.State:
  ```elixir
  defp handle_stream_chunk(chunk, state) do
    Session.State.update_streaming(state.session_id, chunk)
    # Also broadcast via PubSub for TUI
    broadcast_chunk(state.session_id, chunk)
    state
  end
  ```
- [ ] 3.3.4.2 Update stream end to finalize in Session.State
- [ ] 3.3.4.3 Write unit tests for streaming integration

### 3.3.5 Session Supervisor Access Helper
- [ ] **Task 3.3.5**

Add helper to Session.Supervisor for accessing agent.

- [ ] 3.3.5.1 Implement `get_agent/1` in Session.Supervisor:
  ```elixir
  def get_agent(session_id) do
    Registry.lookup(JidoCode.Registry, {:session_agent, session_id})
    |> case do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end
  ```
- [ ] 3.3.5.2 Write unit tests for agent lookup

**Unit Tests for Section 3.3:**
- Test LLMAgent registers with session-specific name
- Test LLMAgent starts in Session.Supervisor
- Test Agent tool execution uses session context
- Test Agent streaming updates Session.State
- Test `get_agent/1` returns agent pid

---

## 3.4 Agent Interaction API

Create a clean API for TUI to interact with session agents.

### 3.4.1 Send Message API
- [ ] **Task 3.4.1**

Create high-level API for sending messages to session agent.

- [ ] 3.4.1.1 Create `lib/jido_code/session/agent_api.ex` module
- [ ] 3.4.1.2 Implement `send_message/2`:
  ```elixir
  def send_message(session_id, message) do
    with {:ok, agent_pid} <- Session.Supervisor.get_agent(session_id) do
      LLMAgent.chat(agent_pid, message)
    end
  end
  ```
- [ ] 3.4.1.3 Implement `send_message_stream/2` for streaming responses
- [ ] 3.4.1.4 Handle agent not found errors
- [ ] 3.4.1.5 Write unit tests for message API

### 3.4.2 Agent Status API
- [ ] **Task 3.4.2**

Create API for checking agent status.

- [ ] 3.4.2.1 Implement `get_status/1` returning agent status:
  ```elixir
  def get_status(session_id) do
    with {:ok, agent_pid} <- Session.Supervisor.get_agent(session_id) do
      LLMAgent.get_status(agent_pid)
    end
  end
  ```
- [ ] 3.4.2.2 Implement `is_processing?/1` for quick status check
- [ ] 3.4.2.3 Write unit tests for status API

### 3.4.3 Agent Configuration API
- [ ] **Task 3.4.3**

Create API for updating agent configuration.

- [ ] 3.4.3.1 Implement `update_config/2`:
  ```elixir
  def update_config(session_id, config) do
    with {:ok, agent_pid} <- Session.Supervisor.get_agent(session_id) do
      LLMAgent.update_config(agent_pid, config)
    end
  end
  ```
- [ ] 3.4.3.2 Also update session's stored config
- [ ] 3.4.3.3 Write unit tests for config API

**Unit Tests for Section 3.4:**
- Test `send_message/2` sends to correct agent
- Test `send_message/2` handles missing agent
- Test `get_status/1` returns agent status
- Test `is_processing?/1` returns boolean
- Test `update_config/2` updates agent config

---

## 3.5 Phase 3 Integration Tests

Comprehensive integration tests verifying all Phase 3 components work together correctly.

### 3.5.1 Tool Execution Pipeline
- [ ] **Task 3.5.1**

Test complete tool execution flow with session context.

- [ ] 3.5.1.1 Create `test/jido_code/integration/session_phase3_test.exs`
- [ ] 3.5.1.2 Test: Build context from session → execute tool → verify session boundary enforced
- [ ] 3.5.1.3 Test: Tool call → PubSub broadcast → correct session topic
- [ ] 3.5.1.4 Test: ReadFile with session context → path validated via Session.Manager
- [ ] 3.5.1.5 Test: WriteFile with session context → file written within boundary
- [ ] 3.5.1.6 Test: Tool execution without session_id → returns error
- [ ] 3.5.1.7 Write all pipeline integration tests

### 3.5.2 Handler Session Awareness
- [ ] **Task 3.5.2**

Test all handlers correctly use session context.

- [ ] 3.5.2.1 Test: FileSystem handlers validate paths via session's Manager
- [ ] 3.5.2.2 Test: Search handlers (Grep, FindFiles) respect session boundary
- [ ] 3.5.2.3 Test: Shell handler uses session's project_root as cwd
- [ ] 3.5.2.4 Test: Todo handler updates Session.State for correct session
- [ ] 3.5.2.5 Test: Task handler passes session context to spawned sub-agents
- [ ] 3.5.2.6 Write all handler integration tests

### 3.5.3 Agent-Session Integration
- [ ] **Task 3.5.3**

Test LLMAgent integration with session supervision.

- [ ] 3.5.3.1 Test: Create session → Agent starts under Session.Supervisor
- [ ] 3.5.3.2 Test: Agent tool call → uses session's execution context
- [ ] 3.5.3.3 Test: Agent streaming → updates Session.State → broadcasts to session topic
- [ ] 3.5.3.4 Test: Agent restart → reconnects to same session context
- [ ] 3.5.3.5 Test: Session close → Agent terminates cleanly
- [ ] 3.5.3.6 Write all agent integration tests

### 3.5.4 Multi-Session Tool Isolation
- [ ] **Task 3.5.4**

Test tool execution isolation across sessions.

- [ ] 3.5.4.1 Test: Execute tool in session A → session B's boundary not accessible
- [ ] 3.5.4.2 Test: Concurrent tool execution in 2 sessions → no interference
- [ ] 3.5.4.3 Test: Todo update in session A → session B todos unchanged
- [ ] 3.5.4.4 Test: Streaming in session A → session B receives no chunks
- [ ] 3.5.4.5 Write all isolation integration tests

### 3.5.5 AgentAPI Integration
- [ ] **Task 3.5.5**

Test AgentAPI provides correct interface for TUI.

- [ ] 3.5.5.1 Test: send_message/2 → agent receives → executes tools → streams response
- [ ] 3.5.5.2 Test: get_status/1 → returns correct processing state
- [ ] 3.5.5.3 Test: update_config/2 → agent config updated → session config updated
- [ ] 3.5.5.4 Test: AgentAPI with invalid session → returns clear error
- [ ] 3.5.5.5 Write all AgentAPI integration tests

**Integration Tests for Section 3.5:**
- Tool execution pipeline works end-to-end
- All handlers use session context correctly
- Agent integrates with session supervision
- Multiple sessions have isolated tool execution
- AgentAPI provides clean interface

---

## Success Criteria

1. **Context Requirements**: All tool execution requires session_id in context
2. **Path Validation**: All file operations validate paths via Session.Manager
3. **Search Isolation**: Grep and FindFiles operate within session boundary
4. **Shell Isolation**: RunCommand uses session's project_root as cwd
5. **State Integration**: Todo handler updates Session.State
6. **Agent Supervision**: LLMAgent runs under Session.Supervisor
7. **Streaming Integration**: Streaming updates flow through Session.State
8. **Clean API**: AgentAPI provides clean interface for TUI
9. **PubSub Routing**: Tool results broadcast to session-specific topics
10. **Test Coverage**: Minimum 80% coverage for phase 3 code
11. **Integration Tests**: All Phase 3 components work together correctly (Section 3.5)

---

## Critical Files

**New Files:**
- `lib/jido_code/session/agent_api.ex`
- `test/jido_code/session/agent_api_test.exs`
- `test/jido_code/integration/session_phase3_test.exs`

**Modified Files:**
- `lib/jido_code/tools/executor.ex` - Session context requirements
- `lib/jido_code/tools/handlers/filesystem/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/search/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/shell/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/web/*.ex` - Session metadata
- `lib/jido_code/tools/handlers/livebook/*.ex` - Session-aware handlers
- `lib/jido_code/tools/handlers/todo.ex` - Session.State integration
- `lib/jido_code/tools/handlers/task.ex` - Session context passing
- `lib/jido_code/agents/llm_agent.ex` - Session integration
- `lib/jido_code/session/supervisor.ex` - Add LLMAgent child

---

## Dependencies

- **Depends on Phase 1**: Session struct, Registry, Supervisors
- **Depends on Phase 2**: Session.Manager, Session.State
- **Phase 4 depends on this**: TUI needs AgentAPI for interaction
