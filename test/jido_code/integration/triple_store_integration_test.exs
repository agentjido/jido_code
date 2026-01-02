defmodule JidoCode.Integration.TripleStoreIntegrationTest do
  @moduledoc """
  Integration tests verifying the triple_store library works correctly
  with the JidoCode memory system.

  These tests verify:
  1. Basic store operations (open, insert, query, close)
  2. Loading TTL ontology files
  3. SPARQL queries against loaded ontology
  """

  use ExUnit.Case, async: false

  @moduletag :integration

  # =============================================================================
  # Helper Functions
  # =============================================================================

  # Extract string value from SPARQL result bindings
  # The triple_store returns tuples like {:named_node, "..."} or {:literal, :simple, "..."}
  defp extract_value({:named_node, iri}), do: iri
  defp extract_value({:literal, :simple, value}), do: value
  defp extract_value({:literal, {:typed, _type}, value}), do: value
  defp extract_value({:literal, {:lang, _lang}, value}), do: value
  defp extract_value(%RDF.IRI{} = iri), do: to_string(iri)
  defp extract_value(value) when is_binary(value), do: value
  defp extract_value(value), do: value

  defp extract_iri_local_name({:named_node, iri}), do: iri |> String.split("#") |> List.last()
  defp extract_iri_local_name(%RDF.IRI{} = iri), do: to_string(iri) |> String.split("#") |> List.last()
  defp extract_iri_local_name(iri) when is_binary(iri), do: iri |> String.split("#") |> List.last()

  # =============================================================================
  # Setup / Teardown
  # =============================================================================

  setup do
    # Create a unique temporary directory for each test
    test_id = :erlang.unique_integer([:positive])
    temp_dir = Path.join(System.tmp_dir!(), "triple_store_test_#{test_id}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      # Clean up after test
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  # =============================================================================
  # 7.1.2.1 - Basic Store Operations
  # =============================================================================

  describe "basic store operations" do
    test "can open, insert, query, and close store", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "basic_test")

      # Open store
      assert {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      assert is_map(store)
      assert Map.has_key?(store, :db)

      # Insert a triple using RDF types
      triple = {
        RDF.iri("http://example.org/subject"),
        RDF.iri("http://example.org/predicate"),
        RDF.iri("http://example.org/object")
      }

      assert {:ok, 1} = TripleStore.insert(store, triple)

      # Query for the triple
      query = "SELECT ?s ?p ?o WHERE { ?s ?p ?o }"
      assert {:ok, results} = TripleStore.query(store, query)
      assert length(results) == 1

      [result] = results
      assert extract_value(result["s"]) == "http://example.org/subject"
      assert extract_value(result["p"]) == "http://example.org/predicate"
      assert extract_value(result["o"]) == "http://example.org/object"

      # Close store
      assert :ok = TripleStore.close(store)
    end

    test "can insert multiple triples", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "multi_insert_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      triples = [
        {RDF.iri("http://ex/a"), RDF.iri("http://ex/type"), RDF.iri("http://ex/Person")},
        {RDF.iri("http://ex/b"), RDF.iri("http://ex/type"), RDF.iri("http://ex/Person")}
      ]

      assert {:ok, 2} = TripleStore.insert(store, triples)

      # Query for all Person types
      query = """
      SELECT ?person
      WHERE {
        ?person <http://ex/type> <http://ex/Person> .
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)
      assert length(results) == 2

      :ok = TripleStore.close(store)
    end

    test "store persists data between open/close cycles", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "persistence_test")

      # First session - insert data
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      triple = {
        RDF.iri("http://ex/persistent"),
        RDF.iri("http://ex/value"),
        RDF.iri("http://ex/persisted")
      }

      {:ok, 1} = TripleStore.insert(store, triple)
      :ok = TripleStore.close(store)

      # Second session - verify data persisted
      {:ok, store2} = TripleStore.open(store_path)

      query = "SELECT ?o WHERE { <http://ex/persistent> <http://ex/value> ?o }"
      assert {:ok, [result]} = TripleStore.query(store2, query)
      assert extract_value(result["o"]) == "http://ex/persisted"

      :ok = TripleStore.close(store2)
    end
  end

  # =============================================================================
  # 7.1.2.2 - Loading TTL Files
  # =============================================================================

  describe "TTL file loading" do
    test "can load a TTL file from ontology directory", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "ttl_load_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Load the core ontology file
      ontology_path = Path.join([
        File.cwd!(),
        "lib/ontology/long-term-context/jido-core.ttl"
      ])

      assert File.exists?(ontology_path), "Ontology file should exist at #{ontology_path}"

      assert {:ok, count} = TripleStore.load(store, ontology_path)
      assert count > 0, "Should have loaded some triples from ontology"

      :ok = TripleStore.close(store)
    end

    test "can load multiple ontology files", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "multi_ttl_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      ontology_dir = Path.join(File.cwd!(), "lib/ontology/long-term-context")

      ontology_files = [
        "jido-core.ttl",
        "jido-knowledge.ttl",
        "jido-decision.ttl"
      ]

      total_loaded =
        Enum.reduce(ontology_files, 0, fn file, acc ->
          path = Path.join(ontology_dir, file)
          {:ok, count} = TripleStore.load(store, path)
          acc + count
        end)

      assert total_loaded > 0, "Should have loaded triples from multiple ontology files"

      :ok = TripleStore.close(store)
    end
  end

  # =============================================================================
  # 7.1.2.3 - SPARQL Queries Against Ontology
  # =============================================================================

  describe "SPARQL queries against loaded ontology" do
    setup %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "sparql_ontology_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Load core and knowledge ontologies
      ontology_dir = Path.join(File.cwd!(), "lib/ontology/long-term-context")

      for file <- ["jido-core.ttl", "jido-knowledge.ttl"] do
        path = Path.join(ontology_dir, file)
        {:ok, _} = TripleStore.load(store, path)
      end

      on_exit(fn ->
        TripleStore.close(store)
      end)

      {:ok, store: store}
    end

    test "can query for MemoryItem class", %{store: store} do
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

      SELECT ?class
      WHERE {
        jido:MemoryItem a ?class .
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)
      assert length(results) > 0, "MemoryItem should be defined in ontology"
    end

    test "can query for knowledge type subclasses", %{store: store} do
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

      SELECT ?subclass
      WHERE {
        ?subclass rdfs:subClassOf jido:MemoryItem .
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)

      subclasses =
        results
        |> Enum.map(& &1["subclass"])
        |> Enum.map(&extract_value/1)

      # Should find at least Fact, Assumption, Hypothesis from jido-knowledge.ttl
      assert Enum.any?(subclasses, &String.contains?(&1, "Fact"))
      assert Enum.any?(subclasses, &String.contains?(&1, "Assumption"))
      assert Enum.any?(subclasses, &String.contains?(&1, "Hypothesis"))
    end

    test "can query for confidence level individuals", %{store: store} do
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

      SELECT ?level
      WHERE {
        ?level rdf:type jido:ConfidenceLevel .
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)

      levels =
        results
        |> Enum.map(& &1["level"])
        |> Enum.map(&extract_value/1)

      # Should find High, Medium, Low
      assert Enum.any?(levels, &String.contains?(&1, "High"))
      assert Enum.any?(levels, &String.contains?(&1, "Medium"))
      assert Enum.any?(levels, &String.contains?(&1, "Low"))
    end

    test "can query for source type individuals", %{store: store} do
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

      SELECT ?source
      WHERE {
        ?source rdf:type jido:SourceType .
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)

      sources =
        results
        |> Enum.map(& &1["source"])
        |> Enum.map(&extract_value/1)

      # Should find UserSource, AgentSource, ToolSource, ExternalDocumentSource
      assert Enum.any?(sources, &String.contains?(&1, "UserSource"))
      assert Enum.any?(sources, &String.contains?(&1, "AgentSource"))
    end

    test "can query ontology properties", %{store: store} do
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?prop
      WHERE {
        ?prop rdf:type owl:ObjectProperty .
        FILTER(STRSTARTS(STR(?prop), "https://jido.ai/ontology#"))
      }
      """

      assert {:ok, results} = TripleStore.query(store, query)

      properties =
        results
        |> Enum.map(& &1["prop"])
        |> Enum.map(&extract_value/1)

      # Should find core properties like hasConfidence, assertedBy
      assert Enum.any?(properties, &String.contains?(&1, "hasConfidence"))
      assert Enum.any?(properties, &String.contains?(&1, "assertedBy"))
    end
  end

  # =============================================================================
  # Additional Integration Tests
  # =============================================================================

  describe "SPARQL UPDATE operations" do
    test "can execute SPARQL INSERT DATA", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "sparql_update_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      update = """
      PREFIX jido: <https://jido.ai/ontology#>

      INSERT DATA {
        jido:memory_test123 jido:summary "Test memory content" .
        jido:memory_test123 a jido:Fact .
      }
      """

      assert {:ok, _} = TripleStore.update(store, update)

      # Verify the data was inserted
      query = """
      PREFIX jido: <https://jido.ai/ontology#>

      SELECT ?summary
      WHERE {
        jido:memory_test123 jido:summary ?summary .
      }
      """

      assert {:ok, [result]} = TripleStore.query(store, query)
      assert extract_value(result["summary"]) == "Test memory content"

      :ok = TripleStore.close(store)
    end

    test "can execute SPARQL DELETE DATA", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "sparql_delete_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # First insert
      insert = """
      PREFIX jido: <https://jido.ai/ontology#>

      INSERT DATA {
        jido:memory_to_delete jido:summary "Will be deleted" .
      }
      """

      {:ok, _} = TripleStore.update(store, insert)

      # Verify insert
      query = "PREFIX jido: <https://jido.ai/ontology#> SELECT ?s WHERE { ?s jido:summary \"Will be deleted\" }"
      {:ok, [_]} = TripleStore.query(store, query)

      # Now delete
      delete = """
      PREFIX jido: <https://jido.ai/ontology#>

      DELETE DATA {
        jido:memory_to_delete jido:summary "Will be deleted" .
      }
      """

      assert {:ok, _} = TripleStore.update(store, delete)

      # Verify deletion
      {:ok, results} = TripleStore.query(store, query)
      assert results == []

      :ok = TripleStore.close(store)
    end
  end

  describe "store health and stats" do
    test "can get store health", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "health_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      assert {:ok, health} = TripleStore.health(store)
      assert health.status in [:healthy, :degraded, :unhealthy]
      assert health.database_open == true

      :ok = TripleStore.close(store)
    end

    test "can get store stats", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "stats_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Insert some data first - using RDF literals for object values
      triples = [
        {RDF.iri("http://ex/a"), RDF.iri("http://ex/p"), RDF.literal("1")},
        {RDF.iri("http://ex/b"), RDF.iri("http://ex/p"), RDF.literal("2")},
        {RDF.iri("http://ex/c"), RDF.iri("http://ex/p"), RDF.literal("3")}
      ]

      {:ok, 3} = TripleStore.insert(store, triples)

      assert {:ok, stats} = TripleStore.stats(store)
      assert is_map(stats)
      assert Map.has_key?(stats, :triple_count)
      assert stats.triple_count >= 3

      :ok = TripleStore.close(store)
    end
  end

  # =============================================================================
  # 7.3.3.5 - SPARQLQueries Integration Tests
  # =============================================================================

  describe "SPARQLQueries integration" do
    alias JidoCode.Memory.LongTerm.SPARQLQueries
    alias JidoCode.Memory.LongTerm.OntologyLoader

    test "insert_memory generates executable SPARQL", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "insert_memory_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Load ontology first so types are defined
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Create a memory to insert
      memory = %{
        id: "test_mem_001",
        content: "This is a test fact about the project",
        memory_type: :fact,
        confidence: :high,
        source_type: :agent,
        session_id: "session_test"
      }

      # Generate and execute the insert query
      insert_query = SPARQLQueries.insert_memory(memory)
      assert {:ok, _} = TripleStore.update(store, insert_query)

      # Verify the memory was inserted by querying for it
      verify_query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>

      SELECT ?content ?confidence WHERE {
        jido:memory_test_mem_001 jido:summary ?content ;
                                  jido:hasConfidence ?confidence .
      }
      """

      {:ok, results} = TripleStore.query(store, verify_query)
      assert length(results) == 1

      result = hd(results)
      assert extract_value(result["content"]) == "This is a test fact about the project"
      assert extract_iri_local_name(result["confidence"]) == "High"

      :ok = TripleStore.close(store)
    end

    test "query_by_session retrieves inserted memories", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "query_session_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Insert multiple memories
      for i <- 1..3 do
        memory = %{
          id: "mem_#{i}",
          content: "Memory content #{i}",
          memory_type: :fact,
          confidence: :high,
          source_type: :agent,
          session_id: "session_abc"
        }

        insert_query = SPARQLQueries.insert_memory(memory)
        {:ok, _} = TripleStore.update(store, insert_query)
      end

      # Query by session
      session_query = SPARQLQueries.query_by_session("session_abc")
      {:ok, results} = TripleStore.query(store, session_query)

      assert length(results) == 3

      :ok = TripleStore.close(store)
    end

    test "query_by_type filters memories by type", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "query_type_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Insert memories of different types
      memories = [
        %{id: "fact_1", content: "A fact", memory_type: :fact, session_id: "s1"},
        %{id: "fact_2", content: "Another fact", memory_type: :fact, session_id: "s1"},
        %{id: "hypo_1", content: "A hypothesis", memory_type: :hypothesis, session_id: "s1"}
      ]

      for memory <- memories do
        insert_query = SPARQLQueries.insert_memory(memory)
        {:ok, _} = TripleStore.update(store, insert_query)
      end

      # Query only facts
      fact_query = SPARQLQueries.query_by_type("s1", :fact)
      {:ok, fact_results} = TripleStore.query(store, fact_query)
      assert length(fact_results) == 2

      # Query only hypotheses
      hypo_query = SPARQLQueries.query_by_type("s1", :hypothesis)
      {:ok, hypo_results} = TripleStore.query(store, hypo_query)
      assert length(hypo_results) == 1

      :ok = TripleStore.close(store)
    end

    test "supersede_memory marks memory as superseded", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "supersede_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Insert old and new memories
      old_memory = %{id: "old_mem", content: "Old content", memory_type: :fact, session_id: "s1"}
      new_memory = %{id: "new_mem", content: "Updated content", memory_type: :fact, session_id: "s1"}

      {:ok, _} = TripleStore.update(store, SPARQLQueries.insert_memory(old_memory))
      {:ok, _} = TripleStore.update(store, SPARQLQueries.insert_memory(new_memory))

      # Supersede old with new
      supersede_query = SPARQLQueries.supersede_memory("old_mem", "new_mem")
      {:ok, _} = TripleStore.update(store, supersede_query)

      # Query should exclude superseded by default
      session_query = SPARQLQueries.query_by_session("s1")
      {:ok, results} = TripleStore.query(store, session_query)
      assert length(results) == 1

      # The remaining result should be the new memory
      result = hd(results)
      assert extract_value(result["content"]) == "Updated content"

      :ok = TripleStore.close(store)
    end

    test "query_by_id retrieves single memory", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "query_by_id_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      memory = %{
        id: "specific_mem",
        content: "Specific content",
        memory_type: :discovery,
        confidence: :medium,
        source_type: :user,
        session_id: "s1",
        rationale: "Found during exploration"
      }

      {:ok, _} = TripleStore.update(store, SPARQLQueries.insert_memory(memory))

      # Query by ID
      id_query = SPARQLQueries.query_by_id("specific_mem")
      {:ok, results} = TripleStore.query(store, id_query)

      assert length(results) == 1
      result = hd(results)
      assert extract_value(result["content"]) == "Specific content"
      assert extract_iri_local_name(result["type"]) == "Discovery"
      assert extract_iri_local_name(result["confidence"]) == "Medium"
      assert extract_iri_local_name(result["source"]) == "UserSource"

      :ok = TripleStore.close(store)
    end

    test "delete_memory soft deletes via supersession", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "delete_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Insert a memory
      memory = %{id: "to_delete", content: "Will be deleted", memory_type: :fact, session_id: "s1"}
      {:ok, _} = TripleStore.update(store, SPARQLQueries.insert_memory(memory))

      # Verify it exists
      session_query = SPARQLQueries.query_by_session("s1")
      {:ok, results_before} = TripleStore.query(store, session_query)
      assert length(results_before) == 1

      # Delete it
      delete_query = SPARQLQueries.delete_memory("to_delete")
      {:ok, _} = TripleStore.update(store, delete_query)

      # Verify it's excluded from queries (soft deleted)
      {:ok, results_after} = TripleStore.query(store, session_query)
      assert length(results_after) == 0

      :ok = TripleStore.close(store)
    end

    test "string escaping prevents SPARQL injection", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "escaping_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Try to insert content with potentially dangerous characters
      memory = %{
        id: "escape_test",
        content: ~s(Content with "quotes" and \\ backslashes and\nnewlines),
        memory_type: :fact,
        session_id: "s1"
      }

      insert_query = SPARQLQueries.insert_memory(memory)
      # This should not crash or cause injection
      assert {:ok, _} = TripleStore.update(store, insert_query)

      # Verify content was stored correctly
      id_query = SPARQLQueries.query_by_id("escape_test")
      {:ok, results} = TripleStore.query(store, id_query)

      assert length(results) == 1
      content = extract_value(hd(results)["content"])
      assert String.contains?(content, "quotes")
      assert String.contains?(content, "backslashes")

      :ok = TripleStore.close(store)
    end
  end
end
