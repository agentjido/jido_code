defmodule JidoCode.Memory.LongTerm.SPARQLQueriesTest do
  # Changed to async: false for consistency with other Phase 7 tests (C12)
  use ExUnit.Case, async: false

  alias JidoCode.Memory.LongTerm.SPARQLQueries

  @moduletag :sparql_queries

  describe "namespace/0" do
    test "returns the Jido namespace IRI" do
      assert SPARQLQueries.namespace() == "https://jido.ai/ontology#"
    end
  end

  describe "prefixes/0" do
    test "returns all standard prefixes" do
      prefixes = SPARQLQueries.prefixes()
      assert String.contains?(prefixes, "PREFIX jido:")
      assert String.contains?(prefixes, "PREFIX rdf:")
      assert String.contains?(prefixes, "PREFIX rdfs:")
      assert String.contains?(prefixes, "PREFIX xsd:")
      assert String.contains?(prefixes, "PREFIX owl:")
    end
  end

  describe "insert_memory/1" do
    test "generates valid INSERT DATA query" do
      memory = %{
        id: "test123",
        content: "Test content",
        memory_type: :fact,
        confidence: :high,
        source_type: :agent,
        session_id: "session_456"
      }

      query = SPARQLQueries.insert_memory(memory)

      assert String.contains?(query, "INSERT DATA")
      assert String.contains?(query, "jido:memory_test123")
      assert String.contains?(query, "rdf:type jido:Fact")
      assert String.contains?(query, ~s(jido:summary "Test content"))
      assert String.contains?(query, "jido:hasConfidence jido:High")
      assert String.contains?(query, "jido:hasSourceType jido:AgentSource")
      assert String.contains?(query, "jido:assertedIn jido:session_session_456")
      assert String.contains?(query, "xsd:dateTime")
    end

    test "handles all memory types" do
      types = [
        :fact,
        :assumption,
        :hypothesis,
        :discovery,
        :risk,
        :unknown,
        :decision,
        :architectural_decision,
        :convention,
        :coding_standard,
        :lesson_learned
      ]

      for type <- types do
        memory = %{id: "test", content: "x", memory_type: type, session_id: "s"}
        query = SPARQLQueries.insert_memory(memory)
        class_name = SPARQLQueries.memory_type_to_class(type)
        assert String.contains?(query, "rdf:type jido:#{class_name}")
      end
    end

    test "handles confidence levels" do
      for level <- [:high, :medium, :low] do
        memory = %{id: "test", content: "x", confidence: level, session_id: "s"}
        query = SPARQLQueries.insert_memory(memory)
        individual = SPARQLQueries.confidence_to_individual(level)
        assert String.contains?(query, "jido:hasConfidence jido:#{individual}")
      end
    end

    test "handles source types" do
      for source <- [:user, :agent, :tool, :external_document] do
        memory = %{id: "test", content: "x", source_type: source, session_id: "s"}
        query = SPARQLQueries.insert_memory(memory)
        individual = SPARQLQueries.source_type_to_individual(source)
        assert String.contains?(query, "jido:hasSourceType jido:#{individual}")
      end
    end

    test "includes rationale when provided" do
      memory = %{
        id: "test",
        content: "x",
        session_id: "s",
        rationale: "Because of reasons"
      }

      query = SPARQLQueries.insert_memory(memory)
      assert String.contains?(query, "jido:rationale")
      assert String.contains?(query, "Because of reasons")
    end

    test "includes evidence refs when provided" do
      memory = %{
        id: "test",
        content: "x",
        session_id: "s",
        evidence_refs: ["ev1", "ev2"]
      }

      query = SPARQLQueries.insert_memory(memory)
      assert String.contains?(query, "jido:derivedFrom jido:evidence_ev1")
      assert String.contains?(query, "jido:derivedFrom jido:evidence_ev2")
    end

    test "uses defaults for missing fields" do
      memory = %{session_id: "s"}
      query = SPARQLQueries.insert_memory(memory)

      # Should use defaults
      assert String.contains?(query, "rdf:type jido:Fact")
      assert String.contains?(query, "jido:hasConfidence jido:Medium")
      assert String.contains?(query, "jido:hasSourceType jido:AgentSource")
    end
  end

  describe "query_by_session/2" do
    test "generates valid SELECT query" do
      query = SPARQLQueries.query_by_session("session_123")

      assert String.contains?(query, "SELECT")
      assert String.contains?(query, "?mem ?type ?content ?confidence ?source ?timestamp")
      assert String.contains?(query, "jido:assertedIn jido:session_session_123")
      assert String.contains?(query, "ORDER BY DESC(?timestamp)")
    end

    test "excludes superseded memories by default" do
      query = SPARQLQueries.query_by_session("s")
      assert String.contains?(query, "FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }")
    end

    test "includes superseded when requested" do
      query = SPARQLQueries.query_by_session("s", include_superseded: true)
      refute String.contains?(query, "FILTER NOT EXISTS")
    end

    test "applies limit when provided" do
      query = SPARQLQueries.query_by_session("s", limit: 10)
      assert String.contains?(query, "LIMIT 10")
    end

    test "applies min_confidence filter for :medium" do
      query = SPARQLQueries.query_by_session("s", min_confidence: :medium)
      assert String.contains?(query, "FILTER(?confidence IN (jido:High, jido:Medium))")
    end

    test "applies min_confidence filter for :high" do
      query = SPARQLQueries.query_by_session("s", min_confidence: :high)
      assert String.contains?(query, "FILTER(?confidence = jido:High)")
    end

    test "supports order_by options" do
      query_desc = SPARQLQueries.query_by_session("s", order_by: :timestamp, order: :desc)
      assert String.contains?(query_desc, "ORDER BY DESC(?timestamp)")

      query_asc = SPARQLQueries.query_by_session("s", order_by: :timestamp, order: :asc)
      assert String.contains?(query_asc, "ORDER BY ASC(?timestamp)")

      query_access = SPARQLQueries.query_by_session("s", order_by: :access_count, order: :desc)
      assert String.contains?(query_access, "ORDER BY DESC(?accessCount)")
    end
  end

  describe "query_by_type/3" do
    test "generates valid SELECT query with type filter" do
      query = SPARQLQueries.query_by_type("session_123", :fact)

      assert String.contains?(query, "SELECT")
      assert String.contains?(query, "rdf:type jido:Fact")
      assert String.contains?(query, "jido:assertedIn jido:session_session_123")
    end

    test "works with all memory types" do
      for type <- JidoCode.Memory.Types.memory_types() do
        query = SPARQLQueries.query_by_type("s", type)
        class_name = SPARQLQueries.memory_type_to_class(type)
        assert String.contains?(query, "rdf:type jido:#{class_name}")
      end
    end

    test "supports same options as query_by_session" do
      query = SPARQLQueries.query_by_type("s", :fact, limit: 5, min_confidence: :high)
      assert String.contains?(query, "LIMIT 5")
      assert String.contains?(query, "FILTER(?confidence = jido:High)")
    end
  end

  describe "query_by_id/1" do
    test "generates valid SELECT query for single memory" do
      query = SPARQLQueries.query_by_id("mem_123")

      assert String.contains?(query, "SELECT")
      assert String.contains?(query, "jido:memory_mem_123")
      assert String.contains?(query, "?type ?content ?confidence ?source ?timestamp")
      assert String.contains?(query, "?supersededBy")
    end
  end

  describe "supersede_memory/2" do
    test "generates valid INSERT DATA query" do
      query = SPARQLQueries.supersede_memory("old_id", "new_id")

      assert String.contains?(query, "INSERT DATA")
      assert String.contains?(query, "jido:memory_old_id jido:supersededBy jido:memory_new_id")
    end
  end

  describe "delete_memory/1" do
    test "generates soft delete query with DeletedMarker" do
      query = SPARQLQueries.delete_memory("mem_123")

      assert String.contains?(query, "INSERT DATA")
      assert String.contains?(query, "jido:memory_mem_123 jido:supersededBy jido:DeletedMarker")
    end
  end

  describe "record_access/1" do
    test "generates update query for access tracking" do
      query = SPARQLQueries.record_access("mem_123")

      assert String.contains?(query, "INSERT")
      assert String.contains?(query, "jido:memory_mem_123")
      assert String.contains?(query, "jido:lastAccessed")
      assert String.contains?(query, "xsd:dateTime")
    end
  end

  describe "query_related/2" do
    test "generates query for refines relationship" do
      query = SPARQLQueries.query_related("mem_123", :refines)

      assert String.contains?(query, "jido:memory_mem_123 jido:refines ?related")
    end

    test "generates query for confirms relationship" do
      query = SPARQLQueries.query_related("mem_123", :confirms)

      assert String.contains?(query, "jido:memory_mem_123 jido:confirms ?related")
    end

    test "generates query for superseded_by relationship" do
      query = SPARQLQueries.query_related("mem_123", :superseded_by)

      assert String.contains?(query, "jido:memory_mem_123 jido:supersededBy ?related")
    end
  end

  describe "query_by_evidence/1" do
    test "generates query for evidence-linked memories" do
      query = SPARQLQueries.query_by_evidence("ev_123")

      assert String.contains?(query, "jido:derivedFrom jido:evidence_ev_123")
      assert String.contains?(query, "FILTER NOT EXISTS { ?mem jido:supersededBy ?newer }")
    end
  end

  describe "query_decisions_with_alternatives/1" do
    test "generates query for decisions with alternatives" do
      query = SPARQLQueries.query_decisions_with_alternatives("session_123")

      assert String.contains?(query, "rdf:type jido:Decision")
      assert String.contains?(query, "jido:hasAlternative ?alternative")
      assert String.contains?(query, "jido:assertedIn jido:session_session_123")
    end
  end

  describe "query_lessons_for_error/1" do
    test "generates query for lessons learned from error" do
      query = SPARQLQueries.query_lessons_for_error("error_123")

      assert String.contains?(query, "jido:memory_error_123 jido:producedLesson ?lesson")
      assert String.contains?(query, "rdf:type jido:LessonLearned")
    end
  end

  describe "memory_type_to_class/1" do
    test "converts all memory types correctly" do
      mappings = [
        {:fact, "Fact"},
        {:assumption, "Assumption"},
        {:hypothesis, "Hypothesis"},
        {:discovery, "Discovery"},
        {:risk, "Risk"},
        {:unknown, "Unknown"},
        {:decision, "Decision"},
        {:architectural_decision, "ArchitecturalDecision"},
        {:convention, "Convention"},
        {:coding_standard, "CodingStandard"},
        {:lesson_learned, "LessonLearned"}
      ]

      for {type, class} <- mappings do
        assert SPARQLQueries.memory_type_to_class(type) == class
      end
    end
  end

  describe "class_to_memory_type/1" do
    test "converts class names to memory types" do
      mappings = [
        {"Fact", :fact},
        {"Assumption", :assumption},
        {"Hypothesis", :hypothesis},
        {"Discovery", :discovery},
        {"Risk", :risk},
        {"Unknown", :unknown},
        {"Decision", :decision},
        {"ArchitecturalDecision", :architectural_decision},
        {"Convention", :convention},
        {"CodingStandard", :coding_standard},
        {"LessonLearned", :lesson_learned}
      ]

      for {class, type} <- mappings do
        assert SPARQLQueries.class_to_memory_type(class) == type
      end
    end

    test "handles full IRIs" do
      iri = "https://jido.ai/ontology#Fact"
      assert SPARQLQueries.class_to_memory_type(iri) == :fact
    end

    test "returns :unknown for unrecognized classes" do
      assert SPARQLQueries.class_to_memory_type("SomeRandomClass") == :unknown
    end
  end

  describe "confidence_to_individual/1" do
    test "converts confidence levels to individuals" do
      assert SPARQLQueries.confidence_to_individual(:high) == "High"
      assert SPARQLQueries.confidence_to_individual(:medium) == "Medium"
      assert SPARQLQueries.confidence_to_individual(:low) == "Low"
    end
  end

  describe "individual_to_confidence/1" do
    test "converts individuals to confidence levels" do
      assert SPARQLQueries.individual_to_confidence("High") == :high
      assert SPARQLQueries.individual_to_confidence("Medium") == :medium
      assert SPARQLQueries.individual_to_confidence("Low") == :low
    end

    test "handles full IRIs" do
      assert SPARQLQueries.individual_to_confidence("https://jido.ai/ontology#High") == :high
    end

    test "returns :low for unrecognized values" do
      assert SPARQLQueries.individual_to_confidence("Unknown") == :low
    end
  end

  describe "source_type_to_individual/1" do
    test "converts source types to individuals" do
      assert SPARQLQueries.source_type_to_individual(:user) == "UserSource"
      assert SPARQLQueries.source_type_to_individual(:agent) == "AgentSource"
      assert SPARQLQueries.source_type_to_individual(:tool) == "ToolSource"
      assert SPARQLQueries.source_type_to_individual(:external_document) == "ExternalDocumentSource"
    end
  end

  describe "individual_to_source_type/1" do
    test "converts individuals to source types" do
      assert SPARQLQueries.individual_to_source_type("UserSource") == :user
      assert SPARQLQueries.individual_to_source_type("AgentSource") == :agent
      assert SPARQLQueries.individual_to_source_type("ToolSource") == :tool
      assert SPARQLQueries.individual_to_source_type("ExternalDocumentSource") == :external_document
    end

    test "handles full IRIs" do
      assert SPARQLQueries.individual_to_source_type("https://jido.ai/ontology#UserSource") == :user
    end
  end

  describe "escape_string/1" do
    test "escapes double quotes" do
      assert SPARQLQueries.escape_string(~s(hello "world")) == ~s("hello \\"world\\"")
    end

    test "escapes backslashes" do
      assert SPARQLQueries.escape_string("path\\to\\file") == ~s("path\\\\to\\\\file")
    end

    test "escapes newlines" do
      assert SPARQLQueries.escape_string("line1\nline2") == ~s("line1\\nline2")
    end

    test "escapes carriage returns" do
      assert SPARQLQueries.escape_string("line1\rline2") == ~s("line1\\rline2")
    end

    test "escapes tabs" do
      assert SPARQLQueries.escape_string("col1\tcol2") == ~s("col1\\tcol2")
    end

    test "handles nil" do
      assert SPARQLQueries.escape_string(nil) == ~s("")
    end

    test "handles empty string" do
      assert SPARQLQueries.escape_string("") == ~s("")
    end

    test "handles normal strings" do
      assert SPARQLQueries.escape_string("hello world") == ~s("hello world")
    end
  end

  describe "extract_memory_id/1" do
    test "extracts ID from full IRI" do
      iri = "https://jido.ai/ontology#memory_abc123"
      assert SPARQLQueries.extract_memory_id(iri) == "abc123"
    end

    test "extracts ID from short form" do
      assert SPARQLQueries.extract_memory_id("memory_abc123") == "abc123"
    end

    test "returns original if no pattern matches" do
      assert SPARQLQueries.extract_memory_id("abc123") == "abc123"
    end
  end

  describe "extract_session_id/1" do
    test "extracts ID from full IRI" do
      iri = "https://jido.ai/ontology#session_xyz789"
      assert SPARQLQueries.extract_session_id(iri) == "xyz789"
    end

    test "extracts ID from short form" do
      assert SPARQLQueries.extract_session_id("session_xyz789") == "xyz789"
    end
  end
end
