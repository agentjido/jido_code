# Summary: Phase 5 Architecture Revision

## Overview

Major revision to Phase 5 planning based on comprehensive security review findings.
This revision removes high-risk tools and changes the architectural pattern from
Lua sandbox to Handler pattern.

## Changes Made

### 1. ADR Created

**File:** `notes/decisions/0002-phase5-tool-security-and-architecture.md`

Documents the decision to:
- Remove `iex_eval` and `reload_module` tools
- Use Handler pattern instead of Lua sandbox for all Phase 5 tools
- Provides rationale, alternatives considered, and consequences

### 2. Tools Removed

| Tool | Risk Level | Reason |
|------|------------|--------|
| `iex_eval` | Critical | `Code.eval_string` enables unrestricted code execution. Cannot be safely sandboxed without fundamentally different security model (e.g., separate BEAM node). |
| `reload_module` | Critical | Hot code loading combined with file write capabilities creates code injection vector. Module reloading should be explicit user action, not LLM tool. |

### 3. Architecture Changed

**Before (Lua Sandbox):**
```
LLM → Executor → Manager → Lua VM → Bridge → Elixir runtime
```

**After (Handler Pattern):**
```
LLM → Executor → Handler.execute() → Elixir runtime
```

**Rationale:**
- Lua sandbox provides no actual protection for Phase 5 tools
- Dangerous operations (`Code.eval_string`, `:sys.get_state`) execute in Elixir, not Lua
- Handler pattern is simpler, matches Phase 3/4 patterns, and provides honest security model
- Security controls are explicit in Handler code, testable with ExUnit

### 4. Revised Tool Set

Phase 5 now implements 6 tools (down from 8):

| Tool | Handler Module | Security Controls |
|------|----------------|-------------------|
| mix_task | `Handlers.Elixir.MixTask` | Task allowlist/blocklist, env restriction, timeout |
| run_exunit | `Handlers.Elixir.RunExunit` | Path validation, test/ restriction, timeout |
| get_process_state | `Handlers.Elixir.ProcessState` | Namespace restriction, blocked prefixes, output sanitization |
| inspect_supervisor | `Handlers.Elixir.SupervisorTree` | Namespace restriction, depth limit, children limit |
| ets_inspect | `Handlers.Elixir.EtsInspect` | Table ownership filter, access control, blocked tables |
| fetch_elixir_docs | `Handlers.Elixir.FetchDocs` | Safe atom handling (existing atoms only) |

### 5. Planning Document Updated

**File:** `notes/planning/tooling/phase-05-tools.md`

Major changes:
- Replaced Lua sandbox architecture diagram with Handler pattern
- Removed Sections 5.1 (iex_eval) and 5.5 (reload_module)
- Renumbered remaining sections (5.1-5.6 instead of 5.1-5.8)
- Added "Removed Tools" section documenting exclusions
- Updated tool table with Handler modules
- Added ADR reference
- Updated success criteria and critical files list

## Security Improvements

### Explicit Security Controls

Each Handler now documents specific security measures:

**mix_task:**
```elixir
@allowed_tasks ~w(compile test format deps.get deps.compile deps.tree deps.unlock help credo dialyzer docs hex.info)
@blocked_tasks ~w(release archive.install escript.build local.hex local.rebar hex.publish deps.update do ecto.drop ecto.reset phx.gen.secret)
```

**get_process_state:**
```elixir
@blocked_prefixes ~w(JidoCode.Tools JidoCode.Session :kernel :stdlib :init)
```

**ets_inspect:**
```elixir
@blocked_tables ~w(code ac_tab file_io_servers shell_records)a
```

### New Security Tests Planned

- Task allowlist enforcement tests
- Path traversal prevention tests
- System process blocking tests
- ETS table access control tests
- Sensitive data sanitization tests

## Impact

### Reduced Functionality

Users cannot:
- Evaluate arbitrary Elixir code via LLM tool
- Hot reload modules via LLM tool

These operations require explicit user action (terminal/IEx).

### Improved Security

- No arbitrary code execution vector
- No code injection vector
- Explicit, auditable security controls
- Consistent with Phase 3/4 patterns

### Simplified Architecture

- No Lua VM overhead for Phase 5 tools
- Direct Elixir execution via Executor → Handler
- Easier to test and debug

## Files Changed

| File | Change |
|------|--------|
| `notes/decisions/0002-phase5-tool-security-and-architecture.md` | Created (ADR) |
| `notes/planning/tooling/phase-05-tools.md` | Rewrote (architecture change) |
| `notes/reviews/phase-05-planning-review.md` | Created earlier (review findings) |

## Next Steps

Phase 5 implementation can now proceed with:
1. Create `lib/jido_code/tools/definitions/elixir.ex`
2. Create `lib/jido_code/tools/handlers/elixir.ex`
3. Implement each Handler with security controls
4. Write comprehensive tests
5. Integration testing

## References

- [ADR-0002](../decisions/0002-phase5-tool-security-and-architecture.md) - Full decision rationale
- [Phase 5 Review](../reviews/phase-05-planning-review.md) - Security review findings
- [Phase 3 Planning](../planning/tooling/phase-03-tools.md) - Handler pattern reference
