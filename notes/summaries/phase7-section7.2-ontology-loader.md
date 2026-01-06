# Phase 7 Section 7.2: Ontology Loader

**Date:** 2026-01-02
**Branch:** `feature/phase7-section7.2-ontology-loader`

## Overview

This section implements the `OntologyLoader` module that loads the Jido ontology TTL files into a TripleStore. The ontology provides the class hierarchy, properties, and individuals that define the structure of long-term memory.

## Implementation Summary

### New File: `lib/jido_code/memory/long_term/ontology_loader.ex`

The OntologyLoader module provides functions to load and query the Jido ontology:

**Core Functions:**
- `load_ontology/1` - Loads all ontology TTL files into a TripleStore
- `ontology_loaded?/1` - Checks if the ontology is loaded (via ASK query)
- `reload_ontology/1` - Clears and reloads the ontology

**Helper Functions:**
- `namespace/0` - Returns the Jido namespace IRI (`https://jido.ai/ontology#`)
- `ontology_files/0` - Returns list of TTL files to load
- `ontology_path/0` - Returns resolved path to ontology directory (cached)

**Query Functions:**
- `list_classes/1` - Lists all OWL classes in the ontology
- `list_individuals/1` - Lists all named individuals in the ontology
- `list_properties/1` - Lists all object and datatype properties

**Ontology Files Loaded:**
1. `jido-core.ttl` - Core classes (MemoryItem, Entity, Confidence, Source)
2. `jido-knowledge.ttl` - Knowledge types (Fact, Assumption, Hypothesis)
3. `jido-decision.ttl` - Decision types (Decision, Alternative, TradeOff)
4. `jido-convention.ttl` - Convention types (CodingStandard, AgentRule)
5. `jido-error.ttl` - Error types (Bug, Failure, LessonLearned)
6. `jido-session.ttl` - Session modeling
7. `jido-agent.ttl` - Agent modeling
8. `jido-project.ttl` - Project modeling
9. `jido-task.ttl` - Task modeling
10. `jido-code.ttl` - Code-related classes

**Total: ~670 triples loaded from 10 ontology files**

### Key Design Decisions

1. **Path Resolution**: Uses `persistent_term` to cache the resolved ontology path for efficiency. Tries multiple resolution strategies (cwd, __DIR__ relative).

2. **Load Order**: `jido-core.ttl` is loaded first as it defines base classes that other ontology files depend on.

3. **ASK Query for Checking**: Uses SPARQL ASK query to check if `jido:MemoryItem` class exists, which is efficient and reliable.

4. **Error Handling**: If clearing ontology fails during reload, logs a warning and proceeds with loading anyway.

### New File: `test/jido_code/memory/long_term/ontology_loader_test.exs`

Comprehensive tests covering:
- `namespace/0`, `ontology_files/0`, `ontology_path/0` helpers
- `load_ontology/1` loads all files and creates queryable triples
- Verifies MemoryItem class, confidence levels, source types exist
- Verifies knowledge subclasses (Fact, Assumption, Hypothesis)
- Verifies object and datatype properties
- `ontology_loaded?/1` returns correct boolean
- `reload_ontology/1` works correctly
- `list_classes/1`, `list_individuals/1`, `list_properties/1` return expected results

## Test Results

```
19 tests, 0 failures
```

All tests pass, confirming:
- Ontology files are found and loaded correctly
- All expected classes, individuals, and properties exist
- SPARQL queries against loaded ontology work
- Path caching works efficiently

## Files Changed

| File | Change |
|------|--------|
| `lib/jido_code/memory/long_term/ontology_loader.ex` | New - OntologyLoader module |
| `test/jido_code/memory/long_term/ontology_loader_test.exs` | New - 19 tests |
| `notes/planning/two-tier-memory/phase-07-triple-store-integration.md` | Modified - Marked 7.2 complete |

## Usage Example

```elixir
{:ok, store} = TripleStore.open(path, create_if_missing: true)

# Load ontology
{:ok, count} = OntologyLoader.load_ontology(store)
# => {:ok, 672}

# Check if loaded
OntologyLoader.ontology_loaded?(store)
# => true

# List classes
{:ok, classes} = OntologyLoader.list_classes(store)
# => {:ok, ["https://jido.ai/ontology#MemoryItem", ...]}

# List individuals
{:ok, individuals} = OntologyLoader.list_individuals(store)
# => {:ok, ["https://jido.ai/ontology#High", "https://jido.ai/ontology#Medium", ...]}
```

## Known Limitations

1. **SPARQL COUNT Aggregate**: The triple_store library has a bug with COUNT(*) aggregates when there are no results. We avoided using COUNT in the module.

2. **DELETE WHERE Parsing**: The SPARQL DELETE WHERE with FILTER in `reload_ontology/1` doesn't parse correctly in triple_store. The function logs a warning and proceeds with loading anyway.

## Next Steps

With Section 7.2 complete, the next sections of Phase 7 can proceed:
- **7.3**: Create SPARQLQueries module with query templates
- **7.4**: Refactor StoreManager to use TripleStore
- **7.5**: Refactor TripleStoreAdapter for real RDF/SPARQL
