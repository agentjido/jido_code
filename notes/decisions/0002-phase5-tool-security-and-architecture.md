# ADR-0002: Phase 5 Tool Security and Architecture Revision

## Status

Accepted

## Date

2026-01-01

## Context

Phase 5 planning originally included 8 Elixir-specific tools for BEAM runtime introspection,
all routed through the Lua sandbox for "defense-in-depth" security per ADR-0001. A comprehensive
code review (see `notes/reviews/phase-05-planning-review.md`) identified critical security issues:

### Security Review Findings

1. **iex_eval (Code.eval_string)**: Allows arbitrary Elixir code execution with full BEAM access.
   The user-provided code can:
   - Execute system commands via `:os.cmd/1` or `System.cmd/2`
   - Access file system via `File.*` modules
   - Read environment secrets via `System.get_env/1`
   - Spawn processes, open network connections
   - Define modules that persist globally and could override security modules

2. **reload_module**: Enables hot code loading which, combined with file write capabilities,
   allows permanent backdoor installation by replacing modules at runtime.

3. **Lua Sandbox Provides False Security**: The Lua sandbox (ADR-0001) removes `os.execute` and
   `io.popen` from the Lua environment, but Phase 5 tools execute their dangerous operations in
   Elixir, not Lua. The Bridge functions have full BEAM access. For example:
   ```
   Lua VM → Bridge.lua_iex_eval/3 → Code.eval_string(user_code) ← UNRESTRICTED
   ```
   The Lua layer adds complexity without providing security for these tools.

4. **Architectural Inconsistency**: Phases 3 and 4 established that many tools use the Handler
   pattern (direct Elixir execution via `Tools.Executor`) when:
   - The tool doesn't benefit from Lua's restricted environment
   - Better integration with Elixir infrastructure is needed (LSP, web, agents)

   Phase 5 planned to route all tools through Lua despite most being pure introspection
   operations that don't benefit from the sandbox.

### Tools Categorized by Risk

| Tool | Risk Level | Issue |
|------|------------|-------|
| iex_eval | Critical | Unrestricted code execution |
| reload_module | Critical | Code injection vector |
| get_process_state | Medium | Sensitive data exposure (addressable) |
| ets_inspect | Medium | Data exposure (addressable) |
| mix_task | Medium | Command execution (addressable via blocklist) |
| run_exunit | Medium | Command execution (addressable via blocklist) |
| inspect_supervisor | Low | Read-only introspection |
| fetch_elixir_docs | Low | Read-only, safe |

## Decision

### 1. Remove High-Risk Tools

The following tools are removed from Phase 5 scope:

- **iex_eval**: Cannot be safely implemented without a fundamentally different security model
  (e.g., sandboxed BEAM node, capability-based restrictions). The complexity of building a
  secure Elixir code evaluator outweighs the benefit.

- **reload_module**: Hot code loading combined with other tool capabilities creates an
  unacceptable attack vector. Module reloading should be done via explicit user action
  (e.g., `mix compile` in terminal), not via LLM tool.

### 2. Use Handler Pattern for Remaining Tools

All remaining Phase 5 tools will use the Handler pattern (direct Elixir execution via
`Tools.Executor`) instead of the Lua sandbox bridge. This provides:

- **Simpler architecture**: No Lua VM overhead for pure Elixir operations
- **Better integration**: Direct access to Elixir/OTP APIs
- **Consistent patterns**: Matches Phase 3 (LSP) and Phase 4 (web, agent) tools
- **Honest security**: Security is enforced in the Handler, not falsely attributed to Lua

### 3. Revised Tool Set

Phase 5 will implement 6 tools using the Handler pattern:

| Tool | Handler Module | Security Controls |
|------|----------------|-------------------|
| mix_task | `Handlers.Elixir.MixTask` | Task allowlist/blocklist, timeout |
| run_exunit | `Handlers.Elixir.RunExunit` | Path validation, timeout |
| get_process_state | `Handlers.Elixir.ProcessState` | Process allowlist, output sanitization |
| inspect_supervisor | `Handlers.Elixir.SupervisorTree` | Depth limit, scope restriction |
| ets_inspect | `Handlers.Elixir.EtsInspect` | Table allowlist, access control |
| fetch_elixir_docs | `Handlers.Elixir.FetchDocs` | Module validation (existing atoms only) |

### 4. Handler Security Model

Each Handler implements its own security controls:

```elixir
defmodule JidoCode.Tools.Handlers.Elixir.MixTask do
  @allowed_tasks ~w(compile test format deps.get deps.compile deps.tree help credo dialyzer docs)
  @blocked_tasks ~w(release archive.install escript.build local.hex hex.publish do)

  def execute(%{"task" => task} = params, context) do
    cond do
      task in @blocked_tasks -> {:error, "blocked task: #{task}"}
      task not in @allowed_tasks -> {:error, "task not in allowlist: #{task}"}
      true -> run_mix_task(task, params, context)
    end
  end
end
```

## Consequences

### Positive

- **Eliminates critical security vulnerabilities**: No arbitrary code execution or code injection
- **Simpler architecture**: Removes unnecessary Lua layer for Phase 5 tools
- **Consistent with existing patterns**: Matches Phase 3/4 Handler architecture
- **Honest security model**: Security controls are explicit in Handler code, not hidden behind
  a Lua layer that doesn't actually protect these operations
- **Easier to audit**: Security logic is in Elixir, testable with ExUnit

### Negative

- **Reduced functionality**: Users cannot evaluate arbitrary Elixir code via LLM tool
- **No hot reload via LLM**: Module reloading requires manual user action
- **Some use cases unsupported**: REPL-like interactions with session bindings not available

### Neutral

- **Phase 5 scope reduced**: From 8 tools to 6 tools
- **Planning document requires update**: Sections 5.1 (iex_eval) and 5.5 (reload_module) removed
- **No Lua bridge functions for Phase 5**: All handlers execute directly via Executor

## Alternatives Considered

### Alternative 1: Sandboxed BEAM Node for iex_eval

Run code evaluation in a separate BEAM node with:
- No network access
- Restricted file system (read-only, project only)
- Resource quotas (memory, CPU time)
- Process limits

**Pros:**
- Enables code evaluation feature
- True isolation via OS-level separation

**Cons:**
- Significant implementation complexity
- VM startup latency for each evaluation
- Complex state synchronization for bindings
- Still requires careful capability design

**Why not chosen:** Complexity outweighs benefit for initial release. Can be reconsidered
in future phase if there's strong user demand.

### Alternative 2: AST-Based Code Restriction for iex_eval

Parse code to AST, analyze for dangerous patterns, reject unsafe code.

**Pros:**
- Could enable safe subset of Elixir evaluation
- No external process needed

**Cons:**
- Extremely difficult to make comprehensive (macros, dynamic dispatch, code loading)
- Easy to bypass with creative code patterns
- Maintenance burden as Elixir evolves
- False sense of security

**Why not chosen:** Cannot be made reliably secure. Elixir's metaprogramming makes
static analysis insufficient.

### Alternative 3: Keep Lua Sandbox for All Phase 5 Tools

Continue with original architecture despite review findings.

**Pros:**
- Consistent with Phase 1/2 architecture
- No planning document changes needed

**Cons:**
- False security claims for iex_eval and reload_module
- Unnecessary complexity for pure introspection tools
- Inconsistent with Phase 3/4 patterns

**Why not chosen:** Security review demonstrated the Lua sandbox provides no protection
for Phase 5 tools. Maintaining the facade of security is worse than being explicit
about the actual security model.

## References

- [ADR-0001: Tool Security Architecture](./0001-tool-security-architecture.md)
- [Phase 5 Planning Review](../reviews/phase-05-planning-review.md)
- [Phase 3 Tools Planning](../planning/tooling/phase-03-tools.md) - Handler pattern for LSP tools
- [Phase 4 Tools Planning](../planning/tooling/phase-04-tools.md) - Handler pattern for web/agent tools
