# Phase 5: Elixir-Specific Tools

This phase implements BEAM runtime introspection tools unique to Elixir. These tools provide
capabilities for process inspection, Mix task execution, ETS table inspection, and
documentation retrieval.

**Architectural Decision:** All Phase 5 tools use the Handler pattern (direct Elixir execution
via `Tools.Executor`) per [ADR-0002](../../decisions/0002-phase5-tool-security-and-architecture.md).
This provides simpler architecture and honest security controls compared to the Lua sandbox,
which was found to provide no actual protection for these operations.

## Handler Architecture

All Elixir-specific tools follow this execution flow:

```
┌─────────────────────────────────────────────────────────────────┐
│  Tool Executor receives LLM tool call                           │
│  e.g., {"name": "mix_task", "arguments": {"task": "test"}}      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Executor.execute(tool_call, context: context)                  │
│  Routes to handler based on tool definition                     │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Handler.execute(params, context)                               │
│  e.g., Handlers.Elixir.MixTask.execute(params, context)         │
│  - Validates parameters                                         │
│  - Applies security controls (allowlist, blocklist)             │
│  - Executes operation                                           │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│  Returns {:ok, result} or {:error, reason}                      │
│  Handler emits telemetry for observability                      │
└─────────────────────────────────────────────────────────────────┘
```

## Tools in This Phase

| Tool | Handler Module | Purpose |
|------|----------------|---------|
| mix_task | `Handlers.Elixir.MixTask` | Run Mix tasks with allowlist |
| run_exunit | `Handlers.Elixir.RunExunit` | Run ExUnit tests with filtering |
| get_process_state | `Handlers.Elixir.ProcessState` | Inspect GenServer/process state |
| inspect_supervisor | `Handlers.Elixir.SupervisorTree` | View supervisor tree structure |
| ets_inspect | `Handlers.Elixir.EtsInspect` | Inspect ETS tables |
| fetch_elixir_docs | `Handlers.Elixir.FetchDocs` | Retrieve module/function docs |

## Removed Tools

The following tools were removed due to security concerns per ADR-0002:

| Tool | Reason for Removal |
|------|-------------------|
| iex_eval | Arbitrary code execution cannot be safely sandboxed |
| reload_module | Hot code loading creates code injection vector |

See [ADR-0002](../../decisions/0002-phase5-tool-security-and-architecture.md) for full rationale.

---

## 5.1 Mix Task Tool

Implement the mix_task tool for running Mix tasks with security controls.

### 5.1.1 Tool Definition

Create the mix_task tool definition.

- [x] 5.1.1.1 Create `lib/jido_code/tools/definitions/elixir.ex` (combined Elixir definitions)
- [x] 5.1.1.2 Define schema:
  ```elixir
  %{
    name: "mix_task",
    description: "Run Mix task. Only allowlisted tasks are permitted.",
    handler: JidoCode.Tools.Handlers.Elixir.MixTask,
    parameters: [
      %{name: "task", type: :string, required: true, description: "Mix task name (e.g., 'compile', 'test')"},
      %{name: "args", type: :array, required: false, description: "Task arguments"},
      %{name: "env", type: :string, required: false, enum: ["dev", "test"], description: "Mix environment (prod blocked)"}
    ]
  }
  ```
- [x] 5.1.1.3 Register tool via `Elixir.all/0`

### 5.1.2 Handler Implementation

Implement the Handler for Mix task execution.

- [ ] 5.1.2.1 Create `lib/jido_code/tools/handlers/elixir.ex` with `MixTask` module
- [ ] 5.1.2.2 Define allowed tasks:
  ```elixir
  @allowed_tasks ~w(compile test format deps.get deps.compile deps.tree deps.unlock help credo dialyzer docs hex.info)
  ```
- [ ] 5.1.2.3 Define blocked tasks:
  ```elixir
  @blocked_tasks ~w(release archive.install escript.build local.hex local.rebar hex.publish deps.update do ecto.drop ecto.reset phx.gen.secret)
  ```
- [ ] 5.1.2.4 Validate task against allowlist (reject if not in allowlist or in blocklist)
- [ ] 5.1.2.5 Build mix command: `System.cmd("mix", [task | args], opts)`
- [ ] 5.1.2.6 Set MIX_ENV via environment option (block "prod")
- [ ] 5.1.2.7 Execute in project directory with timeout (default: 60000ms)
- [ ] 5.1.2.8 Capture stdout/stderr
- [ ] 5.1.2.9 Return `{:ok, %{"output" => output, "exit_code" => code}}`
- [ ] 5.1.2.10 Emit telemetry: `[:jido_code, :elixir, :mix_task]`

### 5.1.3 Unit Tests for Mix Task

- [ ] Test mix_task runs compile
- [ ] Test mix_task runs test
- [ ] Test mix_task runs format
- [ ] Test mix_task runs deps.get
- [ ] Test mix_task blocks tasks not in allowlist
- [ ] Test mix_task blocks explicitly blocked tasks
- [ ] Test mix_task blocks prod environment
- [ ] Test mix_task handles task errors
- [ ] Test mix_task respects timeout
- [ ] Test mix_task validates args are strings

---

## 5.2 Run ExUnit Tool

Implement the run_exunit tool for running ExUnit tests with filtering.

### 5.2.1 Tool Definition

- [ ] 5.2.1.1 Add `run_exunit/0` function to `lib/jido_code/tools/definitions/elixir.ex`
- [ ] 5.2.1.2 Define schema:
  ```elixir
  %{
    name: "run_exunit",
    description: "Run ExUnit tests with filtering options.",
    handler: JidoCode.Tools.Handlers.Elixir.RunExunit,
    parameters: [
      %{name: "path", type: :string, required: false, description: "Test file or directory (relative to project)"},
      %{name: "line", type: :integer, required: false, description: "Run test at specific line"},
      %{name: "tag", type: :string, required: false, description: "Run tests with specific tag"},
      %{name: "exclude_tag", type: :string, required: false, description: "Exclude tests with tag"},
      %{name: "max_failures", type: :integer, required: false, description: "Stop after N failures"},
      %{name: "seed", type: :integer, required: false, description: "Random seed"}
    ]
  }
  ```
- [ ] 5.2.1.3 Update `Elixir.all/0` to include `run_exunit()`

### 5.2.2 Handler Implementation

- [ ] 5.2.2.1 Create `RunExunit` module in `lib/jido_code/tools/handlers/elixir.ex`
- [ ] 5.2.2.2 Validate path is within project boundary (use `HandlerHelpers.validate_path/2`)
- [ ] 5.2.2.3 Validate path is within `test/` directory
- [ ] 5.2.2.4 Build mix test command with options:
  - `--trace` for verbose output
  - `--only tag:value` for tag filtering
  - `--exclude tag:value` for exclusion
  - `--max-failures N` for early stop
  - `--seed N` for reproducibility
- [ ] 5.2.2.5 Execute via `System.cmd("mix", ["test" | args], opts)`
- [ ] 5.2.2.6 Parse test output for structured results:
  - Total tests, passed, failed, skipped
  - Failure details with file/line
  - Timing information
- [ ] 5.2.2.7 Return `{:ok, %{"summary" => summary, "failures" => failures, "output" => output}}`
- [ ] 5.2.2.8 Emit telemetry: `[:jido_code, :elixir, :run_exunit]`

### 5.2.3 Unit Tests for Run ExUnit

- [ ] Test run_exunit runs all tests
- [ ] Test run_exunit runs specific file
- [ ] Test run_exunit runs specific line
- [ ] Test run_exunit filters by tag
- [ ] Test run_exunit excludes by tag
- [ ] Test run_exunit parses failures
- [ ] Test run_exunit respects max_failures
- [ ] Test run_exunit blocks path traversal
- [ ] Test run_exunit blocks paths outside test/

---

## 5.3 Get Process State Tool

Implement the get_process_state tool for inspecting GenServer and process state.

### 5.3.1 Tool Definition

- [ ] 5.3.1.1 Add `get_process_state/0` function to `lib/jido_code/tools/definitions/elixir.ex`
- [ ] 5.3.1.2 Define schema:
  ```elixir
  %{
    name: "get_process_state",
    description: "Get state of a GenServer or process. Only project processes can be inspected.",
    handler: JidoCode.Tools.Handlers.Elixir.ProcessState,
    parameters: [
      %{name: "process", type: :string, required: true, description: "Registered name (e.g., 'MyApp.Worker')"},
      %{name: "timeout", type: :integer, required: false, description: "Timeout in ms (default: 5000)"}
    ]
  }
  ```
- [ ] 5.3.1.3 Update `Elixir.all/0` to include `get_process_state()`

### 5.3.2 Handler Implementation

- [ ] 5.3.2.1 Create `ProcessState` module in `lib/jido_code/tools/handlers/elixir.ex`
- [ ] 5.3.2.2 Parse process identifier using `GenServer.whereis/1`:
  - Registered name: `"MyApp.Worker"` -> lookup via registered name
  - Only allow registered names (block raw PIDs for security)
- [ ] 5.3.2.3 Validate process is in project namespace (starts with project module prefix)
- [ ] 5.3.2.4 Block system-critical processes:
  ```elixir
  @blocked_prefixes ~w(JidoCode.Tools JidoCode.Session :kernel :stdlib :init)
  ```
- [ ] 5.3.2.5 Use `:sys.get_state/2` with timeout
- [ ] 5.3.2.6 Handle non-OTP processes gracefully (return process_info instead)
- [ ] 5.3.2.7 Format state for display (inspect with pretty, limit depth)
- [ ] 5.3.2.8 Sanitize output to redact sensitive fields (passwords, tokens, keys)
- [ ] 5.3.2.9 Return `{:ok, %{"state" => state, "process_info" => info}}`
- [ ] 5.3.2.10 Emit telemetry: `[:jido_code, :elixir, :process_state]`

### 5.3.3 Unit Tests for Get Process State

- [ ] Test get_process_state with registered name
- [ ] Test get_process_state with GenServer
- [ ] Test get_process_state with Agent
- [ ] Test get_process_state blocks raw PID strings
- [ ] Test get_process_state blocks system processes
- [ ] Test get_process_state blocks JidoCode internal processes
- [ ] Test get_process_state handles dead process
- [ ] Test get_process_state respects timeout
- [ ] Test get_process_state sanitizes sensitive fields

---

## 5.4 Inspect Supervisor Tool

Implement the inspect_supervisor tool for viewing supervisor tree structure.

### 5.4.1 Tool Definition

- [ ] 5.4.1.1 Add `inspect_supervisor/0` function to `lib/jido_code/tools/definitions/elixir.ex`
- [ ] 5.4.1.2 Define schema:
  ```elixir
  %{
    name: "inspect_supervisor",
    description: "View supervisor tree structure. Only project supervisors can be inspected.",
    handler: JidoCode.Tools.Handlers.Elixir.SupervisorTree,
    parameters: [
      %{name: "supervisor", type: :string, required: true, description: "Supervisor module name"},
      %{name: "depth", type: :integer, required: false, description: "Max tree depth (default: 2, max: 5)"}
    ]
  }
  ```
- [ ] 5.4.1.3 Update `Elixir.all/0` to include `inspect_supervisor()`

### 5.4.2 Handler Implementation

- [ ] 5.4.2.1 Create `SupervisorTree` module in `lib/jido_code/tools/handlers/elixir.ex`
- [ ] 5.4.2.2 Parse supervisor identifier (registered name only)
- [ ] 5.4.2.3 Validate supervisor is in project namespace
- [ ] 5.4.2.4 Block system supervisors (same prefix list as process_state)
- [ ] 5.4.2.5 Enforce depth limit (max 5, default 2)
- [ ] 5.4.2.6 Use `Supervisor.which_children/1`
- [ ] 5.4.2.7 Recursively inspect child supervisors up to depth
- [ ] 5.4.2.8 Limit children count per level (max 50)
- [ ] 5.4.2.9 Format tree structure for display
- [ ] 5.4.2.10 Return `{:ok, %{"tree" => tree_string, "children" => list}}`
- [ ] 5.4.2.11 Emit telemetry: `[:jido_code, :elixir, :supervisor_tree]`

### 5.4.3 Unit Tests for Inspect Supervisor

- [ ] Test inspect_supervisor with Application supervisor
- [ ] Test inspect_supervisor shows children
- [ ] Test inspect_supervisor respects depth limit
- [ ] Test inspect_supervisor enforces max depth of 5
- [ ] Test inspect_supervisor handles DynamicSupervisor
- [ ] Test inspect_supervisor blocks system supervisors
- [ ] Test inspect_supervisor handles dead supervisor
- [ ] Test inspect_supervisor limits children count

---

## 5.5 ETS Inspect Tool

Implement the ets_inspect tool for ETS table inspection.

### 5.5.1 Tool Definition

- [ ] 5.5.1.1 Add `ets_inspect/0` function to `lib/jido_code/tools/definitions/elixir.ex`
- [ ] 5.5.1.2 Define schema:
  ```elixir
  %{
    name: "ets_inspect",
    description: "Inspect ETS tables. Only project-owned tables can be inspected.",
    handler: JidoCode.Tools.Handlers.Elixir.EtsInspect,
    parameters: [
      %{name: "operation", type: :string, required: true,
        enum: ["list", "info", "lookup", "sample"], description: "Operation to perform"},
      %{name: "table", type: :string, required: false, description: "Table name (required for info/lookup/sample)"},
      %{name: "key", type: :string, required: false, description: "Key for lookup (as string)"},
      %{name: "limit", type: :integer, required: false, description: "Max entries for sample (default: 10, max: 100)"}
    ]
  }
  ```
- [ ] 5.5.1.3 Update `Elixir.all/0` to include `ets_inspect()`

### 5.5.2 Handler Implementation

- [ ] 5.5.2.1 Create `EtsInspect` module in `lib/jido_code/tools/handlers/elixir.ex`
- [ ] 5.5.2.2 Implement `list` operation:
  - Get all tables via `:ets.all()`
  - Filter to project-owned tables (owner process in project namespace)
  - Return table names and basic info
- [ ] 5.5.2.3 Implement `info` operation:
  - Validate table is project-owned
  - Return `:ets.info(table)` data
- [ ] 5.5.2.4 Implement `lookup` operation:
  - Validate table is project-owned and public
  - Parse key from string (support simple types)
  - Return `:ets.lookup(table, key)` results
- [ ] 5.5.2.5 Implement `sample` operation (safer alternative to match):
  - Validate table is project-owned and public
  - Use `:ets.first/1` and `:ets.next/2` for pagination
  - Return first N entries up to limit
- [ ] 5.5.2.6 Check table access level (block protected/private from non-owner)
- [ ] 5.5.2.7 Block system ETS tables:
  ```elixir
  @blocked_tables ~w(code ac_tab file_io_servers shell_records)a
  ```
- [ ] 5.5.2.8 Enforce limit (max 100, default 10)
- [ ] 5.5.2.9 Format results for display (inspect with limits)
- [ ] 5.5.2.10 Return `{:ok, %{"result" => result, "count" => count}}`
- [ ] 5.5.2.11 Emit telemetry: `[:jido_code, :elixir, :ets_inspect]`

### 5.5.3 Unit Tests for ETS Inspect

- [ ] Test ets_inspect list operation
- [ ] Test ets_inspect info operation
- [ ] Test ets_inspect lookup operation
- [ ] Test ets_inspect sample operation
- [ ] Test ets_inspect blocks system tables
- [ ] Test ets_inspect respects table access levels
- [ ] Test ets_inspect enforces limit
- [ ] Test ets_inspect handles non-existent table
- [ ] Test ets_inspect filters to project-owned tables

---

## 5.6 Fetch Elixir Docs Tool

Implement the fetch_elixir_docs tool for retrieving module and function documentation.

### 5.6.1 Tool Definition

- [ ] 5.6.1.1 Add `fetch_elixir_docs/0` function to `lib/jido_code/tools/definitions/elixir.ex`
- [ ] 5.6.1.2 Define schema:
  ```elixir
  %{
    name: "fetch_elixir_docs",
    description: "Retrieve documentation for Elixir module or function.",
    handler: JidoCode.Tools.Handlers.Elixir.FetchDocs,
    parameters: [
      %{name: "module", type: :string, required: true, description: "Module name (e.g., 'Enum', 'MyApp.Worker')"},
      %{name: "function", type: :string, required: false, description: "Function name"},
      %{name: "arity", type: :integer, required: false, description: "Function arity"}
    ]
  }
  ```
- [ ] 5.6.1.3 Update `Elixir.all/0` to include `fetch_elixir_docs()`

### 5.6.2 Handler Implementation

- [ ] 5.6.2.1 Create `FetchDocs` module in `lib/jido_code/tools/handlers/elixir.ex`
- [ ] 5.6.2.2 Parse module name safely:
  - Use `String.to_existing_atom/1` to prevent atom table exhaustion
  - Handle "Elixir." prefix automatically
  - Return error for non-existent modules
- [ ] 5.6.2.3 Use `Code.fetch_docs/1` for documentation
- [ ] 5.6.2.4 Filter to specific function/arity if specified
- [ ] 5.6.2.5 Include type specs via `Code.Typespec.fetch_specs/1`
- [ ] 5.6.2.6 Format documentation (preserve markdown)
- [ ] 5.6.2.7 Handle undocumented modules gracefully
- [ ] 5.6.2.8 Return `{:ok, %{"moduledoc" => doc, "docs" => function_docs, "specs" => specs}}`
- [ ] 5.6.2.9 Emit telemetry: `[:jido_code, :elixir, :fetch_docs]`

### 5.6.3 Unit Tests for Fetch Elixir Docs

- [ ] Test fetch_elixir_docs for standard library module (Enum)
- [ ] Test fetch_elixir_docs for specific function
- [ ] Test fetch_elixir_docs for function with arity
- [ ] Test fetch_elixir_docs includes specs
- [ ] Test fetch_elixir_docs handles undocumented module
- [ ] Test fetch_elixir_docs rejects non-existent module
- [ ] Test fetch_elixir_docs uses existing atoms only (no atom table exhaustion)

---

## 5.7 Phase 5 Integration Tests

Integration tests for Elixir-specific tools using the Handler pattern.

### 5.7.1 Handler Integration

Verify tools execute through the Executor → Handler chain correctly.

- [ ] 5.7.1.1 Create `test/jido_code/integration/tools_phase5_test.exs`
- [ ] 5.7.1.2 Test: All tools execute through `Tools.Executor` → Handler chain
- [ ] 5.7.1.3 Test: Session context passed correctly to handlers
- [ ] 5.7.1.4 Test: Telemetry events emitted for all operations

### 5.7.2 Mix/Test Integration

Test Mix and ExUnit tools in realistic scenarios.

- [ ] 5.7.2.1 Test: mix_task compile works in test project
- [ ] 5.7.2.2 Test: mix_task test runs tests
- [ ] 5.7.2.3 Test: run_exunit parses real test output
- [ ] 5.7.2.4 Test: run_exunit handles test failures

### 5.7.3 Runtime Introspection Integration

Test runtime introspection tools with real processes.

- [ ] 5.7.3.1 Test: get_process_state inspects test GenServer
- [ ] 5.7.3.2 Test: inspect_supervisor shows test supervisor tree
- [ ] 5.7.3.3 Test: ets_inspect lists test ETS tables
- [ ] 5.7.3.4 Test: ets_inspect looks up test data

### 5.7.4 Documentation Integration

Test documentation retrieval.

- [ ] 5.7.4.1 Test: fetch_elixir_docs retrieves Enum docs
- [ ] 5.7.4.2 Test: fetch_elixir_docs retrieves project module docs

### 5.7.5 Security Integration

Test security controls are enforced.

- [ ] 5.7.5.1 Test: mix_task rejects blocked tasks
- [ ] 5.7.5.2 Test: run_exunit rejects path traversal
- [ ] 5.7.5.3 Test: get_process_state rejects system processes
- [ ] 5.7.5.4 Test: ets_inspect rejects system tables
- [ ] 5.7.5.5 Test: All tools reject requests outside project boundary

---

## Phase 5 Success Criteria

| Criterion | Description |
|-----------|-------------|
| **mix_task** | Safe Mix execution via Handler with task allowlist |
| **run_exunit** | Test execution with filtering and output parsing |
| **get_process_state** | Process inspection with namespace restriction |
| **inspect_supervisor** | Supervisor tree with depth limit |
| **ets_inspect** | ETS operations with table ownership filtering |
| **fetch_elixir_docs** | Documentation retrieval with safe atom handling |
| **Handler pattern** | All tools use Executor → Handler chain |
| **Security controls** | Each handler enforces appropriate restrictions |
| **Security infrastructure** | Opt-in middleware, isolation, sanitization, rate limiting, audit logging |
| **Test Coverage** | Minimum 80% for Phase 5 tools |

---

## Phase 5 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/elixir.ex` - All Elixir tool definitions
- `lib/jido_code/tools/handlers/elixir.ex` - All Elixir handlers (MixTask, RunExunit, ProcessState, SupervisorTree, EtsInspect, FetchDocs)
- `test/jido_code/tools/definitions/elixir_test.exs` - Tool definition tests
- `test/jido_code/tools/handlers/elixir_test.exs` - Handler unit tests
- `test/jido_code/integration/tools_phase5_test.exs` - Integration tests

**Modified Files:**
- `lib/jido_code/tools.ex` - Register Elixir tools via `Definitions.Elixir.all()`

**Documentation:**
- `notes/decisions/0002-phase5-tool-security-and-architecture.md` - ADR for removed tools and Handler pattern
- `notes/decisions/0003-handler-security-infrastructure.md` - ADR for centralized security infrastructure

---

## 5.8 Handler Security Infrastructure

Implement centralized security infrastructure for all Handler-based tools. This provides
opt-in security enhancements without requiring changes to existing handlers.

**Architectural Decision:** See [ADR-0003](../../decisions/0003-handler-security-infrastructure.md).

### 5.8.1 SecureHandler Behavior

Define a behavior for handlers to declare security properties.

- [x] 5.8.1.1 Create `lib/jido_code/tools/behaviours/secure_handler.ex`
- [x] 5.8.1.2 Define `@callback security_properties/0`:
  ```elixir
  @type security_properties :: %{
    required(:tier) => :read_only | :write | :execute | :privileged,
    optional(:rate_limit) => {count :: pos_integer(), window_ms :: pos_integer()},
    optional(:timeout_ms) => pos_integer(),
    optional(:requires_consent) => boolean()
  }
  ```
- [x] 5.8.1.3 Define `@callback validate_security(args, context) :: :ok | {:error, reason}`
- [x] 5.8.1.4 Define `@callback sanitize_output(result) :: term()` with default
- [x] 5.8.1.5 Provide `__using__` macro with defaults
- [x] 5.8.1.6 Document tiers: `:read_only`, `:write`, `:execute`, `:privileged`
- [x] 5.8.1.7 Emit telemetry: `[:jido_code, :security, :handler_loaded]`

### 5.8.2 Security Middleware

Implement pre-execution security checks in Executor.

- [x] 5.8.2.1 Create `lib/jido_code/tools/security/middleware.ex`
- [x] 5.8.2.2 Implement `run_checks/3`:
  ```elixir
  def run_checks(tool, args, context) do
    with :ok <- check_rate_limit(tool, context),
         :ok <- check_permission_tier(tool, context),
         :ok <- check_consent_requirement(tool, context) do
      :ok
    end
  end
  ```
- [x] 5.8.2.3 Implement `check_rate_limit/2`
- [x] 5.8.2.4 Implement `check_permission_tier/2`
- [x] 5.8.2.5 Implement `check_consent_requirement/2`
- [x] 5.8.2.6 Add middleware hook to `Executor.execute/2`
- [x] 5.8.2.7 Make opt-in via config: `config :jido_code, security_middleware: true`
- [x] 5.8.2.8 Emit telemetry: `[:jido_code, :security, :middleware_check]`

### 5.8.3 Process Isolation

Implement process isolation for handler execution.

- [x] 5.8.3.1 Create `lib/jido_code/tools/security/isolated_executor.ex`
- [x] 5.8.3.2 Implement `execute_isolated/4` with Task.Supervisor
- [x] 5.8.3.3 Add `JidoCode.Tools.TaskSupervisor` to supervision tree (already exists)
- [x] 5.8.3.4 Enforce memory limit via `:max_heap_size` process flag
- [x] 5.8.3.5 Implement timeout with graceful shutdown
- [x] 5.8.3.6 Handle process crashes without affecting main app
- [x] 5.8.3.7 Emit telemetry: `[:jido_code, :security, :isolation]`

### 5.8.4 Output Sanitization

Implement automatic redaction of sensitive data.

- [x] 5.8.4.1 Create `lib/jido_code/tools/security/output_sanitizer.ex`
- [x] 5.8.4.2 Define sensitive patterns:
  ```elixir
  @sensitive_patterns [
    {~r/(?i)(password|secret|api_?key|token)\s*[:=]\s*\S+/, "[REDACTED]"},
    {~r/(?i)bearer\s+[a-zA-Z0-9._-]+/, "[REDACTED_BEARER]"},
    {~r/sk-[a-zA-Z0-9]{48,}/, "[REDACTED_API_KEY]"},
    {~r/ghp_[a-zA-Z0-9]{36,}/, "[REDACTED_GITHUB_TOKEN]"}
  ]
  ```
- [x] 5.8.4.3 Implement `sanitize/1` for strings
- [x] 5.8.4.4 Implement `sanitize/1` for maps (recursive)
- [x] 5.8.4.5 Define sensitive field names for map key redaction
- [x] 5.8.4.6 Apply in Executor after handler returns
- [x] 5.8.4.7 Emit telemetry: `[:jido_code, :security, :output_sanitized]`

### 5.8.5 Rate Limiting

Implement per-session, per-tool rate limiting.

- [x] 5.8.5.1 Create `lib/jido_code/tools/security/rate_limiter.ex`
- [x] 5.8.5.2 Use ETS table for tracking
- [x] 5.8.5.3 Implement sliding window algorithm
- [x] 5.8.5.4 Define default limits per tier:
  ```elixir
  @default_limits %{
    read_only: {100, :timer.minutes(1)},
    write: {30, :timer.minutes(1)},
    execute: {10, :timer.minutes(1)},
    privileged: {5, :timer.minutes(1)}
  }
  ```
- [x] 5.8.5.5 Implement periodic cleanup of expired entries
- [x] 5.8.5.6 Include retry-after in error response
- [x] 5.8.5.7 Emit telemetry: `[:jido_code, :security, :rate_limited]`

### 5.8.6 Audit Logging

Implement comprehensive invocation logging.

- [x] 5.8.6.1 Create `lib/jido_code/tools/security/audit_logger.ex`
- [x] 5.8.6.2 Define audit entry structure (timestamp, session, tool, status, duration)
- [x] 5.8.6.3 Implement `log_invocation/4` called from Executor
- [x] 5.8.6.4 Hash arguments for privacy (don't log raw values)
- [x] 5.8.6.5 Store in ETS ring buffer (default 10000 entries)
- [x] 5.8.6.6 Implement `get_audit_log/1` for session-specific trail
- [x] 5.8.6.7 Emit telemetry: `[:jido_code, :security, :audit]`
- [x] 5.8.6.8 Integrate with Logger for blocked invocations

### 5.8.7 Permission Tiers

Implement tool categorization with graduated access.

- [x] 5.8.7.1 Create `lib/jido_code/tools/security/permissions.ex`
- [x] 5.8.7.2 Define tier hierarchy: `[:read_only, :write, :execute, :privileged]`
- [x] 5.8.7.3 Define default tool-to-tier mapping
- [ ] 5.8.7.4 Add `granted_tier` and `consented_tools` to Session.State (deferred - requires Session.State changes)
- [x] 5.8.7.5 Implement `grant_tier/2` for permission upgrades
- [x] 5.8.7.6 Implement `record_consent/2` for explicit consent
- [x] 5.8.7.7 Implement `check_permission/3` for middleware
- [x] 5.8.7.8 Emit telemetry: `[:jido_code, :security, :permission_denied]`

### 5.8.8 Unit Tests

- [x] 5.8.8.1 Test SecureHandler behavior callbacks
- [x] 5.8.8.2 Test Middleware.run_checks passes/blocks correctly
- [x] 5.8.8.3 Test IsolatedExecutor timeout enforcement
- [x] 5.8.8.4 Test IsolatedExecutor memory limit
- [x] 5.8.8.5 Test OutputSanitizer pattern redaction
- [x] 5.8.8.6 Test OutputSanitizer nested map handling
- [x] 5.8.8.7 Test RateLimiter within/exceeds limit
- [x] 5.8.8.8 Test RateLimiter sliding window
- [x] 5.8.8.9 Test AuditLogger invocation recording
- [x] 5.8.8.10 Test Permissions tier hierarchy
- [x] 5.8.8.11 Test all telemetry events emitted

### 5.8.9 Integration Tests

- [x] 5.8.9.1 Create `test/jido_code/integration/tools_security_test.exs`
- [x] 5.8.9.2 Test: Executor applies middleware when enabled
- [x] 5.8.9.3 Test: Rate limiting blocks rapid calls
- [x] 5.8.9.4 Test: Output sanitization removes secrets
- [x] 5.8.9.5 Test: Process isolation kills runaway handler (covered via IsolatedExecutor unit tests)
- [x] 5.8.9.6 Test: Permission tier blocks privileged tools
- [x] 5.8.9.7 Test: Audit log captures blocked invocations

---

## 5.8 Critical Files

**New Files (Section 5.8):**
- `lib/jido_code/tools/behaviours/secure_handler.ex` - SecureHandler behavior
- `lib/jido_code/tools/security/middleware.ex` - Pre-execution checks
- `lib/jido_code/tools/security/isolated_executor.ex` - Process isolation
- `lib/jido_code/tools/security/output_sanitizer.ex` - Output redaction
- `lib/jido_code/tools/security/rate_limiter.ex` - Rate limiting
- `lib/jido_code/tools/security/audit_logger.ex` - Audit logging
- `lib/jido_code/tools/security/permissions.ex` - Permission tiers
- `test/jido_code/tools/security/*_test.exs` - Security unit tests
- `test/jido_code/integration/tools_security_test.exs` - Security integration tests

**Modified Files (Section 5.8):**
- `lib/jido_code/tools/executor.ex` - Add middleware hook
- `lib/jido_code/application.ex` - Add TaskSupervisor
