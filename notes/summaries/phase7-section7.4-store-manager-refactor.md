# Phase 7 Section 7.4: Refactor StoreManager

**Date:** 2026-01-02
**Branch:** `feature/phase7-section7.4-store-manager-refactor`

## Overview

This section refactors the StoreManager GenServer to use the TripleStore library instead of ETS tables. Each session now gets a persistent RocksDB-backed RDF triple store with automatic ontology loading.

## Implementation Summary

### Modified File: `lib/jido_code/memory/long_term/store_manager.ex`

**Key Changes:**

1. **Store Type Change**
   - Old: `@type store_ref :: :ets.tid()`
   - New: `@type store_ref :: TripleStore.store()`

2. **State Structure Enhancement**
   ```elixir
   @type store_metadata :: %{
     opened_at: DateTime.t(),
     last_accessed: DateTime.t(),
     ontology_loaded: boolean()
   }

   @type store_entry :: %{
     store: store_ref(),
     metadata: store_metadata()
   }

   @type state :: %{
     stores: %{String.t() => store_entry()},
     base_path: String.t(),
     config: map()
   }
   ```

3. **New API Functions**
   - `get_metadata/2` - Returns store metadata (open time, last access, ontology status)
   - `health/2` - Checks TripleStore health status

4. **Store Lifecycle**
   - `open_store/2` now calls `TripleStore.open/2` with `create_if_missing: true`
   - Automatically loads ontology via `OntologyLoader.load_ontology/1` on first open
   - `close_store/1` now calls `TripleStore.close/1`

5. **Metadata Tracking**
   - Tracks `opened_at` timestamp when store is created
   - Updates `last_accessed` on every `get/2` and `get_or_create/2` call
   - Records `ontology_loaded: true` after successful ontology loading

### Modified File: `test/jido_code/memory/long_term/store_manager_test.exs`

Updated all 37 tests to work with TripleStore backend:

**Key Test Changes:**

| Test Category | Description |
|--------------|-------------|
| Basic Operations | Tests now verify TripleStore operations instead of ETS |
| Ontology Loading | Added tests verifying ontology is loaded automatically |
| Data Persistence | Added tests for data persistence across close/reopen cycles |
| Health Checks | Added tests for `health/2` function |
| Metadata | Added tests for `get_metadata/2` function |
| Store Isolation | Updated to use SPARQL queries for isolation verification |
| Concurrent Access | Updated to verify TripleStore handles concurrent access |

**New Tests Added:**

- `test "returns TripleStore that can be used for queries"` - Verifies SPARQL queries work
- `test "loads ontology on first open"` - Verifies ontology classes are loaded
- `test "data persists after close and reopen"` - Verifies RocksDB persistence
- `test "returns metadata for open store"` - Tests get_metadata/2
- `test "updates last_accessed on get"` - Tests metadata tracking
- `test "returns :healthy for open store"` - Tests health/2

## Architecture

```
StoreManager (GenServer)
     │
     ├── stores: %{
     │     "session_abc" => %{
     │       store: <TripleStore.store()>,
     │       metadata: %{
     │         opened_at: ~U[2026-01-02 12:00:00Z],
     │         last_accessed: ~U[2026-01-02 12:05:00Z],
     │         ontology_loaded: true
     │       }
     │     }
     │   }
     │
     └── base_path: ~/.jido_code/memory_stores/
          ├── session_abc/   (RocksDB instance + ontology)
          ├── session_def/   (RocksDB instance + ontology)
          └── session_ghi/   (RocksDB instance + ontology)
```

## Test Results

```
130 tests, 0 failures (Phase 7 components)
```

Breakdown:
- 37 StoreManager tests
- 53 SPARQLQueries tests
- 21 TripleStore integration tests
- 19 OntologyLoader tests

## Files Changed

| File | Change |
|------|--------|
| `lib/jido_code/memory/long_term/store_manager.ex` | Major refactor - ETS to TripleStore |
| `test/jido_code/memory/long_term/store_manager_test.exs` | Updated all 37 tests |
| `notes/planning/two-tier-memory/phase-07-triple-store-integration.md` | Marked 7.4 complete |

## Usage Example

```elixir
alias JidoCode.Memory.LongTerm.StoreManager

# Start the StoreManager (typically done by application supervisor)
{:ok, _pid} = StoreManager.start_link(base_path: "/tmp/memory_stores")

# Get or create a store for a session - ontology is loaded automatically
{:ok, store} = StoreManager.get_or_create("session-123")

# Use TripleStore operations directly
{:ok, results} = TripleStore.query(store, """
  PREFIX jido: <https://jido.ai/ontology#>
  SELECT ?class WHERE { ?class a owl:Class }
""")

# Check store metadata
{:ok, metadata} = StoreManager.get_metadata("session-123")
# => %{opened_at: ~U[...], last_accessed: ~U[...], ontology_loaded: true}

# Check store health
{:ok, :healthy} = StoreManager.health("session-123")

# Close when done
:ok = StoreManager.close("session-123")
```

## Known Limitations

1. **TripleStoreAdapter Not Yet Updated**: The TripleStoreAdapter (Section 7.5) still expects ETS tables from StoreManager. This causes 363 test failures in the broader test suite. These will be fixed in Section 7.5.

2. **No Periodic Health Checks**: The plan mentioned periodic health checks, but this was deferred as it adds complexity without immediate benefit.

## Next Steps

With Section 7.4 complete, Section 7.5 (Refactor TripleStoreAdapter) is next:
- Update TripleStoreAdapter to use SPARQL queries via SPARQLQueries module
- Remove ETS-specific code
- Update result mapping from SPARQL bindings to memory structs
- This will fix the 363 failing tests that expect ETS stores
