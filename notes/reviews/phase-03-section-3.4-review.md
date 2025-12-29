# Review: Phase 3 Section 3.4 - Go To Definition Tool

**Date:** 2025-12-29
**Reviewers:** Factual, QA, Architecture, Security, Consistency, Elixir-specific
**Document:** `notes/planning/tooling/phase-03-tools.md` (lines 276-329)
**Status:** Planning document (not yet implemented)

---

## Executive Summary

Section 3.4 describes implementing the `go_to_definition` LSP tool. The review identified **significant inconsistencies** with the already-implemented section 3.3 (`get_hover_info`). The primary issue is that section 3.4 still describes the **Lua sandbox bridge pattern**, but section 3.3 established that LSP tools use the **Handler pattern**.

| Category | Count |
|----------|-------|
| Blockers | 5 |
| Concerns | 8 |
| Suggestions | 10 |
| Good Practices | 6 |

---

## Blockers (Must Fix Before Implementation)

### 1. Architectural Mismatch: Lua Bridge vs Handler Pattern

**All reviewers flagged this issue.**

Section 3.4.2 describes implementing `lua_lsp_definition/3` in `bridge.ex`, but:
- Section 3.3.2 explicitly documents: "LSP tools use the Handler pattern (direct Elixir execution)"
- The tools table (line 48) correctly shows `go_to_definition | Handler pattern`
- The note at line 51 states LSP tools use Handler pattern

**Fix Required:** Replace section 3.4.2 (Bridge Function Implementation) with Handler Implementation tasks matching 3.3.2 structure.

### 2. Wrong File Location Specified

**Location:** Line 284 - Task 3.4.1.1

The plan says: "Create `lib/jido_code/tools/definitions/go_to_definition.ex`"

But the established pattern uses combined modules:
- `lib/jido_code/tools/definitions/lsp.ex` (all LSP tool definitions)
- `lib/jido_code/tools/handlers/lsp.ex` (all LSP handlers)

**Fix Required:** Change to "Add `go_to_definition/0` to existing `lib/jido_code/tools/definitions/lsp.ex`"

### 3. Manager API Section is N/A for Handler Pattern

**Location:** Section 3.4.3 (lines 319-322)

Handler pattern tools execute via `Tools.Executor`, not `Tools.Manager`. Section 3.3.3 was correctly marked as N/A.

**Fix Required:** Mark section 3.4.3 as N/A with explanation matching 3.3.3.

### 4. Missing Output Path Validation (Security)

**Security reviewer identified critical gap.**

Unlike `get_hover_info` which returns information at a position, `go_to_definition` returns a **path** pointing to where a symbol is defined. This path could be:
- Inside the project (safe)
- In `deps/` or `_build/` (policy decision needed)
- In Elixir/Erlang stdlib (reveals system paths)
- Outside project entirely (information disclosure)

**Fix Required:** Add output path validation task:
```
- [ ] 3.4.2.X Validate OUTPUT path from LSP response:
  - Within project_root: Return relative path
  - In deps/ or _build/: Return relative path (allow read-only)
  - In stdlib/OTP: Return sanitized indicator (e.g., "elixir:File")
  - Outside boundaries: Return error without revealing path
```

### 5. Missing Handler Module Task

Section 3.3.1.4 includes creating the handler module, but section 3.4.1 is missing this.

**Fix Required:** Add task 3.4.1.4 for adding `GoToDefinition` handler module to `lib/jido_code/tools/handlers/lsp.ex`.

---

## Concerns (Should Address or Explain)

### 1. Inadequate Test Coverage Plan

**QA reviewer comparison:**

| Test Category | get_hover_info (3.3.4) | go_to_definition (3.4.4) |
|--------------|------------------------|--------------------------|
| Schema validation | 1 | 0 |
| LLM format conversion | 2 | 0 |
| Executor integration | 1 | 0 |
| Parameter validation | 2 | 0 |
| Security tests | 2 | 0 |
| Session-aware context | 1 | 0 |
| Functional tests | 3 | 3 |
| **Total** | **13** | **3** |

**Recommendation:** Expand section 3.4.4 to include:
- Test tool definition has correct schema
- Test generates valid LLM function format
- Test executor validates required arguments
- Test validates line number (must be >= 1)
- Test validates character number (must be >= 1)
- Test blocks path traversal (input)
- Test blocks absolute paths outside project (input)
- Test sanitizes external paths (output)
- Test session-aware context
- Test results convert to LLM messages
- Test handles non-Elixir files
- Test handles non-existent file

### 2. No Multiple Definitions Handling

LSP `textDocument/definition` can return:
- `null` (no definition found)
- Single `Location`
- Array of `Location[]` (multiple definitions - common for protocol implementations)
- `LocationLink[]` (with origin selection range)

The plan only handles single location or not found.

**Recommendation:** Add test case and handling for multiple definitions.

### 3. Return Format Inconsistency

Plan shows: `{[%{path: path, line: line, character: char}], state}` (Lua bridge format)

Handler pattern should return: `{:ok, map()} | {:error, String.t()}`

Also note field name inconsistency: `char` vs `character`.

### 4. Missing Security Test Cases

Section 3.4.4 lacks security tests that exist in 3.3.4:
- Path traversal (input)
- Absolute paths outside project (input)
- Output path sanitization (unique to go_to_definition)

### 5. Phase 3 Success Criteria Outdated

Lines 463-464 still reference Lua bridge:
> "get_hover_info: Type and docs via `jido.lsp_hover` bridge"

Should reference Handler pattern execution.

### 6. Integration Tests Reference "Sandbox"

Section 3.7.3 title mentions "through sandbox" but LSP tools use Handler pattern.

### 7. Policy for Dependency Definitions Undefined

When definition is in `deps/jason/lib/jason.ex`:
- Should this be returned?
- As relative or absolute path?
- Could encourage LLM to modify deps (bad)

### 8. Error Message Information Disclosure

Error handling should not reveal external paths:

Bad: `"Definition found at /home/user/.asdf/installs/elixir/1.16.0/lib/file.ex but outside project"`

Good: `"Definition is in external library (not accessible within project boundary)"`

---

## Suggestions (Nice to Have)

### 1. Add Architectural Decision Note

Section 3.4.2 should include the same architectural decision block as 3.3.2.

### 2. Extract Shared Position Parameter Helpers

Both handlers need identical extraction for path/line/character. Move to parent `LSPHandlers` module:
```elixir
defp extract_path/1, extract_line/1, extract_character/1
```

### 3. Add Telemetry Task

Follow `GetHoverInfo` pattern:
```
- [ ] 3.4.2.X Emit telemetry for :go_to_definition operation
```

### 4. Shared Parameter Definition

Create helper for position parameters used by all LSP tools:
```elixir
defp position_parameters do
  [
    %{name: "path", type: :string, required: true, ...},
    %{name: "line", type: :integer, required: true, ...},
    %{name: "character", type: :integer, required: true, ...}
  ]
end
```

### 5. Consider Preview Snippet Field

Include a preview of the definition line:
```elixir
%{
  "path" => "lib/user.ex",
  "line" => 15,
  "character" => 7,
  "preview" => "def create_user(attrs \\\\ %{}) do"
}
```

### 6. Add Position Indexing Note

Document 1-indexed to 0-indexed conversion (deferred to Phase 3.6).

### 7. Cross-Reference to Section 3.3

Add note: "Implementation follows the same Handler pattern established in 3.3.2."

### 8. Add Error Type to format_error/2

```elixir
def format_error(:definition_not_found, path),
  do: "No definition found at this position in: #{path}"
```

### 9. Add Symlink Handling for Output Paths

Validate symlinks in LSP-returned paths before boundary check.

### 10. Rate Limiting Telemetry

Track definition lookups for potential rate limiting if needed.

---

## Good Practices Noticed

### 1. Consistent Parameter Schema

Section 3.4.1.2 correctly uses same parameter structure as 3.3.1.2 (path, line, character).

### 2. Correct 1-Indexed Position Convention

Both sections specify 1-indexed line and character, matching editor conventions.

### 3. Tools Table Correctly Updated

Line 48 shows `go_to_definition | Handler pattern` - only detailed tasks need updating.

### 4. Phase 3.6 LSP Client Deferral

Planning correctly defers actual LSP client integration to Phase 3.6.

### 5. Input Path Validation Planned

Task 3.4.2.2 includes "Validate file path within boundary" using established `HandlerHelpers.validate_path/2`.

### 6. Critical Files Section Updated

Lines 481-486 correctly list combined LSP files, showing forward planning.

---

## Recommended Section 3.4 Rewrite

```markdown
## 3.4 Go To Definition Tool

Implement the go_to_definition tool for navigating to symbol definitions.

**Note:** Uses Handler pattern (not Lua sandbox) per architectural decision in 3.3.2.

### 3.4.1 Tool Definition (add to existing lsp.ex)

- [ ] 3.4.1.1 Add `go_to_definition/0` to `lib/jido_code/tools/definitions/lsp.ex`
- [ ] 3.4.1.2 Define schema (path, line, character - same as get_hover_info)
- [ ] 3.4.1.3 Update `LSP.all/0` to include go_to_definition()
- [ ] 3.4.1.4 Create handler `GoToDefinition` in `lib/jido_code/tools/handlers/lsp.ex`

### 3.4.2 Handler Implementation (uses Handler pattern)

**Architectural Decision:** Same as 3.3.2 - Handler pattern for LSP tools.

- [ ] 3.4.2.1 Handler module `JidoCode.Tools.Handlers.LSP.GoToDefinition`
- [ ] 3.4.2.2 Validate INPUT path using `HandlerHelpers.validate_path/2`
- [ ] 3.4.2.3 Position handling (1-indexed; 0-indexed conversion in Phase 3.6)
- [ ] 3.4.2.4 LSP server integration placeholder (awaiting Phase 3.6)
- [ ] 3.4.2.5 Validate OUTPUT path from LSP response (SECURITY):
  - Within project: Return relative path
  - In deps/_build: Return relative path
  - In stdlib: Return sanitized indicator
  - Outside boundaries: Error without revealing path
- [ ] 3.4.2.6 Handle multiple definitions (return array)
- [ ] 3.4.2.7 Returns `{:ok, map}` or `{:error, string}`
- [ ] 3.4.2.8 Emit telemetry for :go_to_definition

### 3.4.3 Manager API (N/A - Handler pattern)

Handler pattern tools execute via `Tools.Executor`, not `Tools.Manager`.

### 3.4.4 Unit Tests (add to lsp_test.exs)

Schema & Format:
- [ ] Test tool definition has correct schema
- [ ] Test generates valid LLM function format

Executor Integration:
- [ ] Test go_to_definition works via executor for Elixir files
- [ ] Test go_to_definition handles non-Elixir files
- [ ] Test go_to_definition returns error for non-existent file
- [ ] Test executor validates required arguments

Parameter Validation:
- [ ] Test validates line number (must be >= 1)
- [ ] Test validates character number (must be >= 1)

Functional:
- [ ] Test finds function definition
- [ ] Test finds module definition
- [ ] Test handles no definition found
- [ ] Test handles multiple definitions

Security:
- [ ] Test blocks path traversal (input)
- [ ] Test blocks absolute paths outside project (input)
- [ ] Test sanitizes external paths (output)
- [ ] Test error messages don't reveal external paths

Session & LLM:
- [ ] Test session-aware context
- [ ] Test results convert to LLM messages

Note: Full LSP integration tests deferred to Phase 3.6.
```

---

## Summary

Section 3.4 needs significant updates before implementation to align with the Handler pattern established in section 3.3. The primary actions are:

1. **Replace** Lua bridge approach with Handler pattern
2. **Update** file locations to use combined lsp.ex modules
3. **Add** output path validation for security
4. **Expand** test coverage from 3 to ~15 tests
5. **Mark** Manager API section as N/A

These changes should be made to the planning document before implementation begins.
