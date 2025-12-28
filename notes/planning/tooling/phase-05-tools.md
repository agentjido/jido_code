# Phase 5: Elixir-Specific Tools

This phase implements BEAM runtime introspection tools unique to Elixir. These tools provide powerful capabilities for code evaluation, process inspection, hot reloading, and ETS table management that are unavailable in other language ecosystems.

## Tools in This Phase

| Tool | Purpose | Priority |
|------|---------|----------|
| iex_eval | Evaluate Elixir code with bindings | Advanced |
| mix_task | Run Mix tasks | Advanced |
| get_process_state | Inspect GenServer/process state | Advanced |
| inspect_supervisor | View supervisor tree | Advanced |
| reload_module | Hot reload module | Advanced |
| ets_inspect | Inspect ETS tables | Advanced |
| fetch_elixir_docs | Retrieve module/function docs | Advanced |
| run_exunit | Run ExUnit tests | Advanced |

---

## 5.1 IEx Eval Tool

Implement the iex_eval tool for evaluating Elixir code expressions with bindings and state.

### 5.1.1 Tool Definition

Create the iex_eval tool definition for code evaluation.

- [ ] 5.1.1.1 Create `lib/jido_code/tools/definitions/iex_eval.ex`
- [ ] 5.1.1.2 Define schema:
  ```elixir
  %{
    code: %{type: :string, required: true, description: "Elixir code to evaluate"},
    bindings: %{type: :map, required: false, description: "Variable bindings"},
    timeout: %{type: :integer, required: false, description: "Evaluation timeout in ms (default: 5000)"}
  }
  ```
- [ ] 5.1.1.3 Document safety considerations

### 5.1.2 IEx Eval Handler Implementation

Implement the handler for code evaluation.

- [ ] 5.1.2.1 Create `lib/jido_code/tools/handlers/elixir/iex_eval.ex`
- [ ] 5.1.2.2 Parse bindings into keyword list format
- [ ] 5.1.2.3 Use Code.eval_string with bindings
- [ ] 5.1.2.4 Wrap evaluation in Task with timeout
- [ ] 5.1.2.5 Capture result and updated bindings
- [ ] 5.1.2.6 Handle evaluation errors gracefully
- [ ] 5.1.2.7 Format result for display (inspect with pretty)
- [ ] 5.1.2.8 Return `{:ok, %{result: result, bindings: bindings}}` or `{:error, reason}`

### 5.1.3 Unit Tests for IEx Eval

- [ ] Test iex_eval with simple expressions
- [ ] Test iex_eval with bindings
- [ ] Test iex_eval updates bindings
- [ ] Test iex_eval captures syntax errors
- [ ] Test iex_eval captures runtime errors
- [ ] Test iex_eval respects timeout
- [ ] Test iex_eval handles complex expressions
- [ ] Test iex_eval handles module definitions

---

## 5.2 Mix Task Tool

Implement the mix_task tool for running Mix tasks with arguments.

### 5.2.1 Tool Definition

Create the mix_task tool definition for task execution.

- [ ] 5.2.1.1 Create `lib/jido_code/tools/definitions/mix_task.ex`
- [ ] 5.2.1.2 Define schema:
  ```elixir
  %{
    task: %{type: :string, required: true, description: "Mix task name (e.g., 'compile', 'test')"},
    args: %{type: :array, required: false, description: "Task arguments"},
    env: %{type: :string, required: false, enum: ["dev", "test", "prod"], description: "Mix environment"}
  }
  ```
- [ ] 5.2.1.3 Document allowed and blocked tasks

### 5.2.2 Mix Task Handler Implementation

Implement the handler for Mix task execution.

- [ ] 5.2.2.1 Create `lib/jido_code/tools/handlers/elixir/mix_task.ex`
- [ ] 5.2.2.2 Define allowed tasks:
  - compile, compile.all
  - test, test.all
  - format
  - deps.get, deps.compile, deps.tree
  - help
  - credo
  - dialyzer
- [ ] 5.2.2.3 Define blocked tasks:
  - release (production concern)
  - ecto.drop, ecto.reset (destructive)
  - phx.gen.secret (security)
- [ ] 5.2.2.4 Validate task against allowlist
- [ ] 5.2.2.5 Build mix command with arguments
- [ ] 5.2.2.6 Set MIX_ENV if specified
- [ ] 5.2.2.7 Execute mix task with output capture
- [ ] 5.2.2.8 Parse output for structured results
- [ ] 5.2.2.9 Return `{:ok, %{output: output, exit_code: code}}` or `{:error, reason}`

### 5.2.3 Unit Tests for Mix Task

- [ ] Test mix_task runs compile
- [ ] Test mix_task runs test
- [ ] Test mix_task runs test with filter
- [ ] Test mix_task runs format
- [ ] Test mix_task runs deps.get
- [ ] Test mix_task blocks dangerous tasks
- [ ] Test mix_task sets MIX_ENV
- [ ] Test mix_task handles task errors

---

## 5.3 Get Process State Tool

Implement the get_process_state tool for inspecting GenServer and process state.

### 5.3.1 Tool Definition

Create the get_process_state tool definition for process inspection.

- [ ] 5.3.1.1 Create `lib/jido_code/tools/definitions/get_process_state.ex`
- [ ] 5.3.1.2 Define schema:
  ```elixir
  %{
    process: %{type: :string, required: true, description: "PID string, registered name, or module name"},
    timeout: %{type: :integer, required: false, description: "Timeout in ms (default: 5000)"}
  }
  ```

### 5.3.2 Get Process State Handler Implementation

Implement the handler for process state retrieval.

- [ ] 5.3.2.1 Create `lib/jido_code/tools/handlers/elixir/process_state.ex`
- [ ] 5.3.2.2 Parse process identifier:
  - PID string: "#PID<0.123.0>" -> :erlang.list_to_pid
  - Registered name: "MyApp.Worker" -> Process.whereis
  - Module with __via__: lookup through registry
- [ ] 5.3.2.3 Use :sys.get_state/2 for GenServer/gen_statem
- [ ] 5.3.2.4 Handle process_info for raw processes
- [ ] 5.3.2.5 Format state for display (inspect with pretty)
- [ ] 5.3.2.6 Return `{:ok, %{state: state, process_info: info}}` or `{:error, reason}`

### 5.3.3 Unit Tests for Get Process State

- [ ] Test get_process_state with PID string
- [ ] Test get_process_state with registered name
- [ ] Test get_process_state with GenServer
- [ ] Test get_process_state with Agent
- [ ] Test get_process_state handles dead process
- [ ] Test get_process_state respects timeout

---

## 5.4 Inspect Supervisor Tool

Implement the inspect_supervisor tool for viewing supervisor trees.

### 5.4.1 Tool Definition

Create the inspect_supervisor tool definition.

- [ ] 5.4.1.1 Create `lib/jido_code/tools/definitions/inspect_supervisor.ex`
- [ ] 5.4.1.2 Define schema:
  ```elixir
  %{
    supervisor: %{type: :string, required: true, description: "Supervisor module or PID"},
    depth: %{type: :integer, required: false, description: "Max tree depth (default: 3)"}
  }
  ```

### 5.4.2 Inspect Supervisor Handler Implementation

Implement the handler for supervisor tree inspection.

- [ ] 5.4.2.1 Create `lib/jido_code/tools/handlers/elixir/supervisor.ex`
- [ ] 5.4.2.2 Parse supervisor identifier
- [ ] 5.4.2.3 Use Supervisor.which_children/1
- [ ] 5.4.2.4 Recursively inspect child supervisors up to depth
- [ ] 5.4.2.5 Format tree structure for display:
  ```
  MyApp.Supervisor
  ├── MyApp.Worker (worker, running)
  ├── MyApp.TaskSupervisor (supervisor)
  │   ├── Task.Supervisor (worker, running)
  │   └── ...
  └── MyApp.Registry (worker, running)
  ```
- [ ] 5.4.2.6 Return `{:ok, %{tree: tree_string, children: list}}` or `{:error, reason}`

### 5.4.3 Unit Tests for Inspect Supervisor

- [ ] Test inspect_supervisor with Application supervisor
- [ ] Test inspect_supervisor shows children
- [ ] Test inspect_supervisor respects depth limit
- [ ] Test inspect_supervisor handles DynamicSupervisor
- [ ] Test inspect_supervisor handles dead supervisor

---

## 5.5 Reload Module Tool

Implement the reload_module tool for hot code reloading.

### 5.5.1 Tool Definition

Create the reload_module tool definition.

- [ ] 5.5.1.1 Create `lib/jido_code/tools/definitions/reload_module.ex`
- [ ] 5.5.1.2 Define schema:
  ```elixir
  %{
    module: %{type: :string, required: true, description: "Module name to reload"},
    recompile: %{type: :boolean, required: false, description: "Recompile before reload (default: true)"}
  }
  ```

### 5.5.2 Reload Module Handler Implementation

Implement the handler for module hot reloading.

- [ ] 5.5.2.1 Create `lib/jido_code/tools/handlers/elixir/reload.ex`
- [ ] 5.5.2.2 Parse module name to atom
- [ ] 5.5.2.3 If recompile=true, run Mix.Task.rerun("compile")
- [ ] 5.5.2.4 Use Code.purge/1 to remove old code
- [ ] 5.5.2.5 Use Code.load_file or IEx.Helpers.r for reload
- [ ] 5.5.2.6 Verify module loaded successfully
- [ ] 5.5.2.7 Return `{:ok, %{module: module, functions: exports}}` or `{:error, reason}`

### 5.5.3 Unit Tests for Reload Module

- [ ] Test reload_module reloads existing module
- [ ] Test reload_module with recompile
- [ ] Test reload_module handles non-existent module
- [ ] Test reload_module handles compilation errors

---

## 5.6 ETS Inspect Tool

Implement the ets_inspect tool for ETS table inspection.

### 5.6.1 Tool Definition

Create the ets_inspect tool definition.

- [ ] 5.6.1.1 Create `lib/jido_code/tools/definitions/ets_inspect.ex`
- [ ] 5.6.1.2 Define schema:
  ```elixir
  %{
    operation: %{type: :string, required: true, enum: ["list", "info", "lookup", "match"], description: "Operation to perform"},
    table: %{type: :string, required: false, description: "Table name or reference (required for info/lookup/match)"},
    key: %{type: :any, required: false, description: "Key for lookup"},
    pattern: %{type: :any, required: false, description: "Match pattern"},
    limit: %{type: :integer, required: false, description: "Max entries to return"}
  }
  ```

### 5.6.2 ETS Inspect Handler Implementation

Implement the handler for ETS operations.

- [ ] 5.6.2.1 Create `lib/jido_code/tools/handlers/elixir/ets.ex`
- [ ] 5.6.2.2 Implement `list` operation: :ets.all() with table info
- [ ] 5.6.2.3 Implement `info` operation: :ets.info(table)
- [ ] 5.6.2.4 Implement `lookup` operation: :ets.lookup(table, key)
- [ ] 5.6.2.5 Implement `match` operation: :ets.match(table, pattern, limit)
- [ ] 5.6.2.6 Format results for display
- [ ] 5.6.2.7 Return `{:ok, result}` or `{:error, reason}`

### 5.6.3 Unit Tests for ETS Inspect

- [ ] Test ets_inspect list operation
- [ ] Test ets_inspect info operation
- [ ] Test ets_inspect lookup operation
- [ ] Test ets_inspect match operation
- [ ] Test ets_inspect handles non-existent table
- [ ] Test ets_inspect respects limit

---

## 5.7 Fetch Elixir Docs Tool

Implement the fetch_elixir_docs tool for retrieving module and function documentation.

### 5.7.1 Tool Definition

Create the fetch_elixir_docs tool definition.

- [ ] 5.7.1.1 Create `lib/jido_code/tools/definitions/fetch_elixir_docs.ex`
- [ ] 5.7.1.2 Define schema:
  ```elixir
  %{
    module: %{type: :string, required: true, description: "Module name"},
    function: %{type: :string, required: false, description: "Function name (optional)"},
    arity: %{type: :integer, required: false, description: "Function arity (optional)"}
  }
  ```

### 5.7.2 Fetch Elixir Docs Handler Implementation

Implement the handler for documentation retrieval.

- [ ] 5.7.2.1 Create `lib/jido_code/tools/handlers/elixir/docs.ex`
- [ ] 5.7.2.2 Parse module name to atom
- [ ] 5.7.2.3 Use Code.fetch_docs/1 for module docs
- [ ] 5.7.2.4 Filter to specific function/arity if specified
- [ ] 5.7.2.5 Format documentation (markdown conversion)
- [ ] 5.7.2.6 Include specs if available
- [ ] 5.7.2.7 Return `{:ok, %{moduledoc: doc, docs: function_docs}}` or `{:error, reason}`

### 5.7.3 Unit Tests for Fetch Elixir Docs

- [ ] Test fetch_elixir_docs for module
- [ ] Test fetch_elixir_docs for specific function
- [ ] Test fetch_elixir_docs for function with arity
- [ ] Test fetch_elixir_docs includes specs
- [ ] Test fetch_elixir_docs handles undocumented module

---

## 5.8 Run ExUnit Tool

Implement the run_exunit tool for running ExUnit tests with fine-grained control.

### 5.8.1 Tool Definition

Create the run_exunit tool definition.

- [ ] 5.8.1.1 Create `lib/jido_code/tools/definitions/run_exunit.ex`
- [ ] 5.8.1.2 Define schema:
  ```elixir
  %{
    path: %{type: :string, required: false, description: "Test file or directory"},
    line: %{type: :integer, required: false, description: "Run test at specific line"},
    tag: %{type: :string, required: false, description: "Run tests with specific tag"},
    exclude_tag: %{type: :string, required: false, description: "Exclude tests with tag"},
    seed: %{type: :integer, required: false, description: "Random seed"},
    max_failures: %{type: :integer, required: false, description: "Stop after N failures"}
  }
  ```

### 5.8.2 Run ExUnit Handler Implementation

Implement the handler for test execution.

- [ ] 5.8.2.1 Create `lib/jido_code/tools/handlers/elixir/exunit.ex`
- [ ] 5.8.2.2 Build mix test command with options
- [ ] 5.8.2.3 Add --trace for verbose output
- [ ] 5.8.2.4 Execute tests and capture output
- [ ] 5.8.2.5 Parse test results:
  - Total tests, passed, failed, skipped
  - Failure details with file/line
  - Timing information
- [ ] 5.8.2.6 Return `{:ok, %{summary: summary, failures: failures, output: output}}` or `{:error, reason}`

### 5.8.3 Unit Tests for Run ExUnit

- [ ] Test run_exunit runs all tests
- [ ] Test run_exunit runs specific file
- [ ] Test run_exunit runs specific line
- [ ] Test run_exunit filters by tag
- [ ] Test run_exunit excludes by tag
- [ ] Test run_exunit parses failures
- [ ] Test run_exunit respects max_failures

---

## 5.9 Phase 5 Integration Tests

Integration tests for Elixir-specific tools.

### 5.9.1 Runtime Introspection Integration

Test runtime introspection tools together.

- [ ] 5.9.1.1 Create `test/jido_code/integration/tools_phase5_test.exs`
- [ ] 5.9.1.2 Test: iex_eval creates GenServer -> get_process_state inspects it
- [ ] 5.9.1.3 Test: Mix task execution and output parsing
- [ ] 5.9.1.4 Test: Hot reload after file edit

### 5.9.2 BEAM-Specific Integration

Test BEAM-specific introspection tools.

- [ ] 5.9.2.1 Test: ETS table creation -> ets_inspect list/info/lookup
- [ ] 5.9.2.2 Test: Supervisor tree traversal
- [ ] 5.9.2.3 Test: GenServer state inspection

### 5.9.3 Documentation Integration

Test documentation tools.

- [ ] 5.9.3.1 Test: fetch_elixir_docs for standard library modules
- [ ] 5.9.3.2 Test: fetch_elixir_docs for project modules

### 5.9.4 Testing Integration

Test ExUnit integration.

- [ ] 5.9.4.1 Test: run_exunit executes tests
- [ ] 5.9.4.2 Test: run_exunit parses failures correctly

---

## Phase 5 Success Criteria

1. **iex_eval**: Code evaluation with bindings and timeout
2. **mix_task**: Safe Mix task execution
3. **get_process_state**: GenServer/process state inspection
4. **inspect_supervisor**: Supervisor tree visualization
5. **reload_module**: Hot code reloading
6. **ets_inspect**: ETS table operations
7. **fetch_elixir_docs**: Documentation retrieval
8. **run_exunit**: Test execution with filtering
9. **Test Coverage**: Minimum 80% for Phase 5 tools

---

## Phase 5 Critical Files

**New Files:**
- `lib/jido_code/tools/definitions/iex_eval.ex`
- `lib/jido_code/tools/definitions/mix_task.ex`
- `lib/jido_code/tools/definitions/get_process_state.ex`
- `lib/jido_code/tools/definitions/inspect_supervisor.ex`
- `lib/jido_code/tools/definitions/reload_module.ex`
- `lib/jido_code/tools/definitions/ets_inspect.ex`
- `lib/jido_code/tools/definitions/fetch_elixir_docs.ex`
- `lib/jido_code/tools/definitions/run_exunit.ex`
- `lib/jido_code/tools/handlers/elixir/iex_eval.ex`
- `lib/jido_code/tools/handlers/elixir/mix_task.ex`
- `lib/jido_code/tools/handlers/elixir/process_state.ex`
- `lib/jido_code/tools/handlers/elixir/supervisor.ex`
- `lib/jido_code/tools/handlers/elixir/reload.ex`
- `lib/jido_code/tools/handlers/elixir/ets.ex`
- `lib/jido_code/tools/handlers/elixir/docs.ex`
- `lib/jido_code/tools/handlers/elixir/exunit.ex`
- `test/jido_code/tools/handlers/elixir_test.exs`
- `test/jido_code/integration/tools_phase5_test.exs`

**Modified Files:**
- `lib/jido_code/tools/definitions.ex` - Register new tools
