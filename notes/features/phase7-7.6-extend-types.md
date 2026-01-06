# Feature Plan: Section 7.6 - Extend Types Module

**Feature:** Extend Types Module with Full Ontology Alignment
**Branch:** `feature/phase7-7.6-extend-types`
**Phase:** Phase 7 - Triple Store Integration & Ontology Alignment
**Status:** In Progress

---

## Problem Statement

The current `JidoCode.Memory.Types` module has only partial alignment with the Jido ontology defined in the TTL files. Specifically:

1. **Missing Memory Types**: The ontology defines additional memory types that are not represented:
   - From `jido-decision.ttl`: `:implementation_decision`, `:alternative`, `:trade_off`
   - From `jido-convention.ttl`: `:architectural_convention`, `:agent_rule`, `:process_convention`
   - From `jido-error.ttl`: `:error`, `:bug`, `:failure`, `:incident`, `:root_cause`

2. **Missing IRI Mapping Functions**: No functions to convert between atoms and ontology IRIs

3. **Missing Relationship Types**: Ontology defines relationships (e.g., `:refines`, `:has_alternative`) that are not typed

4. **Missing Individual Types**: Ontology defines individuals like `:evidence_strength`, `:convention_scope`, `:enforcement_level`, `:error_status` that should have corresponding types

**Impact**: Code using the memory system cannot fully leverage the semantic richness of the Jido ontology, limiting query capabilities and type safety.

---

## Solution Overview

Extend the `Types` module to:

1. Add all missing memory types from the ontology
2. Add IRI mapping functions (`memory_type_to_iri/1`, `iri_to_memory_type/1`)
3. Add relationship type definitions with IRI mappings
4. Add individual type definitions (evidence strength, convention scope, enforcement level, error status)
5. Update all validation functions to include the new types
6. Maintain backward compatibility with existing code

**Design Decision**: Keep types as atoms (not IRIs) in Elixir code, with conversion functions for SPARQL operations. This maintains idiomatic Elixir while ensuring proper ontology alignment.

---

## Agent Consultations

This is a self-contained type extension task based on existing ontology definitions. No external agent consultation required - all necessary information is in the TTL files and existing code patterns.

---

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/memory/types.ex` | Add new types, mappings, and validation functions |
| `test/jido_code/memory/types_test.exs` | Add tests for new types and mappings |

### Dependencies

- None (uses existing ontology definitions)

### Configuration

- None (type definitions are compile-time constants)

---

## Ontology Type Analysis

### Memory Types (from TTL files)

| TTL File | Ontology Class | Current Status | Action |
|----------|---------------|----------------|--------|
| jido-knowledge.ttl | `Fact` | ✓ `:fact` | None |
| jido-knowledge.ttl | `Assumption` | ✓ `:assumption` | None |
| jido-knowledge.ttl | `Hypothesis` | ✓ `:hypothesis` | None |
| jido-knowledge.ttl | `Discovery` | ✓ `:discovery` | None |
| jido-knowledge.ttl | `Risk` | ✓ `:risk` | None |
| jido-knowledge.ttl | `Unknown` | ✓ `:unknown` | None |
| jido-decision.ttl | `Decision` | ✓ `:decision` | None |
| jido-decision.ttl | `ArchitecturalDecision` | ✓ `:architectural_decision` | None |
| jido-decision.ttl | `ImplementationDecision` | ✗ Missing | **Add `:implementation_decision`** |
| jido-decision.ttl | `Alternative` | ✗ Missing | **Add `:alternative`** |
| jido-decision.ttl | `TradeOff` | ✗ Missing | **Add `:trade_off`** |
| jido-convention.ttl | `Convention` | ✓ `:convention` | None |
| jido-convention.ttl | `CodingStandard` | ✓ `:coding_standard` | None |
| jido-convention.ttl | `ArchitecturalConvention` | ✗ Missing | **Add `:architectural_convention`** |
| jido-convention.ttl | `AgentRule` | ✗ Missing | **Add `:agent_rule`** |
| jido-convention.ttl | `ProcessConvention` | ✗ Missing | **Add `:process_convention`** |
| jido-error.ttl | `Error` | ✗ Missing | **Add `:error`** |
| jido-error.ttl | `Bug` | ✗ Missing | **Add `:bug`** |
| jido-error.ttl | `Failure` | ✗ Missing | **Add `:failure`** |
| jido-error.ttl | `Incident` | ✗ Missing | **Add `:incident`** |
| jido-error.ttl | `RootCause` | ✗ Missing | **Add `:root_cause`** |
| jido-error.ttl | `LessonLearned` | ✓ `:lesson_learned` | None |

### Relationship Types (from TTL files)

| TTL File | Ontology Property | Type |
|----------|------------------|------|
| jido-knowledge.ttl | `refines` | `:refines` |
| jido-knowledge.ttl | `confirms` | `:confirms` |
| jido-knowledge.ttl | `contradicts` | `:contradicts` |
| jido-decision.ttl | `hasAlternative` | `:has_alternative` |
| jido-decision.ttl | `selectedAlternative` | `:selected_alternative` |
| jido-decision.ttl | `hasTradeOff` | `:has_trade_off` |
| jido-decision.ttl | `justifiedBy` | `:justified_by` |
| jido-error.ttl | `hasRootCause` | `:has_root_cause` |
| jido-error.ttl | `producedLesson` | `:produced_lesson` |
| jido-error.ttl | `relatedError` | `:related_error` |
| jido-code.ttl | `derivedFrom` | `:derived_from` |
| jido-code.ttl | `supersededBy` | `:superseded_by` |

### Individual Types (from TTL files)

| TTL File | Ontology Class | Values |
|----------|---------------|--------|
| jido-knowledge.ttl | `EvidenceStrength` | `:weak`, `:moderate`, `:strong` |
| jido-convention.ttl | `ConventionScope` | `:global`, `:project`, `:agent` |
| jido-convention.ttl | `EnforcementLevel` | `:advisory`, `:required`, `:strict` |
| jido-error.ttl | `ErrorStatus` | `:reported`, `:investigating`, `:resolved`, `:deferred` |

---

## Success Criteria

1. All 22 memory types from the ontology are defined in `Types.memory_type()`
2. IRI round-trip conversion works for all memory types
3. All 12 relationship types are defined with IRI mappings
4. All individual types are defined with their valid values
5. All validation functions support the new types
6. 100% of new tests pass
7. No existing tests break
8. Backward compatibility maintained (existing code continues to work)

---

## Implementation Plan

### 7.6.1 Align Types with Ontology

- [ ] Add missing memory types to `@type memory_type`
- [ ] Add missing types to `@memory_types` attribute
- [ ] Add `memory_type_to_iri/1` function
- [ ] Add `iri_to_memory_type/1` function
- [ ] Update documentation table

### 7.6.2 Add Ontology Relationship Types

- [ ] Add `@type relationship` with all 12 relationships
- [ ] Add `@relationships` attribute list
- [ ] Add `relationship_to_iri/1` function
- [ ] Add `iri_to_relationship/1` function
- [ ] Add `valid_relationship?/1` validation function
- [ ] Add documentation for relationship types

### 7.6.3 Add Ontology Individual Types

- [ ] Add `@type evidence_strength` with `:weak`, `:moderate`, `:strong`
- [ ] Add `@type convention_scope` with `:global`, `:project`, `:agent`
- [ ] Add `@type enforcement_level` with `:advisory`, `:required`, `:strict`
- [ ] Add `@type error_status` with `:reported`, `:investigating`, `:resolved`, `:deferred`
- [ ] Add validation functions for each individual type
- [ ] Add IRI conversion functions for individuals

### 7.6.4 Types Tests

- [ ] Test all 22 memory types are valid
- [ ] Test memory type IRI round-trip conversion
- [ ] Test all 12 relationship types are valid
- [ ] Test relationship IRI conversions
- [ ] Test all individual type validations
- [ ] Test individual IRI conversions
- [ ] Update existing tests for expanded memory types

---

## Notes/Considerations

### Backward Compatibility

All existing memory types remain unchanged. New types are additive only.

### SPARQL Integration

The new IRI conversion functions align with the pattern already used in `SPARQLQueries`. The maps there will need to be updated in a future section (7.7).

### Future Work

- Section 7.7 will consolidate duplicated type mappings between `Types` and `SPARQLQueries`
- Section 7.8-7.9 will update Memory facade and Actions to use new types
- Individual type mappings should be added to `SPARQLQueries` for consistency

---

## Status

**Current:** Implementation pending planning approval
**Next:** Begin 7.6.1 - Align Types with Ontology
