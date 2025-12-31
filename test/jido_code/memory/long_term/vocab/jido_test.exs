defmodule JidoCode.Memory.LongTerm.Vocab.JidoTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.LongTerm.Vocab.Jido

  @jido_ns "https://jido.ai/ontology#"

  # ============================================================================
  # Namespace and IRI Construction Tests
  # ============================================================================

  describe "namespace/0" do
    test "returns the Jido ontology namespace" do
      assert Jido.namespace() == "https://jido.ai/ontology#"
    end
  end

  describe "xsd_namespace/0" do
    test "returns the XML Schema namespace" do
      assert Jido.xsd_namespace() == "http://www.w3.org/2001/XMLSchema#"
    end
  end

  describe "iri/1" do
    test "constructs full IRI with namespace prefix" do
      assert Jido.iri("Fact") == "https://jido.ai/ontology#Fact"
    end

    test "constructs property IRI" do
      assert Jido.iri("hasConfidence") == "https://jido.ai/ontology#hasConfidence"
    end

    test "handles empty string" do
      assert Jido.iri("") == "https://jido.ai/ontology#"
    end
  end

  describe "rdf_type/0" do
    test "returns correct RDF type IRI" do
      assert Jido.rdf_type() == "http://www.w3.org/1999/02/22-rdf-syntax-ns#type"
    end
  end

  # ============================================================================
  # Memory Type Class Tests
  # ============================================================================

  describe "memory type class functions" do
    test "memory_item returns correct IRI" do
      assert Jido.memory_item() == @jido_ns <> "MemoryItem"
    end

    test "fact returns correct IRI" do
      assert Jido.fact() == @jido_ns <> "Fact"
    end

    test "assumption returns correct IRI" do
      assert Jido.assumption() == @jido_ns <> "Assumption"
    end

    test "hypothesis returns correct IRI" do
      assert Jido.hypothesis() == @jido_ns <> "Hypothesis"
    end

    test "discovery returns correct IRI" do
      assert Jido.discovery() == @jido_ns <> "Discovery"
    end

    test "risk returns correct IRI" do
      assert Jido.risk() == @jido_ns <> "Risk"
    end

    test "unknown returns correct IRI" do
      assert Jido.unknown() == @jido_ns <> "Unknown"
    end

    test "decision returns correct IRI" do
      assert Jido.decision() == @jido_ns <> "Decision"
    end

    test "architectural_decision returns correct IRI" do
      assert Jido.architectural_decision() == @jido_ns <> "ArchitecturalDecision"
    end

    test "convention returns correct IRI" do
      assert Jido.convention() == @jido_ns <> "Convention"
    end

    test "coding_standard returns correct IRI" do
      assert Jido.coding_standard() == @jido_ns <> "CodingStandard"
    end

    test "lesson_learned returns correct IRI" do
      assert Jido.lesson_learned() == @jido_ns <> "LessonLearned"
    end

    test "error returns correct IRI" do
      assert Jido.error() == @jido_ns <> "Error"
    end

    test "bug returns correct IRI" do
      assert Jido.bug() == @jido_ns <> "Bug"
    end
  end

  # ============================================================================
  # Memory Type Mapping Tests
  # ============================================================================

  describe "memory_type_to_class/1" do
    test "maps :fact to Fact IRI" do
      assert Jido.memory_type_to_class(:fact) == @jido_ns <> "Fact"
    end

    test "maps :assumption to Assumption IRI" do
      assert Jido.memory_type_to_class(:assumption) == @jido_ns <> "Assumption"
    end

    test "maps :hypothesis to Hypothesis IRI" do
      assert Jido.memory_type_to_class(:hypothesis) == @jido_ns <> "Hypothesis"
    end

    test "maps :discovery to Discovery IRI" do
      assert Jido.memory_type_to_class(:discovery) == @jido_ns <> "Discovery"
    end

    test "maps :risk to Risk IRI" do
      assert Jido.memory_type_to_class(:risk) == @jido_ns <> "Risk"
    end

    test "maps :unknown to Unknown IRI" do
      assert Jido.memory_type_to_class(:unknown) == @jido_ns <> "Unknown"
    end

    test "maps :decision to Decision IRI" do
      assert Jido.memory_type_to_class(:decision) == @jido_ns <> "Decision"
    end

    test "maps :convention to Convention IRI" do
      assert Jido.memory_type_to_class(:convention) == @jido_ns <> "Convention"
    end

    test "maps :lesson_learned to LessonLearned IRI" do
      assert Jido.memory_type_to_class(:lesson_learned) == @jido_ns <> "LessonLearned"
    end

    test "raises for unknown memory types" do
      assert_raise ArgumentError, ~r/Unknown memory type/, fn ->
        Jido.memory_type_to_class(:invalid_type)
      end
    end
  end

  describe "class_to_memory_type/1" do
    test "maps Fact IRI to :fact" do
      assert Jido.class_to_memory_type(@jido_ns <> "Fact") == :fact
    end

    test "maps Assumption IRI to :assumption" do
      assert Jido.class_to_memory_type(@jido_ns <> "Assumption") == :assumption
    end

    test "maps Hypothesis IRI to :hypothesis" do
      assert Jido.class_to_memory_type(@jido_ns <> "Hypothesis") == :hypothesis
    end

    test "maps Discovery IRI to :discovery" do
      assert Jido.class_to_memory_type(@jido_ns <> "Discovery") == :discovery
    end

    test "maps Risk IRI to :risk" do
      assert Jido.class_to_memory_type(@jido_ns <> "Risk") == :risk
    end

    test "maps Unknown IRI to :unknown" do
      assert Jido.class_to_memory_type(@jido_ns <> "Unknown") == :unknown
    end

    test "maps Decision IRI to :decision" do
      assert Jido.class_to_memory_type(@jido_ns <> "Decision") == :decision
    end

    test "maps Convention IRI to :convention" do
      assert Jido.class_to_memory_type(@jido_ns <> "Convention") == :convention
    end

    test "maps LessonLearned IRI to :lesson_learned" do
      assert Jido.class_to_memory_type(@jido_ns <> "LessonLearned") == :lesson_learned
    end

    test "returns :unknown for unrecognized IRIs" do
      assert Jido.class_to_memory_type("https://example.org/SomeClass") == :unknown
    end

    test "returns :unknown for different namespace" do
      assert Jido.class_to_memory_type("https://other.org/ontology#Fact") == :unknown
    end
  end

  # ============================================================================
  # Confidence Level Tests
  # ============================================================================

  describe "confidence level functions" do
    test "confidence_high returns correct IRI" do
      assert Jido.confidence_high() == @jido_ns <> "High"
    end

    test "confidence_medium returns correct IRI" do
      assert Jido.confidence_medium() == @jido_ns <> "Medium"
    end

    test "confidence_low returns correct IRI" do
      assert Jido.confidence_low() == @jido_ns <> "Low"
    end
  end

  describe "confidence_to_individual/1" do
    test "maps 0.8 to High" do
      assert Jido.confidence_to_individual(0.8) == @jido_ns <> "High"
    end

    test "maps 0.9 to High" do
      assert Jido.confidence_to_individual(0.9) == @jido_ns <> "High"
    end

    test "maps 1.0 to High" do
      assert Jido.confidence_to_individual(1.0) == @jido_ns <> "High"
    end

    test "maps 0.5 to Medium" do
      assert Jido.confidence_to_individual(0.5) == @jido_ns <> "Medium"
    end

    test "maps 0.6 to Medium" do
      assert Jido.confidence_to_individual(0.6) == @jido_ns <> "Medium"
    end

    test "maps 0.79 to Medium" do
      assert Jido.confidence_to_individual(0.79) == @jido_ns <> "Medium"
    end

    test "maps 0.49 to Low" do
      assert Jido.confidence_to_individual(0.49) == @jido_ns <> "Low"
    end

    test "maps 0.3 to Low" do
      assert Jido.confidence_to_individual(0.3) == @jido_ns <> "Low"
    end

    test "maps 0.0 to Low" do
      assert Jido.confidence_to_individual(0.0) == @jido_ns <> "Low"
    end
  end

  describe "individual_to_confidence/1" do
    test "High returns 0.9" do
      assert Jido.individual_to_confidence(@jido_ns <> "High") == 0.9
    end

    test "Medium returns 0.6" do
      assert Jido.individual_to_confidence(@jido_ns <> "Medium") == 0.6
    end

    test "Low returns 0.3" do
      assert Jido.individual_to_confidence(@jido_ns <> "Low") == 0.3
    end

    test "unrecognized IRI returns 0.5" do
      assert Jido.individual_to_confidence("https://example.org/Unknown") == 0.5
    end
  end

  # ============================================================================
  # Source Type Tests
  # ============================================================================

  describe "source type functions" do
    test "source_user returns correct IRI" do
      assert Jido.source_user() == @jido_ns <> "UserSource"
    end

    test "source_agent returns correct IRI" do
      assert Jido.source_agent() == @jido_ns <> "AgentSource"
    end

    test "source_tool returns correct IRI" do
      assert Jido.source_tool() == @jido_ns <> "ToolSource"
    end

    test "source_external returns correct IRI" do
      assert Jido.source_external() == @jido_ns <> "ExternalDocumentSource"
    end
  end

  describe "source_type_to_individual/1" do
    test "maps :user to UserSource IRI" do
      assert Jido.source_type_to_individual(:user) == @jido_ns <> "UserSource"
    end

    test "maps :agent to AgentSource IRI" do
      assert Jido.source_type_to_individual(:agent) == @jido_ns <> "AgentSource"
    end

    test "maps :tool to ToolSource IRI" do
      assert Jido.source_type_to_individual(:tool) == @jido_ns <> "ToolSource"
    end

    test "maps :external_document to ExternalDocumentSource IRI" do
      assert Jido.source_type_to_individual(:external_document) ==
               @jido_ns <> "ExternalDocumentSource"
    end

    test "raises for unknown source types" do
      assert_raise ArgumentError, ~r/Unknown source type/, fn ->
        Jido.source_type_to_individual(:invalid_source)
      end
    end
  end

  describe "individual_to_source_type/1" do
    test "maps UserSource IRI to :user" do
      assert Jido.individual_to_source_type(@jido_ns <> "UserSource") == :user
    end

    test "maps AgentSource IRI to :agent" do
      assert Jido.individual_to_source_type(@jido_ns <> "AgentSource") == :agent
    end

    test "maps ToolSource IRI to :tool" do
      assert Jido.individual_to_source_type(@jido_ns <> "ToolSource") == :tool
    end

    test "maps ExternalDocumentSource IRI to :external_document" do
      assert Jido.individual_to_source_type(@jido_ns <> "ExternalDocumentSource") ==
               :external_document
    end

    test "returns :unknown for unrecognized source IRIs" do
      assert Jido.individual_to_source_type("https://example.org/Unknown") == :unknown
    end
  end

  # ============================================================================
  # Property IRI Tests
  # ============================================================================

  describe "property functions" do
    test "summary returns correct IRI" do
      assert Jido.summary() == @jido_ns <> "summary"
    end

    test "detailed_explanation returns correct IRI" do
      assert Jido.detailed_explanation() == @jido_ns <> "detailedExplanation"
    end

    test "rationale returns correct IRI" do
      assert Jido.rationale() == @jido_ns <> "rationale"
    end

    test "has_confidence returns correct IRI" do
      assert Jido.has_confidence() == @jido_ns <> "hasConfidence"
    end

    test "has_source_type returns correct IRI" do
      assert Jido.has_source_type() == @jido_ns <> "hasSourceType"
    end

    test "has_timestamp returns correct IRI" do
      assert Jido.has_timestamp() == @jido_ns <> "hasTimestamp"
    end

    test "asserted_by returns correct IRI" do
      assert Jido.asserted_by() == @jido_ns <> "assertedBy"
    end

    test "asserted_in returns correct IRI" do
      assert Jido.asserted_in() == @jido_ns <> "assertedIn"
    end

    test "applies_to_project returns correct IRI" do
      assert Jido.applies_to_project() == @jido_ns <> "appliesToProject"
    end

    test "derived_from returns correct IRI" do
      assert Jido.derived_from() == @jido_ns <> "derivedFrom"
    end

    test "superseded_by returns correct IRI" do
      assert Jido.superseded_by() == @jido_ns <> "supersededBy"
    end

    test "invalidated_by returns correct IRI" do
      assert Jido.invalidated_by() == @jido_ns <> "invalidatedBy"
    end

    test "has_access_count returns correct IRI" do
      assert Jido.has_access_count() == @jido_ns <> "hasAccessCount"
    end

    test "last_accessed returns correct IRI" do
      assert Jido.last_accessed() == @jido_ns <> "lastAccessed"
    end
  end

  # ============================================================================
  # Entity IRI Generator Tests
  # ============================================================================

  describe "memory_uri/1" do
    test "generates valid IRI from id" do
      assert Jido.memory_uri("abc123") == @jido_ns <> "memory_abc123"
    end

    test "handles UUID-style ids" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert Jido.memory_uri(uuid) == @jido_ns <> "memory_" <> uuid
    end

    test "handles empty id" do
      assert Jido.memory_uri("") == @jido_ns <> "memory_"
    end
  end

  describe "session_uri/1" do
    test "generates valid IRI from id" do
      assert Jido.session_uri("session-123") == @jido_ns <> "session_session-123"
    end

    test "handles UUID-style ids" do
      uuid = "550e8400-e29b-41d4-a716-446655440000"
      assert Jido.session_uri(uuid) == @jido_ns <> "session_" <> uuid
    end
  end

  describe "agent_uri/1" do
    test "generates valid IRI from id" do
      assert Jido.agent_uri("agent-456") == @jido_ns <> "agent_agent-456"
    end
  end

  describe "project_uri/1" do
    test "generates valid IRI from id" do
      assert Jido.project_uri("my-project") == @jido_ns <> "project_my-project"
    end
  end

  describe "evidence_uri/1" do
    test "generates IRI with hashed reference" do
      ref = "file:lib/foo.ex:42"
      uri = Jido.evidence_uri(ref)
      assert String.starts_with?(uri, @jido_ns <> "evidence_")
      # Hash is 16 chars
      assert String.length(uri) == String.length(@jido_ns <> "evidence_") + 16
    end

    test "same reference produces same hash" do
      ref = "file:lib/bar.ex:100"
      assert Jido.evidence_uri(ref) == Jido.evidence_uri(ref)
    end

    test "different references produce different hashes" do
      uri1 = Jido.evidence_uri("file:a.ex:1")
      uri2 = Jido.evidence_uri("file:b.ex:2")
      assert uri1 != uri2
    end
  end

  describe "hash_ref/1" do
    test "produces 16 character lowercase hex string" do
      hash = Jido.hash_ref("some reference")
      assert String.length(hash) == 16
      assert hash =~ ~r/^[a-f0-9]+$/
    end

    test "is deterministic" do
      ref = "test reference"
      assert Jido.hash_ref(ref) == Jido.hash_ref(ref)
    end
  end
end
