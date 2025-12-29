# Phase 4: Web & Agent Tools

This phase implements web access capabilities and agent/task delegation tools. All tools route through the Lua sandbox for defense-in-depth security per [ADR-0001](../../decisions/0001-tool-security-architecture.md).

## Lua Sandbox Architecture

All web and agent tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                       │
│  e.g., {"name": "web_fetch", "arguments": {"url": "..."}}   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Tools.Manager.web_fetch(url, opts, session_id: id)         │
│  GenServer call to session-scoped Lua sandbox               │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Lua VM executes: "return jido.web_fetch(url, opts)"        │
│  (dangerous functions like os.execute already removed)      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Bridge.lua_web_fetch/3 invoked from Lua                    │
│  (Elixir function registered as jido.web_fetch)             │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│  Security.Web.validate_url/1                                │
│  - Domain allowlist enforcement                             │
│  - Scheme validation (no file://, javascript://)            │
└─────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Implementation | Purpose | Status |
|------|----------------|---------|--------|
| web_fetch | Handler pattern | Fetch and parse web content | ✅ Implemented |
| web_search | Handler pattern | Search the web | ✅ Implemented |
| spawn_task | Handler pattern | Delegate tasks to sub-agents (sync) | ✅ Implemented |
| get_task_output | - | Retrieve background task results | ❌ Not needed (sync) |
| todo_write | Handler pattern | Manage task tracking list | ✅ Implemented |
| todo_read | - | Read current task list | ❌ Deferred |
| ask_user | - | Interactive user questions | ❌ Deferred |

> **Note:** The implementation uses the Handler pattern (direct Elixir execution) instead of the Lua bridge pattern. `spawn_task` is synchronous so `get_task_output` is not needed. Tool names differ from planning: `spawn_subagent` → `spawn_task`.

---

## 4.1 Web Fetch Tool ✅

Implement the web_fetch tool for fetching and parsing web content. Uses the Handler pattern with direct Elixir execution.

### 4.1.1 Tool Definition ✅

Note: Implemented as `web_fetch` in `lib/jido_code/tools/definitions/web.ex`

- [x] 4.1.1.1 Create tool definition in `lib/jido_code/tools/definitions/web.ex`
- [x] 4.1.1.2 Define schema with url, prompt parameters
- [x] 4.1.1.3 Document domain allowlist in description
- [x] 4.1.1.4 Register tool via `Web.all/0`

### 4.1.2 Handler Implementation ✅

Note: Uses Handler pattern instead of Lua bridge for simpler implementation.

- [x] 4.1.2.1 Create `Fetch` handler in `lib/jido_code/tools/handlers/web.ex`
- [x] 4.1.2.2 Use `Security.Web.validate_url/1` to check against domain allowlist
- [x] 4.1.2.3 Block dangerous URL schemes (file://, javascript://, data://)
- [x] 4.1.2.4 Fetch URL with HTTP client (Req)
- [x] 4.1.2.5 Handle redirects (follow up to 5 redirects, validate each domain)
- [x] 4.1.2.6 Parse HTML with Floki
- [x] 4.1.2.7 Convert HTML to markdown
- [x] 4.1.2.8 Truncate large content with indicator
- [x] 4.1.2.9 Return content with final URL

### 4.1.3 Unit Tests for Web Fetch ✅

- [x] Test web_fetch with allowed domain
- [x] Test web_fetch blocks disallowed domain
- [x] Test web_fetch blocks file:// URLs
- [x] Test web_fetch converts HTML to markdown
- [x] Test web_fetch handles 404 errors
- [x] Test web_fetch handles timeouts

---

## 4.2 Web Search Tool ✅

Implement the web_search tool for searching the web. Uses the Handler pattern with DuckDuckGo.

### 4.2.1 Tool Definition ✅

Note: Implemented as `web_search` in `lib/jido_code/tools/definitions/web.ex`

- [x] 4.2.1.1 Create tool definition in `lib/jido_code/tools/definitions/web.ex`
- [x] 4.2.1.2 Define schema with query, num_results parameters
- [x] 4.2.1.3 Register tool via `Web.all/0`

### 4.2.2 Handler Implementation ✅

Note: Uses Handler pattern instead of Lua bridge.

- [x] 4.2.2.1 Create `Search` handler in `lib/jido_code/tools/handlers/web.ex`
- [x] 4.2.2.2 Execute search via DuckDuckGo
- [x] 4.2.2.3 Parse search results
- [x] 4.2.2.4 Apply result limit
- [x] 4.2.2.5 Format results with title, URL, snippet

### 4.2.3 Unit Tests for Web Search ✅

- [x] Test web_search returns results
- [x] Test web_search respects limit
- [x] Test web_search handles no results
- [x] Test web_search handles search errors

---

## 4.3 Spawn Task Tool ✅

Implement the spawn_task tool for delegating complex tasks. Uses the Handler pattern with synchronous execution.

> **Note:** Implemented as `spawn_task` (not `spawn_subagent`). The tool executes synchronously - background execution was not implemented, so `get_task_output` is not needed.

### 4.3.1 Tool Definition ✅

Note: Implemented as `spawn_task` in `lib/jido_code/tools/definitions/task.ex`

- [x] 4.3.1.1 Create tool definition in `lib/jido_code/tools/definitions/task.ex`
- [x] 4.3.1.2 Define schema with description, prompt, subagent_type, model, timeout
- [x] 4.3.1.3 Register tool via `Task.all/0`

### 4.3.2 Handler Implementation ✅

Note: Uses Handler pattern, synchronous execution only.

- [x] 4.3.2.1 Create `Task` handler in `lib/jido_code/tools/handlers/task.ex`
- [x] 4.3.2.2 Validate subagent_type hint
- [x] 4.3.2.3 Create TaskAgent with prompt and session context
- [x] 4.3.2.4 Wait for completion (synchronous)
- [x] 4.3.2.5 Capture agent output
- [x] 4.3.2.6 Return result or error

### 4.3.3 Unit Tests for Spawn Task ✅

- [x] Test spawn_task creates agent
- [x] Test spawn_task with different types
- [x] Test spawn_task returns result
- [x] Test spawn_task handles agent failure

---

## 4.4 Get Task Output Tool ❌ Not Needed

> **Note:** This tool is not needed because `spawn_task` executes synchronously. Background task execution was not implemented, so there is no need for task output retrieval.

This section is preserved for reference in case background execution is added in the future.

---

## 4.5 Todo Write Tool ✅

Implement the todo_write tool for managing task tracking lists. Uses the Handler pattern.

### 4.5.1 Tool Definition ✅

Note: Implemented as `todo_write` in `lib/jido_code/tools/definitions/todo.ex`

- [x] 4.5.1.1 Create tool definition in `lib/jido_code/tools/definitions/todo.ex`
- [x] 4.5.1.2 Define schema with todos array (content, status, active_form)
- [x] 4.5.1.3 Register tool via `Todo.all/0`

### 4.5.2 Handler Implementation ✅

Note: Uses Handler pattern instead of Lua bridge.

- [x] 4.5.2.1 Create `Todo` handler in `lib/jido_code/tools/handlers/todo.ex`
- [x] 4.5.2.2 Validate todo structure
- [x] 4.5.2.3 Update session state with new todo list
- [x] 4.5.2.4 Publish todo update via PubSub
- [x] 4.5.2.5 Return todos or error

### 4.5.3 Unit Tests for Todo Write ✅

- [x] Test todo_write creates new list
- [x] Test todo_write updates existing list
- [x] Test todo_write validates status enum
- [x] Test todo_write publishes update

---

## 4.6 Todo Read Tool ❌ Deferred

> **Note:** This tool is deferred to a future phase. The current implementation only supports writing todos; reading is handled internally by the TUI.

This section is preserved for future implementation.

---

## 4.7 Ask User Tool ❌ Deferred

> **Note:** This tool is deferred to a future phase. User interaction is currently handled through the TUI directly without a formal tool interface.

This section is preserved for future implementation.

---

## 4.8 Phase 4 Integration Tests (Partial)

Integration tests for web and agent tools.

### 4.8.1 Handler Integration ✅

Verify tools execute through the handler pattern correctly.

- [x] Test: All tools execute through `Executor` → Handler chain
- [x] Test: Session context passed correctly

### 4.8.2 Web Integration ✅

Test web tools in realistic scenarios.

- [x] Test: web_fetch retrieves documentation pages
- [x] Test: web_search finds relevant results

### 4.8.3 Task Integration ✅

Test task tools.

- [x] Test: spawn_task executes and returns result
- [x] Test: spawn_task handles agent failure

### 4.8.4 Todo Integration ✅

Test todo tracking.

- [x] Test: todo_write creates and updates list
- [x] Test: todo updates published to TUI

---

## Phase 4 Success Criteria

| Criterion | Status |
|-----------|--------|
| **web_fetch**: HTML-to-markdown via Handler pattern | ✅ Implemented |
| **web_search**: Query search via Handler pattern | ✅ Implemented |
| **spawn_task**: Agent delegation via Handler pattern (sync) | ✅ Implemented |
| **get_task_output**: Task retrieval | ❌ Not needed (sync execution) |
| **todo_write**: Task tracking via Handler pattern | ✅ Implemented |
| **todo_read**: Read task list | ❌ Deferred |
| **ask_user**: User interaction | ❌ Deferred |
| **Test Coverage**: Minimum 80% for Phase 4 tools | ✅ Achieved |

---

## Phase 4 Critical Files

**Implemented Files:**
- `lib/jido_code/tools/definitions/web.ex` - web_fetch, web_search definitions
- `lib/jido_code/tools/definitions/task.ex` - spawn_task definition
- `lib/jido_code/tools/definitions/todo.ex` - todo_write definition
- `lib/jido_code/tools/handlers/web.ex` - Fetch, Search handlers
- `lib/jido_code/tools/handlers/task.ex` - Task handler
- `lib/jido_code/tools/handlers/todo.ex` - Todo handler
- `lib/jido_code/tools/security/web.ex` - URL validation for web tools
- `test/jido_code/tools/handlers/web_test.exs` - Web handler tests
- `test/jido_code/tools/handlers/task_test.exs` - Task handler tests
- `test/jido_code/tools/handlers/todo_test.exs` - Todo handler tests

**Deferred Files:**
- `lib/jido_code/tools/definitions/todo_read.ex` - Not implemented
- `lib/jido_code/tools/definitions/ask_user.ex` - Not implemented
