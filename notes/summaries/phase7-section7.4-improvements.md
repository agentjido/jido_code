# Phase 7 Section 7.4: StoreManager Improvements

**Date:** 2026-01-02
**Branch:** `feature/phase7-section7.4-improvements`

## Overview

This document summarizes the improvements made to the StoreManager based on the comprehensive code review findings from the Section 7.4 implementation.

## Improvements Implemented

### 1. High Priority Fixes

#### 1.1 Fixed Health Spec Type Mismatch
- **Issue:** The `@spec` for `health/2` specified `{:error, :unhealthy}` but implementation returned `{:error, {:unhealthy, status}}`
- **Fix:** Updated spec to `{:error, :not_found | {:unhealthy, term()} | term()}`
- **Location:** `lib/jido_code/memory/long_term/store_manager.ex:200-201`

#### 1.2 Added LRU Eviction with max_open_stores
- **Issue:** Unbounded store growth could lead to memory issues
- **Fix:** Added `max_open_stores` configuration (default: 100) with automatic LRU eviction
- **Implementation:**
  - `maybe_evict_lru/1` - Checks if at capacity before opening new store
  - `evict_lru_store/1` - Closes the least recently accessed store
  - `find_lru_session/1` - Finds session with oldest `last_accessed` timestamp

#### 1.3 Added Idle Cleanup Timer
- **Issue:** Abandoned sessions could leave stores open indefinitely
- **Fix:** Added periodic cleanup of idle stores
- **Configuration:**
  - `idle_timeout_ms` - Time before store is considered idle (default: 30 minutes)
  - `cleanup_interval_ms` - Interval for cleanup checks (default: 5 minutes)
- **Implementation:**
  - `schedule_cleanup/1` - Schedules next cleanup via `Process.send_after`
  - `cleanup_idle_stores/1` - Closes stores that exceed idle timeout
  - New `handle_info(:cleanup_idle_stores, state)` callback

### 2. Medium Priority Fixes

#### 2.1 Extracted update_last_accessed Helper
- **Issue:** Duplicated code for updating `last_accessed` timestamp
- **Fix:** Created `touch_last_accessed/3` helper function
- **Before:** 6 lines duplicated in `get_or_create` and `get` handlers
- **After:** Single helper function reused in both places

#### 2.2 Extracted close_all_stores Helper
- **Issue:** Duplicated close iteration logic
- **Fix:** Created two helper functions:
  - `close_all_stores/1` - Simple sequential close
  - `close_all_stores_with_timeout/1` - Parallel close with timeouts

#### 2.3 Fixed if-not Anti-Pattern
- **Issue:** Used `if not condition` instead of idiomatic `unless`
- **Fix:** Changed to `unless` in `get_or_create` handler and `open_store` function

#### 2.4 Added Timeout Handling in terminate
- **Issue:** `terminate/2` could block indefinitely if TripleStore.close hangs
- **Fix:** Uses parallel Task closing with 5-second timeout per store
- **Implementation:**
  - `close_all_stores_with_timeout/1` spawns tasks for each store
  - Uses `Task.yield/2` with timeout, falls back to `Task.shutdown/1`
  - Logs warning for stores that fail to close cleanly

### 3. Low Priority Fixes

#### 3.1 Inlined expand_path Wrapper
- **Issue:** Single-line wrapper function adding no value
- **Fix:** Replaced calls to `expand_path/1` with direct `Path.expand/1`

#### 3.2 Added Logger Inspection Limits
- **Issue:** Unbounded `inspect` output in log messages
- **Fix:** Added `limit: 50` to all `inspect` calls in Logger statements

## Configuration Options

The StoreManager now accepts the following configuration:

```elixir
StoreManager.start_link(
  base_path: "/tmp/stores",
  name: :my_store_manager,
  config: %{
    max_open_stores: 100,        # LRU eviction threshold
    idle_timeout_ms: 1_800_000,  # 30 minutes
    cleanup_interval_ms: 300_000 # 5 minutes
  }
)
```

## Test Improvements

### New Test Helpers
- `unique_session_id/1` - Generates random session IDs
- `extract_rdf_value/1` - Extracts values from RDF literals
- `@sparql_prefixes` - Module attribute for common SPARQL prefixes

### New Test Suites

| Suite | Tests | Description |
|-------|-------|-------------|
| LRU eviction | 2 | Tests eviction at capacity and under capacity |
| Idle cleanup | 2 | Tests cleanup of idle and active stores |
| Configuration | 2 | Tests config merging and custom intervals |

### Test Results

```
43 tests, 0 failures (StoreManager tests)
288 tests, 0 failures (All Phase 7 tests)
```

## Files Changed

| File | Change |
|------|--------|
| `lib/jido_code/memory/long_term/store_manager.ex` | Major refactor |
| `test/jido_code/memory/long_term/store_manager_test.exs` | Added 6 new tests, helpers |
| `notes/summaries/phase7-section7.4-improvements.md` | Created |

## Code Quality Improvements

| Metric | Before | After |
|--------|--------|-------|
| Compile warnings | 4 | 0 |
| Duplicated code blocks | 3 | 0 |
| Test count | 37 | 43 |
| Configuration options | 1 | 4 |

## Architecture Changes

```
StoreManager (GenServer)
     │
     ├── stores: %{session_id => store_entry}
     │
     ├── config: %{
     │     max_open_stores: 100,
     │     idle_timeout_ms: 30min,
     │     cleanup_interval_ms: 5min
     │   }
     │
     ├── Cleanup Timer ────► :cleanup_idle_stores message
     │                        ↓
     │                   cleanup_idle_stores/1
     │                        ↓
     │                   Close idle stores
     │
     └── LRU Eviction
           ↓
         maybe_evict_lru/1 on get_or_create
           ↓
         evict_lru_store/1 if at capacity
```

## Summary

All high-priority, medium-priority, and most low-priority recommendations from the code review have been implemented. The StoreManager now:

1. **Prevents unbounded growth** via LRU eviction
2. **Cleans up idle stores** automatically
3. **Has cleaner code** with extracted helpers
4. **Uses idiomatic Elixir** patterns
5. **Handles termination gracefully** with timeouts
6. **Is well-tested** with 43 tests covering new features
