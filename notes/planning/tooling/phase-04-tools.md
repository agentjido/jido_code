# Phase 4: Web & Agent Tools

This phase implements web access capabilities and agent/task delegation tools. Web tools enable documentation fetching and search, while agent tools support sub-agent spawning and task tracking.

## Tools in This Phase

| Tool | Purpose | Priority |
|------|---------|----------|
| web_fetch | Fetch and parse web content | Core |
| web_search | Search the web | Core |
| spawn_subagent | Delegate tasks to sub-agents | Core |
| todo_write | Manage task tracking list | Core |
| todo_read | Read current task list | Core |
| ask_user | Interactive user questions | Core |

---

## 4.1 Web Fetch Tool

Implement the web_fetch tool for fetching and parsing web content with HTML-to-markdown conversion.

### 4.1.1 Tool Definition

Create the web_fetch tool definition with URL validation.

- [ ] 4.1.1.1 Create `lib/jido_code/tools/definitions/web_fetch.ex`
- [ ] 4.1.1.2 Define schema:
  ```elixir
  %{
    url: %{type: :string, required: true, description: "URL to fetch"},
    prompt: %{type: :string, required: false, description: "Prompt to process content with"},
    extract_selector: %{type: :string, required: false, description: "CSS selector to extract"}
  }
  ```
- [ ] 4.1.1.3 Document domain allowlist in description

### 4.1.2 Web Fetch Handler Implementation

Implement the handler for web content fetching.

- [ ] 4.1.2.1 Create `lib/jido_code/tools/handlers/web/fetch.ex`
- [ ] 4.1.2.2 Validate URL against domain allowlist:
  - hexdocs.pm
  - elixir-lang.org
  - erlang.org
  - github.com
  - hex.pm
- [ ] 4.1.2.3 Block dangerous URL schemes (file://, javascript://, data://)
- [ ] 4.1.2.4 Fetch URL with HTTP client (Req or HTTPoison)
- [ ] 4.1.2.5 Handle redirects (follow up to 5 redirects)
- [ ] 4.1.2.6 Parse HTML with Floki
- [ ] 4.1.2.7 Convert HTML to markdown (preserve code blocks, links)
- [ ] 4.1.2.8 Apply CSS selector extraction if specified
- [ ] 4.1.2.9 Implement 15-minute cache for repeated requests
- [ ] 4.1.2.10 Truncate large content (preserve useful portions)
- [ ] 4.1.2.11 Return `{:ok, %{content: markdown, url: final_url}}` or `{:error, reason}`

### 4.1.3 Unit Tests for Web Fetch

- [ ] Test web_fetch with allowed domain
- [ ] Test web_fetch blocks disallowed domain
- [ ] Test web_fetch blocks file:// URLs
- [ ] Test web_fetch follows redirects
- [ ] Test web_fetch converts HTML to markdown
- [ ] Test web_fetch applies CSS selector
- [ ] Test web_fetch caches responses
- [ ] Test web_fetch handles 404 errors
- [ ] Test web_fetch handles timeouts

---

## 4.2 Web Search Tool

Implement the web_search tool for searching the web.

### 4.2.1 Tool Definition

Create the web_search tool definition with query parameters.

- [ ] 4.2.1.1 Create `lib/jido_code/tools/definitions/web_search.ex`
- [ ] 4.2.1.2 Define schema:
  ```elixir
  %{
    query: %{type: :string, required: true, description: "Search query"},
    allowed_domains: %{type: :array, required: false, description: "Limit to specific domains"},
    blocked_domains: %{type: :array, required: false, description: "Exclude specific domains"},
    limit: %{type: :integer, required: false, description: "Max results (default: 10)"}
  }
  ```

### 4.2.2 Web Search Handler Implementation

Implement the handler for web search.

- [ ] 4.2.2.1 Create `lib/jido_code/tools/handlers/web/search.ex`
- [ ] 4.2.2.2 Build search query with domain filters
- [ ] 4.2.2.3 Execute search via DuckDuckGo or other provider
- [ ] 4.2.2.4 Parse search results
- [ ] 4.2.2.5 Filter by allowed/blocked domains
- [ ] 4.2.2.6 Apply result limit
- [ ] 4.2.2.7 Format results with title, URL, snippet
- [ ] 4.2.2.8 Return `{:ok, [%{title: t, url: u, snippet: s}, ...]}` or `{:error, reason}`

### 4.2.3 Unit Tests for Web Search

- [ ] Test web_search returns results
- [ ] Test web_search filters by allowed_domains
- [ ] Test web_search filters by blocked_domains
- [ ] Test web_search respects limit
- [ ] Test web_search handles no results
- [ ] Test web_search handles search errors

---

## 4.3 Spawn Subagent Tool

Implement the spawn_subagent tool for delegating complex tasks to specialized sub-agents.

### 4.3.1 Tool Definition

Create the spawn_subagent tool definition for task delegation.

- [ ] 4.3.1.1 Create `lib/jido_code/tools/definitions/spawn_subagent.ex`
- [ ] 4.3.1.2 Define schema:
  ```elixir
  %{
    description: %{type: :string, required: true, description: "3-5 word task description"},
    prompt: %{type: :string, required: true, description: "Detailed task prompt"},
    subagent_type: %{type: :string, required: true, enum: ["general-purpose", "explore", "plan"], description: "Agent type"},
    run_in_background: %{type: :boolean, required: false, description: "Run asynchronously"},
    model: %{type: :string, required: false, description: "Model override (sonnet, opus, haiku)"}
  }
  ```

### 4.3.2 Spawn Subagent Handler Implementation

Implement the handler for sub-agent spawning.

- [ ] 4.3.2.1 Create `lib/jido_code/tools/handlers/agent/spawn.ex`
- [ ] 4.3.2.2 Validate subagent_type against available types
- [ ] 4.3.2.3 Create agent configuration based on type
- [ ] 4.3.2.4 Spawn TaskAgent with prompt and context
- [ ] 4.3.2.5 If run_in_background, return task_id immediately
- [ ] 4.3.2.6 If synchronous, wait for completion
- [ ] 4.3.2.7 Capture agent output and tool calls
- [ ] 4.3.2.8 Return `{:ok, %{task_id: id, result: result}}` or `{:error, reason}`

### 4.3.3 Unit Tests for Spawn Subagent

- [ ] Test spawn_subagent creates agent
- [ ] Test spawn_subagent with different types
- [ ] Test spawn_subagent background mode returns task_id
- [ ] Test spawn_subagent synchronous mode returns result
- [ ] Test spawn_subagent handles agent failure

---

## 4.4 Todo Write Tool

Implement the todo_write tool for managing task tracking lists.

### 4.4.1 Tool Definition

Create the todo_write tool definition for task management.

- [ ] 4.4.1.1 Create `lib/jido_code/tools/definitions/todo_write.ex`
- [ ] 4.4.1.2 Define schema:
  ```elixir
  %{
    todos: %{type: :array, required: true, items: %{
      content: %{type: :string, required: true, description: "Task description"},
      status: %{type: :string, required: true, enum: ["pending", "in_progress", "completed"]},
      active_form: %{type: :string, required: true, description: "Present continuous form"}
    }}
  }
  ```

### 4.4.2 Todo Write Handler Implementation

Implement the handler for todo list management.

- [ ] 4.4.2.1 Create `lib/jido_code/tools/handlers/todo/write.ex`
- [ ] 4.4.2.2 Validate todo structure
- [ ] 4.4.2.3 Update session state with new todo list
- [ ] 4.4.2.4 Publish todo update via PubSub
- [ ] 4.4.2.5 Return `{:ok, todos}` or `{:error, reason}`

### 4.4.3 Unit Tests for Todo Write

- [ ] Test todo_write creates new list
- [ ] Test todo_write updates existing list
- [ ] Test todo_write validates status enum
- [ ] Test todo_write publishes update

---

## 4.5 Todo Read Tool

Implement the todo_read tool for reading current task list.

### 4.5.1 Tool Definition

Create the todo_read tool definition.

- [ ] 4.5.1.1 Create `lib/jido_code/tools/definitions/todo_read.ex`
- [ ] 4.5.1.2 Define schema:
  ```elixir
  %{
    filter: %{type: :string, required: false, enum: ["all", "pending", "in_progress", "completed"]}
  }
  ```

### 4.5.2 Todo Read Handler Implementation

Implement the handler for reading todos.

- [ ] 4.5.2.1 Create `lib/jido_code/tools/handlers/todo/read.ex`
- [ ] 4.5.2.2 Retrieve todos from session state
- [ ] 4.5.2.3 Apply filter if specified
- [ ] 4.5.2.4 Return `{:ok, todos}` or `{:error, reason}`

### 4.5.3 Unit Tests for Todo Read

- [ ] Test todo_read returns all todos
- [ ] Test todo_read filters by status
- [ ] Test todo_read handles empty list

---

## 4.6 Ask User Tool

Implement the ask_user tool for interactive user questions.

### 4.6.1 Tool Definition

Create the ask_user tool definition for user interaction.

- [ ] 4.6.1.1 Create `lib/jido_code/tools/definitions/ask_user.ex`
- [ ] 4.6.1.2 Define schema:
  ```elixir
  %{
    questions: %{type: :array, required: true, items: %{
      question: %{type: :string, required: true, description: "Question text"},
      header: %{type: :string, required: true, description: "Short label (max 12 chars)"},
      options: %{type: :array, required: true, items: %{
        label: %{type: :string, required: true},
        description: %{type: :string, required: false}
      }},
      multi_select: %{type: :boolean, required: false, description: "Allow multiple selections"}
    }}
  }
  ```

### 4.6.2 Ask User Handler Implementation

Implement the handler for user questions.

- [ ] 4.6.2.1 Create `lib/jido_code/tools/handlers/user/ask.ex`
- [ ] 4.6.2.2 Validate question structure
- [ ] 4.6.2.3 Format questions for TUI display
- [ ] 4.6.2.4 Publish question to TUI via PubSub
- [ ] 4.6.2.5 Wait for user response (blocking)
- [ ] 4.6.2.6 Return `{:ok, %{answers: answers}}` or `{:error, :cancelled}`

### 4.6.3 Unit Tests for Ask User

- [ ] Test ask_user formats questions correctly
- [ ] Test ask_user with single select
- [ ] Test ask_user with multi select
- [ ] Test ask_user handles user cancellation
- [ ] Test ask_user timeout handling

---

## 4.7 Get Task Output Tool

Implement the get_task_output tool for retrieving background agent results.

### 4.7.1 Tool Definition

Create the get_task_output tool definition.

- [ ] 4.7.1.1 Create `lib/jido_code/tools/definitions/get_task_output.ex`
- [ ] 4.7.1.2 Define schema:
  ```elixir
  %{
    task_id: %{type: :string, required: true, description: "Task ID from spawn_subagent"},
    block: %{type: :boolean, required: false, description: "Wait for completion (default: true)"},
    timeout: %{type: :integer, required: false, description: "Max wait time in ms"}
  }
  ```

### 4.7.2 Get Task Output Handler Implementation

Implement the handler for task output retrieval.

- [ ] 4.7.2.1 Create `lib/jido_code/tools/handlers/agent/output.ex`
- [ ] 4.7.2.2 Look up task by task_id
- [ ] 4.7.2.3 If block=true, wait for completion
- [ ] 4.7.2.4 Return task status and result
- [ ] 4.7.2.5 Return `{:ok, %{status: status, result: result}}` or `{:error, reason}`

### 4.7.3 Unit Tests for Get Task Output

- [ ] Test get_task_output retrieves completed task
- [ ] Test get_task_output waits for running task
- [ ] Test get_task_output handles timeout
- [ ] Test get_task_output handles unknown task_id

---

## 4.8 Phase 4 Integration Tests

Integration tests for web and agent tools.

### 4.8.1 Web Integration

Test web tools in realistic scenarios.

- [ ] 4.8.1.1 Create `test/jido_code/integration/tools_phase4_test.exs`
- [ ] 4.8.1.2 Test: web_fetch retrieves hexdocs page
- [ ] 4.8.1.3 Test: web_fetch caches repeated requests
- [ ] 4.8.1.4 Test: web_search finds relevant results

### 4.8.2 Agent Integration

Test agent tools in realistic scenarios.

- [ ] 4.8.2.1 Test: spawn_subagent -> get_task_output retrieves result
- [ ] 4.8.2.2 Test: spawn_subagent background mode
- [ ] 4.8.2.3 Test: Multiple concurrent subagents

### 4.8.3 Todo Integration

Test todo tracking across session.

- [ ] 4.8.3.1 Test: todo_write -> todo_read cycle
- [ ] 4.8.3.2 Test: todo updates published to TUI
- [ ] 4.8.3.3 Test: todos persisted with session

### 4.8.4 User Interaction Integration

Test user interaction tools.

- [ ] 4.8.4.1 Test: ask_user displays in TUI
- [ ] 4.8.4.2 Test: ask_user receives user response

---

## Phase 4 Success Criteria

1. **web_fetch**: HTML-to-markdown with caching
2. **web_search**: Query with domain filtering
3. **spawn_subagent**: Background and synchronous delegation
4. **todo_write/read**: Task tracking with session persistence
5. **ask_user**: Interactive user questions
6. **get_task_output**: Background task result retrieval
7. **Test Coverage**: Minimum 80% for Phase 4 tools

---

## Phase 4 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/web_fetch.ex`
- `lib/jido_code/tools/definitions/web_search.ex`
- `lib/jido_code/tools/definitions/spawn_subagent.ex`
- `lib/jido_code/tools/definitions/todo_write.ex`
- `lib/jido_code/tools/definitions/todo_read.ex`
- `lib/jido_code/tools/definitions/ask_user.ex`
- `lib/jido_code/tools/definitions/get_task_output.ex`
- `lib/jido_code/tools/handlers/web/fetch.ex`
- `lib/jido_code/tools/handlers/web/search.ex`
- `lib/jido_code/tools/handlers/agent/spawn.ex`
- `lib/jido_code/tools/handlers/agent/output.ex`
- `lib/jido_code/tools/handlers/todo/write.ex`
- `lib/jido_code/tools/handlers/todo/read.ex`
- `lib/jido_code/tools/handlers/user/ask.ex`
- `lib/jido_code/tools/web/cache.ex`
- `test/jido_code/tools/handlers/web_test.exs`
- `test/jido_code/tools/handlers/agent_test.exs`
- `test/jido_code/tools/handlers/todo_test.exs`
- `test/jido_code/integration/tools_phase4_test.exs`

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register new tools
