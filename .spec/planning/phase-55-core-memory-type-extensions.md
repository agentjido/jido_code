# Phase 55 - Core Memory Type Extensions

This phase extends the core Jido memory model beyond Fact, Decision, and LessonLearned to include additional first-class memory classes (Invariant, Convention, KnownIssue, OpenQuestion, Pattern, AntiPattern).

<!-- covers: architecture.memory_ontology.coding_memory_types_extend_core_memory_model -->
<!-- covers: package.jido_code.spec_led_workspace -->

Back to index: [README](./README.md)

## Relevant Shared APIs / Interfaces
- `../specs/memory_ontology.spec.md`
- `../decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md`
- `lib/jido_code/memory_graph/durable_memory_envelope.ex`
- `lib/jido_code/memory_graph/durable_memory_writer.ex`
- `priv/ontologies/jido-memory.ttl`

## Relevant Assumptions / Defaults
- Base memory types (Fact, Decision, LessonLearned) are already implemented
- The jido-memory.ttl ontology exists and can be extended
- DurableMemoryEnvelope normalizes and validates capture envelopes
- DurableMemoryWriter writes normalized envelopes to the memory graph

[ ] 55 Phase 55 - Core Memory Type Extensions
  Extend the memory ontology to support additional first-class memory types including Invariant, Convention, KnownIssue, OpenQuestion, Pattern, and AntiPattern, and update envelope and writer logic to handle these new types.

  [ ] 55.1 Section - Ontology Type Definitions
    Add RDF class definitions for the new memory types to the jido-memory ontology with proper rdfs:label and rdfs:comment documentation.

    [ ] 55.1.1 Task - Define Invariant class
      Add Invariant as a subclass of jido:Memory with properties for code invariants that must always hold true.

      [ ] 55.1.1.1 Subtask - Add Invariant RDF class definition to jido-memory.ttl
      [ ] 55.1.1.2 Subtask - Add rdfs:label "Invariant" and rdfs:comment documenting the class
      [ ] 55.1.1.3 Subtask - Define Invariant as a subclass of jido:Memory

    [ ] 55.1.2 Task - Define Convention class
      Add Convention as a subclass of jido:Memory for coding conventions and team agreements.

      [ ] 55.1.2.1 Subtask - Add Convention RDF class definition to jido-memory.ttl
      [ ] 55.1.2.2 Subtask - Add rdfs:label "Convention" and rdfs:comment documenting the class
      [ ] 55.1.2.3 Subtask - Define Convention as a subclass of jido:Memory

    [ ] 55.1.3 Task - Define KnownIssue class
      Add KnownIssue as a subclass of jido:Memory for tracking bugs, recurring problems, and operational weaknesses.

      [ ] 55.1.3.1 Subtask - Add KnownIssue RDF class definition to jido-memory.ttl
      [ ] 55.1.3.2 Subtask - Add rdfs:label "Known Issue" and rdfs:comment documenting the class
      [ ] 55.1.3.3 Subtask - Define KnownIssue as a subclass of jido:Memory

    [ ] 55.1.4 Task - Define OpenQuestion class
      Add OpenQuestion as a subclass of jido:Memory for unresolved questions and areas needing investigation.

      [ ] 55.1.4.1 Subtask - Add OpenQuestion RDF class definition to jido-memory.ttl
      [ ] 55.1.4.2 Subtask - Add rdfs:label "Open Question" and rdfs:comment documenting the class
      [ ] 55.1.4.3 Subtask - Define OpenQuestion as a subclass of jido:Memory

    [ ] 55.1.5 Task - Define Pattern class
      Add Pattern as a subclass of jido:Memory for documenting useful design and coding patterns.

      [ ] 55.1.5.1 Subtask - Add Pattern RDF class definition to jido-memory.ttl
      [ ] 55.1.5.2 Subtask - Add rdfs:label "Pattern" and rdfs:comment documenting the class
      [ ] 55.1.5.3 Subtask - Define Pattern as a subclass of jido:Memory

    [ ] 55.1.6 Task - Define AntiPattern class
      Add AntiPattern as a subclass of jido:Memory for documenting patterns to avoid.

      [ ] 55.1.6.1 Subtask - Add AntiPattern RDF class definition to jido-memory.ttl
      [ ] 55.1.6.2 Subtask - Add rdfs:label "AntiPattern" and rdfs:comment documenting the class
      [ ] 55.1.6.3 Subtask - Define AntiPattern as a subclass of jido:Memory

  [ ] 55.2 Section - Envelope Normalization Updates
    Update DurableMemoryEnvelope.normalize/2 to recognize and validate the new memory types.

    [ ] 55.2.1 Task - Update memory_kinds/0 list
      Extend the @memory_kinds attribute to include all new memory types.

      [ ] 55.2.1.1 Subtask - Add invariant, convention, known_issue, open_question, pattern, anti_pattern to @memory_kinds
      [ ] 55.2.1.2 Subtask - Update supported_kind?/1 to recognize new kinds
      [ ] 55.2.1.3 Subtask - Update kind_paths map with new kind paths

    [ ] 55.2.2 Task - Update kind_class_names map
      Add RDF class name mappings for the new memory types.

      [ ] 55.2.2.1 Subtask - Add class name mappings for all six new types
      [ ] 55.2.2.2 Subtask - Ensure class names follow existing naming convention

    [ ] 55.2.3 Task - Add builder functions for new types
      Create convenience builder functions following the existing pattern (e.g., invariant/1, convention/1).

      [ ] 55.2.3.1 Subtask - Add invariant/1 builder function
      [ ] 55.2.3.2 Subtask - Add convention/1 builder function
      [ ] 55.2.3.3 Subtask - Add known_issue/1 builder function
      [ ] 55.2.3.4 Subtask - Add open_question/1 builder function
      [ ] 55.2.3.5 Subtask - Add pattern/1 builder function
      [ ] 55.2.3.6 Subtask - Add anti_pattern/1 builder function

  [ ] 55.3 Section - Writer Triple Generation
    Update DurableMemoryWriter.triples/1 to emit correct rdf:type statements for new memory types.

    [ ] 55.3.1 Task - Add resource_class_iri for new types
      Update GovernedReference.class_iri/1 to handle new memory types.

      [ ] 55.3.1.1 Subtask - Add class_iri(:invariant) returning jido:Invariant IRI
      [ ] 55.3.1.2 Subtask - Add class_iri(:convention) returning jido:Convention IRI
      [ ] 55.3.1.3 Subtask - Add class_iri(:known_issue) returning jido:KnownIssue IRI
      [ ] 55.3.1.4 Subtask - Add class_iri(:open_question) returning jido:OpenQuestion IRI
      [ ] 55.3.1.5 Subtask - Add class_iri(:pattern) returning jido:Pattern IRI
      [ ] 55.3.1.6 Subtask - Add class_iri(:anti_pattern) returning jido:AntiPattern IRI

    [ ] 55.3.2 Task - Update triple emission for new types
      Ensure writers emit correct rdf:type triples for new memory types.

      [ ] 55.3.2.1 Subtask - Verify resource_class_iri/2 returns correct class for new types
      [ ] 55.3.2.2 Subtask - Ensure jido:Memory type is always included alongside specific type

  [ ] 55.4 Section - Query and View Updates
    Update memory queries and views to recognize and display new memory types.

    [ ] 55.4.1 Task - Update memory queries to include new types
      Ensure SPARQL queries can filter and retrieve new memory types.

      [ ] 55.4.1.1 Subtask - Update HelperQueries.memories/2 to include new types in results
      [ ] 55.4.1.2 Subtask - Add type-specific queries for each new memory kind
      [ ] 55.4.1.3 Subtask - Update memory_kind_name/2 to handle new types

    [ ] 55.4.2 Task - Update ViewModel formatting
      Update ViewModel.memory_item/2 to format new memory types correctly.

      [ ] 55.4.2.1 Subtask - Add new types to @known_memory_kind_suffixes in ViewModel
      [ ] 55.4.2.2 Subtask - Ensure memory_kind_label/2 handles all new types
      [ ] 55.4.2.3 Subtask - Test display of each new memory type in UI

  [ ] 55.5 Section - Operator Surface Support
    Update operator surfaces to allow creating and managing new memory types.

    [ ] 55.5.1 Task - Update OperatorService actions
      Ensure operator actions support creating memories with new types.

      [ ] 55.5.1.1 Subtask - Verify record_invariant/2 creates valid Invariant memories
      [ ] 55.5.1.2 Subtask - Verify record_convention/2 creates valid Convention memories
      [ ] 55.5.1.3 Subtask - Verify record_known_issue/2 creates valid KnownIssue memories
      [ ] 55.5.1.4 Subtask - Verify record_open_question/2 creates valid OpenQuestion memories
      [ ] 55.5.1.5 Subtask - Verify record_pattern/2 creates valid Pattern memories
      [ ] 55.5.1.6 Subtask - Verify record_anti_pattern/2 creates valid AntiPattern memories

    [ ] 55.5.2 Task - Update GovernedAdoption support
      Ensure governed adoption flows can handle new memory types.

      [ ] 55.5.2.1 Subtask - Verify finding classification can produce new memory types
      [ ] 55.5.2.2 Subtask - Test that each new type can be adopted into governed records

  [ ] 55.6 Section - Integration Tests and Verification
    Verify the extended memory types work end-to-end with proper ontology modeling, envelope normalization, writer behavior, and query retrieval.

    [ ] 55.6.1 Task - Ontology type definitions scenarios
      Prove each new memory type is properly defined in the ontology and can be instantiated.

      [ ] 55.6.1.1 Subtask - Add coverage proving Invariant class exists and is a Memory subclass
      [ ] 55.6.1.2 Subtask - Add coverage proving Convention class exists and is a Memory subclass
      [ ] 55.6.1.3 Subtask - Add coverage proving KnownIssue class exists and is a Memory subclass
      [ ] 55.6.1.4 Subtask - Add coverage proving OpenQuestion class exists and is a Memory subclass
      [ ] 55.6.1.5 Subtask - Add coverage proving Pattern class exists and is a Memory subclass
      [ ] 55.6.1.6 Subtask - Add coverage proving AntiPattern class exists and is a Memory subclass

    [ ] 55.6.2 Task - Envelope normalization scenarios
      Prove envelope normalization accepts and validates all new memory types.

      [ ] 55.6.2.1 Subtask - Add coverage proving normalize/2 accepts invariant kind
      [ ] 55.6.2.2 Subtask - Add coverage proving normalize/2 accepts convention kind
      [ ] 55.6.2.3 Subtask - Add coverage proving normalize/2 accepts known_issue kind
      [ ] 55.6.2.4 Subtask - Add coverage proving normalize/2 accepts open_question kind
      [ ] 55.6.2.5 Subtask - Add coverage proving normalize/2 accepts pattern kind
      [ ] 55.6.2.6 Subtask - Add coverage proving normalize/2 accepts anti_pattern kind

    [ ] 55.6.3 Task - Writer triple emission scenarios
      Prove writers emit correct rdf:type triples for new memory types.

      [ ] 55.6.3.1 Subtask - Add coverage proving write/2 emits correct types for Invariant
      [ ] 55.6.3.2 Subtask - Add coverage proving write/2 emits correct types for Convention
      [ ] 55.6.3.3 Subtask - Add coverage proving write/2 emits correct types for KnownIssue
      [ ] 55.6.3.4 Subtask - Add coverage proving write/2 emits correct types for OpenQuestion
      [ ] 55.6.3.5 Subtask - Add coverage proving write/2 emits correct types for Pattern
      [ ] 55.6.3.6 Subtask - Add coverage proving write/2 emits correct types for AntiPattern

    [ ] 55.6.4 Task - Query and retrieval scenarios
      Prove queries can retrieve and filter by new memory types.

      [ ] 55.6.4.1 Subtask - Add coverage proving memories/2 returns new memory types
      [ ] 55.6.4.2 Subtask - Add coverage proving SPARQL queries can filter by new types
      [ ] 55.6.4.3 Subtask - Add coverage proving ViewModel formats new types correctly
