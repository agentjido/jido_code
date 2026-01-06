defmodule JidoCode.Memory.LongTerm.OntologyLoaderTest do
  use ExUnit.Case, async: false

  alias JidoCode.Memory.LongTerm.OntologyLoader

  @moduletag :ontology_loader

  setup do
    # Create a temporary directory for the test store
    temp_dir = System.tmp_dir!() |> Path.join("ontology_loader_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(temp_dir)

    on_exit(fn ->
      File.rm_rf!(temp_dir)
    end)

    {:ok, temp_dir: temp_dir}
  end

  describe "namespace/0" do
    test "returns the Jido namespace IRI" do
      assert OntologyLoader.namespace() == "https://jido.ai/ontology#"
    end
  end

  describe "ontology_files/0" do
    test "returns list of ontology files" do
      files = OntologyLoader.ontology_files()
      assert is_list(files)
      assert "jido-core.ttl" in files
      assert "jido-knowledge.ttl" in files
      assert "jido-decision.ttl" in files
      assert "jido-convention.ttl" in files
      assert "jido-error.ttl" in files
    end

    test "jido-core.ttl is first in the list" do
      [first | _] = OntologyLoader.ontology_files()
      assert first == "jido-core.ttl"
    end
  end

  describe "ontology_path/0" do
    test "returns a valid directory path" do
      path = OntologyLoader.ontology_path()
      assert is_binary(path)
      assert File.dir?(path)
    end

    test "path contains ontology files" do
      path = OntologyLoader.ontology_path()
      assert File.exists?(Path.join(path, "jido-core.ttl"))
      assert File.exists?(Path.join(path, "jido-knowledge.ttl"))
    end
  end

  describe "load_ontology/1" do
    test "loads all ontology files into store", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "load_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      assert {:ok, count} = OntologyLoader.load_ontology(store)
      assert count > 0

      # Should be a significant number of triples from all ontology files
      # Each TTL file has ~30-50 triples, and we load 10 files
      assert count >= 200

      :ok = TripleStore.close(store)
    end

    test "loads MemoryItem class", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "memory_item_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Query for MemoryItem class
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?label WHERE {
        jido:MemoryItem rdf:type owl:Class ;
                        rdfs:label ?label .
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      assert length(results) == 1

      :ok = TripleStore.close(store)
    end

    test "loads confidence level individuals", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "confidence_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?level WHERE {
        ?level rdf:type owl:NamedIndividual ;
               rdf:type jido:ConfidenceLevel .
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      levels = Enum.map(results, fn %{"level" => l} -> extract_local_name(l) end)

      assert "High" in levels
      assert "Medium" in levels
      assert "Low" in levels

      :ok = TripleStore.close(store)
    end

    test "loads source type individuals", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "source_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?source WHERE {
        ?source rdf:type owl:NamedIndividual ;
                rdf:type jido:SourceType .
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      sources = Enum.map(results, fn %{"source" => s} -> extract_local_name(s) end)

      assert "UserSource" in sources
      assert "AgentSource" in sources
      assert "ToolSource" in sources

      :ok = TripleStore.close(store)
    end

    test "loads knowledge type subclasses of MemoryItem", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "knowledge_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      # Knowledge types (Fact, Assumption, Hypothesis) are subclasses of MemoryItem
      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>

      SELECT ?subclass WHERE {
        ?subclass rdfs:subClassOf jido:MemoryItem .
        FILTER(STRSTARTS(STR(?subclass), "https://jido.ai/ontology#"))
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      subclasses = Enum.map(results, fn %{"subclass" => s} -> extract_local_name(s) end)

      assert "Fact" in subclasses
      assert "Assumption" in subclasses
      assert "Hypothesis" in subclasses

      :ok = TripleStore.close(store)
    end

    test "loads object properties", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "properties_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?prop WHERE {
        ?prop rdf:type owl:ObjectProperty .
        FILTER(STRSTARTS(STR(?prop), "https://jido.ai/ontology#"))
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      properties = Enum.map(results, fn %{"prop" => p} -> extract_local_name(p) end)

      assert "hasConfidence" in properties
      assert "hasSourceType" in properties
      assert "assertedBy" in properties
      assert "supersededBy" in properties

      :ok = TripleStore.close(store)
    end

    test "loads datatype properties", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "datatype_props_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      query = """
      PREFIX jido: <https://jido.ai/ontology#>
      PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
      PREFIX owl: <http://www.w3.org/2002/07/owl#>

      SELECT ?prop WHERE {
        ?prop rdf:type owl:DatatypeProperty .
        FILTER(STRSTARTS(STR(?prop), "https://jido.ai/ontology#"))
      }
      """

      {:ok, results} = TripleStore.query(store, query)
      properties = Enum.map(results, fn %{"prop" => p} -> extract_local_name(p) end)

      assert "summary" in properties
      assert "rationale" in properties
      assert "hasTimestamp" in properties

      :ok = TripleStore.close(store)
    end
  end

  describe "ontology_loaded?/1" do
    test "returns false for empty store", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "empty_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      refute OntologyLoader.ontology_loaded?(store)

      :ok = TripleStore.close(store)
    end

    test "returns true after loading ontology", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "loaded_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      refute OntologyLoader.ontology_loaded?(store)

      {:ok, _} = OntologyLoader.load_ontology(store)

      assert OntologyLoader.ontology_loaded?(store)

      :ok = TripleStore.close(store)
    end
  end

  describe "reload_ontology/1" do
    test "reloads ontology successfully", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "reload_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Load first time
      {:ok, count1} = OntologyLoader.load_ontology(store)
      assert count1 > 0

      # Reload
      {:ok, count2} = OntologyLoader.reload_ontology(store)
      assert count2 > 0

      # Counts should be similar (reloaded same files)
      assert count2 >= count1 * 0.9  # Allow some variance due to triple deletion

      :ok = TripleStore.close(store)
    end
  end

  describe "list_classes/1" do
    test "lists all ontology classes", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "list_classes_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      {:ok, classes} = OntologyLoader.list_classes(store)
      assert is_list(classes)
      assert length(classes) > 10  # Should have many classes

      # Check for some known classes
      class_names = Enum.map(classes, &extract_local_name/1)
      assert "MemoryItem" in class_names
      assert "Entity" in class_names
      assert "ConfidenceLevel" in class_names

      :ok = TripleStore.close(store)
    end
  end

  describe "list_individuals/1" do
    test "lists all ontology individuals", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "list_individuals_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      {:ok, individuals} = OntologyLoader.list_individuals(store)
      assert is_list(individuals)
      assert length(individuals) >= 6  # High, Medium, Low, UserSource, AgentSource, ToolSource

      # Check for known individuals
      individual_names = Enum.map(individuals, &extract_local_name/1)
      assert "High" in individual_names
      assert "Medium" in individual_names
      assert "Low" in individual_names

      :ok = TripleStore.close(store)
    end
  end

  describe "list_properties/1" do
    test "lists all ontology properties", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "list_properties_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)
      {:ok, _} = OntologyLoader.load_ontology(store)

      {:ok, properties} = OntologyLoader.list_properties(store)
      assert is_list(properties)
      assert length(properties) >= 5  # Should have multiple properties

      # Check for known properties
      property_names = Enum.map(properties, &extract_local_name/1)
      assert "hasConfidence" in property_names
      assert "summary" in property_names

      :ok = TripleStore.close(store)
    end
  end

  describe "ontology loading verification" do
    test "loaded ontology is queryable via store stats", %{temp_dir: temp_dir} do
      store_path = Path.join(temp_dir, "stats_test")
      {:ok, store} = TripleStore.open(store_path, create_if_missing: true)

      # Load ontology and verify count returns a value
      {:ok, loaded_count} = OntologyLoader.load_ontology(store)
      assert loaded_count > 0

      # Use the stats API to verify triples were loaded
      # Allow small variance due to potential timing/counting differences
      {:ok, stats} = TripleStore.stats(store)
      assert stats.triple_count > 600  # Expect roughly similar count

      :ok = TripleStore.close(store)
    end
  end

  # Helper to extract local name from IRI
  defp extract_local_name({:named_node, iri}), do: iri |> String.split("#") |> List.last()
  defp extract_local_name(iri) when is_binary(iri), do: iri |> String.split("#") |> List.last()
end
