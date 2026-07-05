defmodule JidoCode.ControlPlane.OntologyTopologyIntegrationTest do
  use ExUnit.Case, async: true

  alias JidoCode.ControlPlane.{GraphTopology, SemanticIdentity}
  alias JidoCode.MemoryGraph

  @control_plane_ns "https://jido.run/ontology/control-plane#"
  @memory_ns "https://jido.run/ontology/memory#"
  @owl_class RDF.iri("http://www.w3.org/2002/07/owl#Class")
  @owl_datatype_property RDF.iri("http://www.w3.org/2002/07/owl#DatatypeProperty")

  setup do
    store_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_control_plane_topology_#{System.unique_integer([:positive])}"
      )

    {:ok, store} = TripleStore.open(store_path, create_if_missing: true, schema: :quad)

    on_exit(fn ->
      TripleStore.close(store)
      File.rm_rf!(store_path)
    end)

    {:ok, store: store}
  end

  test "loads memory and control-plane ontologies into the control-plane graph", %{store: store} do
    {:ok, control_plane_graph} = GraphTopology.graph_resource(:control_plane)

    assert {:ok, loaded_count} =
             load_ontology_artifacts(store, control_plane_graph, [
               MemoryGraph.ontology_path(),
               MemoryGraph.control_plane_ontology_path()
             ])

    assert loaded_count > 0

    assert {:ok, %{^control_plane_graph => quad_count}} =
             TripleStore.QuadOperations.graphs_summary(store.db, include_default: false)

    assert quad_count == loaded_count

    assert_quad_exists!(
      store,
      control_plane_graph,
      {control_iri("ManagedRepo"), RDF.type(), @owl_class}
    )

    assert_quad_exists!(
      store,
      control_plane_graph,
      {control_iri("ExecutionWorkflow"), RDF.type(), @owl_class}
    )

    assert_quad_exists!(
      store,
      control_plane_graph,
      {control_iri("payloadJson"), RDF.type(), @owl_datatype_property}
    )

    assert_quad_exists!(
      store,
      control_plane_graph,
      {memory_iri("Memory"), RDF.type(), @owl_class}
    )
  end

  test "topology registry and identity templates are executable contracts", %{store: store} do
    {:ok, control_plane_graph} = GraphTopology.graph_resource(:control_plane)

    {:ok, _loaded_count} =
      load_ontology_artifacts(store, control_plane_graph, [MemoryGraph.control_plane_ontology_path()])

    Enum.each(GraphTopology.graph_names(), fn graph_name ->
      assert {:ok, graph_iri} = GraphTopology.graph_iri(graph_name)
      assert String.starts_with?(graph_iri, "https://jido.run/graphs/")
    end)

    Enum.each(SemanticIdentity.record_types(), fn record_type ->
      assert {:ok, iri} = SemanticIdentity.canonical_iri(record_type, sample_attrs(record_type))
      assert String.starts_with?(iri, SemanticIdentity.base_iri())
      assert {:ok, _graph_name} = GraphTopology.graph_for_record(record_type)
    end)

    Enum.each(forbidden_secret_predicates(), fn predicate_name ->
      refute quad_exists?(
               store,
               control_plane_graph,
               {control_iri(predicate_name), RDF.type(), @owl_datatype_property}
             )
    end)
  end

  defp load_ontology_artifacts(store, named_graph, paths) do
    Enum.reduce_while(paths, {:ok, 0}, fn path, {:ok, total_count} ->
      with {:ok, graph} <- RDF.Turtle.read_file(path),
           {:ok, count} <- TripleStore.load_graph(store, graph, graph: named_graph) do
        {:cont, {:ok, total_count + count}}
      else
        {:error, reason} -> {:halt, {:error, {path, reason}}}
      end
    end)
  end

  defp assert_quad_exists!(store, named_graph, triple) do
    assert quad_exists?(store, named_graph, triple), "expected #{inspect(triple)} in #{named_graph}"
  end

  defp quad_exists?(store, named_graph, {subject, predicate, object}) do
    with {:ok, graph_id} <- TripleStore.Adapter.term_to_id(store.dict_manager, named_graph),
         {:ok, subject_id} <- TripleStore.Adapter.term_to_id(store.dict_manager, subject),
         {:ok, predicate_id} <- TripleStore.Adapter.term_to_id(store.dict_manager, predicate),
         {:ok, object_id} <- TripleStore.Adapter.term_to_id(store.dict_manager, object) do
      TripleStore.QuadOperations.quad_exists?(store.db, {subject_id, predicate_id, object_id, graph_id})
    else
      {:error, _reason} -> false
    end
  end

  defp sample_attrs(:external_object),
    do: %{provider: :github, provider_host: "github.com", object_type: :issue, external_id: "42"}

  defp sample_attrs(:system_config), do: %{key: "singleton"}
  defp sample_attrs(record_type), do: sample_attrs(record_type, SemanticIdentity.record_spec!(record_type))
  defp sample_attrs(record_type, %{scope: :repo_scoped}), do: %{managed_repo_id: "repo-1", id: "#{record_type}-1"}
  defp sample_attrs(record_type, _spec), do: "#{record_type}-1"

  defp forbidden_secret_predicates do
    ~w(plaintext ciphertext hashedPassword apiKeyHash tokenValue webhookSecret privateKey rawLlmResponse output)
  end

  defp control_iri(local), do: RDF.iri(@control_plane_ns <> local)
  defp memory_iri(local), do: RDF.iri(@memory_ns <> local)
end
