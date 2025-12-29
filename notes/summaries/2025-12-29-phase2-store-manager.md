# Phase 2 Task 2.2.1 - StoreManager GenServer

**Date:** 2025-12-29
**Branch:** `feature/phase2-store-manager`
**Task:** 2.2.1 StoreManager GenServer and 2.2.2 Unit Tests

## Overview

Implemented the StoreManager GenServer for session-isolated store lifecycle management. Each session gets its own isolated store identified by session ID.

## Implementation Details

### Module Location
`lib/jido_code/memory/long_term/store_manager.ex`

### Architecture

```
StoreManager (GenServer)
     │
     ├── stores: %{session_id => store_ref}
     │
     └── base_path: ~/.jido_code/memory_stores/
          ├── session_abc123/
          ├── session_def456/
          └── session_ghi789/
```

### Store Backend

The current implementation uses ETS tables as the backing store. Each session gets its own ETS table for storing data. This design allows for easy upgrade to a persistent triple store (like RocksDB-backed) in the future.

### Features Implemented

#### State Management
- State struct with `stores`, `base_path`, and `config` fields
- Default configuration with `create_if_missing: true`
- Default base path: `~/.jido_code/memory_stores`

#### Client API
| Function | Description |
|----------|-------------|
| `start_link/1` | Start GenServer with optional base_path, name, config |
| `get_or_create/2` | Get existing or create new store for session |
| `get/2` | Get existing store only (no auto-create) |
| `close/2` | Close and remove a session's store |
| `close_all/1` | Close all open stores |
| `list_open/1` | List currently open session IDs |
| `open?/2` | Check if session has open store |
| `base_path/1` | Get configured base path |

#### GenServer Callbacks
- `init/1` - Initialize state, expand paths, create directories
- `handle_call` for all client operations
- `terminate/2` - Clean shutdown of all stores

#### Helper Functions
- `store_path/2` - Generate session-specific directory path
- `expand_path/1` - Expand ~ in paths
- `ensure_directory/1` - Create directory if missing
- `open_store/2` - Create ETS table for session
- `close_store/1` - Delete ETS table

## Test Coverage

**Test File:** `test/jido_code/memory/long_term/store_manager_test.exs`

**30 tests covering:**
- start_link with default and custom options
- get_or_create for new and existing sessions
- get for existing and non-existent sessions
- close and close_all operations
- list_open functionality
- open? predicate
- Store isolation between sessions
- Concurrent access handling
- terminate cleanup

## Test Results

```
StoreManager Tests: 30 tests, 0 failures
All Memory Tests: 268 tests, 0 failures
```

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/memory/long_term/store_manager.ex` | StoreManager GenServer |
| `test/jido_code/memory/long_term/store_manager_test.exs` | Comprehensive unit tests |

## Files Modified

| File | Changes |
|------|---------|
| `notes/planning/two-tier-memory/phase-02-long-term-store.md` | Marked 2.2.1 and 2.2.2 tasks complete (34 checkboxes) |

## Design Notes

### ETS as Backing Store
The implementation uses ETS tables instead of a real triple store because:
1. No external dependencies required
2. Fast in-memory operations for testing
3. Same interface can be used with real triple store later
4. Allows Phase 2 development to proceed without waiting for RDF store integration

### Session Isolation
- Each session gets a dedicated ETS table
- Table names include session ID for uniqueness
- Directory structure prepared for future persistent storage
- Concurrent access is safe due to GenServer serialization

### Future Upgrades
To switch to a real triple store:
1. Update `open_store/2` to use triple store library
2. Update `close_store/1` to properly close connections
3. Store references will change type but API remains same

## Next Steps

This completes Task 2.2.1 and 2.2.2. The StoreManager is now ready for:
- Task 2.3 - Triple Store Adapter (Elixir struct ↔ RDF triple mapping)
- Task 2.5 - Memory Supervisor (add StoreManager to supervision tree)
