# Phase 2 Task 2.1.1 - Jido Vocabulary Module

**Date:** 2025-12-29
**Branch:** `feature/phase2-vocabulary-module`
**Task:** 2.1.1 Vocabulary Module and 2.1.2 Unit Tests

## Overview

Implemented the Jido ontology vocabulary namespace module providing type-safe access to RDF IRIs for memory operations. This module enables proper semantic mapping between Elixir memory types and their RDF representations in the triple store.

## Implementation Details

### Module Location
`lib/jido_code/memory/long_term/vocab/jido.ex`

### Namespace Constants
```elixir
@jido_ns "https://jido.ai/ontology#"
@rdf_type "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
@xsd_ns "http://www.w3.org/2001/XMLSchema#"
```

### Features Implemented

#### 1. IRI Construction
- `iri/1` - Constructs full IRI from local name
- `namespace/0` - Returns Jido namespace prefix
- `xsd_namespace/0` - Returns XML Schema namespace
- `rdf_type/0` - Returns RDF type IRI

#### 2. Memory Type Classes
All Jido ontology memory type classes:
- `memory_item/0`, `fact/0`, `assumption/0`, `hypothesis/0`
- `discovery/0`, `risk/0`, `unknown/0`, `decision/0`
- `architectural_decision/0`, `convention/0`, `coding_standard/0`
- `lesson_learned/0`, `error/0`, `bug/0`

#### 3. Type Mapping Functions
- `memory_type_to_class/1` - Maps Elixir atom to IRI (raises for unknown types)
- `class_to_memory_type/1` - Maps IRI to Elixir atom (returns :unknown for unrecognized)

#### 4. Confidence Level Handling
- `confidence_high/0`, `confidence_medium/0`, `confidence_low/0`
- `confidence_to_individual/1` - Float to IRI mapping
  - >= 0.8 → High
  - >= 0.5 → Medium
  - < 0.5 → Low
- `individual_to_confidence/1` - IRI to float mapping
  - High → 0.9, Medium → 0.6, Low → 0.3

#### 5. Source Type Handling
- `source_user/0`, `source_agent/0`, `source_tool/0`, `source_external/0`
- `source_type_to_individual/1` - Atom to IRI (raises for unknown)
- `individual_to_source_type/1` - IRI to atom (returns :unknown for unrecognized)

#### 6. Property IRIs
Content properties: `summary/0`, `detailed_explanation/0`, `rationale/0`
Metadata properties: `has_confidence/0`, `has_source_type/0`, `has_timestamp/0`
Provenance properties: `asserted_by/0`, `asserted_in/0`, `applies_to_project/0`
Lifecycle properties: `derived_from/0`, `superseded_by/0`, `invalidated_by/0`
Access tracking: `has_access_count/0`, `last_accessed/0`

#### 7. Entity IRI Generators
- `memory_uri/1` - Generates memory entity IRI from id
- `session_uri/1` - Generates session entity IRI from id
- `agent_uri/1` - Generates agent entity IRI from id
- `project_uri/1` - Generates project entity IRI from id
- `evidence_uri/1` - Generates evidence IRI with hashed reference

## Test Coverage

**Test File:** `test/jido_code/memory/long_term/vocab/jido_test.exs`

**97 tests covering:**
- Namespace and IRI construction
- All memory type class functions
- Memory type mapping (both directions)
- Confidence level mapping (both directions)
- Source type mapping (both directions)
- All property IRI functions
- Entity IRI generators
- Edge cases (unknown types, unrecognized IRIs)

## Test Results

```
Memory Tests: 238 tests, 0 failures
Vocabulary Tests: 97 tests, 0 failures
```

## Files Created

| File | Purpose |
|------|---------|
| `lib/jido_code/memory/long_term/vocab/jido.ex` | Jido vocabulary namespace module |
| `test/jido_code/memory/long_term/vocab/jido_test.exs` | Comprehensive unit tests |

## Files Modified

| File | Changes |
|------|---------|
| `notes/planning/two-tier-memory/phase-02-long-term-store.md` | Marked 2.1.1 and 2.1.2 tasks complete |

## Next Steps

This completes Task 2.1.1 and 2.1.2. The vocabulary module is now ready for use by:
- Task 2.2 - Store Manager (session-isolated triple store lifecycle)
- Task 2.3 - Triple Store Adapter (Elixir struct ↔ RDF triple mapping)
