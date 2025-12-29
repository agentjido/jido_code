# Phase 3 Sections 3.4-3.5 Review Fixes

**Status**: Complete
**Branch**: `feature/3.4-review-fixes`
**Review Reference**: `notes/reviews/phase-03-section-3.4-review.md`

## Summary

Applied all blockers, concerns, and suggestions from the parallel review of Phase 3 sections 3.4 (Go To Definition) and 3.5 (Find References). Both sections were updated to use the Handler pattern established in section 3.3.

## Blockers Fixed

### 1. Architectural Mismatch: Lua Bridge → Handler Pattern

**Before:** Sections described Lua bridge functions (`lua_lsp_definition/3`, `lua_lsp_references/3`)

**After:** Both sections now specify Handler pattern with:
- Handler modules in `lib/jido_code/tools/handlers/lsp.ex`
- Execution via `Tools.Executor` → Handler chain
- Architectural decision notes referencing 3.3.2

### 2. File Location: Separate Files → Combined lsp.ex

**Before:** Tasks specified creating separate files (`go_to_definition.ex`, `find_references.ex`)

**After:** Tasks specify adding to existing combined modules:
- `lib/jido_code/tools/definitions/lsp.ex` - Tool definitions
- `lib/jido_code/tools/handlers/lsp.ex` - Handler modules

### 3. Manager API Sections Marked N/A

**Before:** Sections 3.4.3 and 3.5.3 described Manager API with Lua calls

**After:** Both marked as N/A with explanation:
> Handler pattern tools execute via `Tools.Executor` directly, not through `Tools.Manager`.

### 4. Output Path Validation (Security)

**Added new security requirements:**

For `go_to_definition` (3.4.2.5):
- Within project_root: Return relative path
- In deps/ or _build/: Return relative path (allow read-only access)
- In stdlib/OTP: Return sanitized indicator (e.g., `"elixir:File"`)
- Outside all boundaries: Return error without revealing actual path

For `find_references` (3.5.2.6):
- Filter results to only include paths within project boundary
- Include deps/ and _build/ as relative paths
- Exclude and do not reveal stdlib/OTP paths

### 5. Handler Module Tasks Added

Added tasks 3.4.1.4 and 3.5.1.4 for creating handler modules.

## Concerns Fixed

### 1. Expanded Test Coverage

**Before:** 3 tests each for go_to_definition and find_references

**After:** ~18 tests each organized by category:
- Schema & Format (2 tests)
- Executor Integration (4 tests)
- Parameter Validation (2-3 tests)
- Functional (4 tests)
- Security (4 tests) - NEW
- Session & LLM (2 tests)

### 2. Updated Success Criteria

Reorganized to distinguish patterns:
- Git tools: Lua Sandbox Pattern
- LSP tools: Handler Pattern

Added new criteria:
- Security: Output path validation for LSP tools
- Clarified which tools are DONE vs pending

### 3. Updated Integration Tests Section

- Renamed 3.7.1 to "Tool Execution Integration"
- Added tests for both execution patterns
- Added security test for output path validation
- Added note clarifying LSP tools use Handler pattern

### 4. Multiple Definitions Handling

Added task 3.4.2.6: "Handle multiple definitions (LSP can return array of locations)"

## Suggestions Implemented

### 1. Architectural Notes and Cross-References

Both sections now include:
```markdown
**Note:** Uses Handler pattern (not Lua sandbox) per architectural decision in 3.3.2.
See `notes/summaries/tooling-3.3.2-lsp-handler-architecture.md` for rationale.
```

### 2. Telemetry Tasks

Added tasks for telemetry emission:
- 3.4.2.8: Emit telemetry for `:go_to_definition`
- 3.5.2.8: Emit telemetry for `:find_references`

### 3. Error Formatting Tasks

Added tasks for format_error clauses:
- 3.4.2.9: `:definition_not_found`
- 3.5.2.9: `:no_references_found`

### 4. LSP Infrastructure Section Updated

Updated section 3.6 header and descriptions to reference Handler modules instead of Bridge functions.

### 5. Critical Files Section Reorganized

Separated by pattern:
- Git Tools (Lua Sandbox Pattern)
- LSP Tools (Handler Pattern)
- LSP Infrastructure (Phase 3.6)

Marked already-created files with ✓.

## Files Modified

| File | Changes |
|------|---------|
| `notes/planning/tooling/phase-03-tools.md` | Major updates to sections 3.4, 3.5, 3.6, 3.7, Success Criteria, Critical Files |

## Test Verification

No code changes were made - only planning document updates. The existing tests for `get_hover_info` (13 tests) continue to pass and serve as the template for the updated test plans in 3.4.4 and 3.5.4.

## Next Steps

When implementing sections 3.4 and 3.5:
1. Follow the Handler pattern established in 3.3
2. Add tool definitions to existing `lsp.ex`
3. Add handler modules to existing `handlers/lsp.ex`
4. Add tests to existing `lsp_test.exs`
5. Implement output path validation for security
