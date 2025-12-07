# Credo Fixes Feature

**Branch:** `feature/credo-fixes`
**Date:** 2025-12-07
**Status:** In Progress

## Overview

Systematically fix all credo issues in the codebase, categorized by priority.

## Implementation Plan

### Phase 1: P1 Issues (HIGH Priority - Quick Fixes)

#### 1.1 Predicate Function Names
- [ ] Rename `is_numeric_target?` → `numeric_target?` in commands.ex
- [ ] Rename `is_file?` → `file?` in manager.ex
- [ ] Rename `is_dir?` → `directory?` in manager.ex
- [ ] Update all call sites

#### 1.2 Large Numbers
- [ ] Fix `12345` → `12_345` in agent_api_test.exs (5 occurrences)

#### 1.3 MapJoin Optimization
- [ ] Fix web.ex:260 - convert_to_markdown
- [ ] Fix web.ex:291 - convert_to_markdown
- [ ] Fix manager.ex:660 - call_bridge_function
- [ ] Fix manager.ex:712 - lua_encode_arg
- [ ] Fix conversation_view_test.exs:1088, 1108

#### 1.4 Negated Conditions
- [ ] Fix executor.ex:238 - build_context

#### 1.5 Unless With Else
- [ ] Fix session_phase3_test.exs:324
- [ ] Fix session_phase3_test.exs:352

#### 1.6 Filter Filter
- [ ] Fix web.ex:404 - parse_duckduckgo_response

### Phase 2: P2 Issues (MEDIUM Priority)

#### 2.1 With Single Clause
- [ ] Fix file_system.ex:202 - ReadFile.execute
- [ ] Fix file_system.ex:378 - ListDirectory.execute
- [ ] Fix file_system.ex:483 - FileInfo.execute
- [ ] Fix file_system.ex:555 - CreateDirectory.execute
- [ ] Fix file_system.ex:603 - DeleteFile.execute

#### 2.2 Prefer Implicit Try
- [ ] Fix task.ex:181 - run_with_cleanup

#### 2.3 Alias Order (14 fixes)
- [ ] Fix lib/jido_code/application.ex
- [ ] Fix lib/jido_code/livebook/parser.ex
- [ ] Fix lib/jido_code/livebook/serializer.ex
- [ ] Fix lib/jido_code/tools.ex
- [ ] Fix lib/jido_code/tools/handlers/file_system.ex
- [ ] Fix lib/jido_code/tools/handlers/livebook.ex
- [ ] Fix lib/jido_code/tools/handlers/task.ex
- [ ] Fix test files (7)

### Phase 3: P3 Issues (LOW Priority - Defer)
- Nesting issues (13) - require significant refactoring
- Cyclomatic complexity (5) - need function decomposition
- AliasUsage in tests (15) - low value
- TODO tags (2) - documentation, not bugs

## Files to Modify

### Phase 1
- `lib/jido_code/commands.ex`
- `lib/jido_code/tools/manager.ex`
- `lib/jido_code/tools/executor.ex`
- `lib/jido_code/tools/handlers/web.ex`
- `test/jido_code/session/agent_api_test.exs`
- `test/jido_code/integration/session_phase3_test.exs`
- `test/jido_code/tui/widgets/conversation_view_test.exs`

### Phase 2
- `lib/jido_code/tools/handlers/file_system.ex`
- `lib/jido_code/tools/handlers/task.ex`
- Multiple files for alias ordering

## Success Criteria

1. `mix credo --strict` shows 0 P1 issues
2. `mix credo --strict` shows 0 P2 issues
3. All tests pass
4. P3 issues documented for future work
