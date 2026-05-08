defmodule JidoCode.PhaseThirtyFiveIntegrationTest do
  # covers: architecture.memory_ontology.companion_control_plane_ontology_models_governed_records
  # covers: architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
  # covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical
  use ExUnit.Case, async: true

  alias JidoCode.{MemoryGraph, SourceCodeGraph}
  alias JidoCode.MemoryGraph.GovernedReference

  @expected_kinds [
    :managed_repo,
    :event,
    :observation,
    :assessment,
    :work_item,
    :run,
    :evidence,
    :change_request,
    :decision
  ]

  test "35.3.1.1 companion ontology loads alongside coding memory without namespace ambiguity" do
    assert {:ok, memory_graph} = RDF.Turtle.read_file(MemoryGraph.ontology_path())

    assert {:ok, control_plane_graph} =
             RDF.Turtle.read_file(MemoryGraph.control_plane_ontology_path())

    assert RDF.Graph.triple_count(memory_graph) > 0
    assert RDF.Graph.triple_count(control_plane_graph) > 0

    memory_source = File.read!(MemoryGraph.ontology_path())
    control_plane_source = File.read!(MemoryGraph.control_plane_ontology_path())

    assert memory_source =~ "owl:imports <https://jido.run/ontology/control-plane#>"
    assert memory_source =~ "jido:Decision a owl:Class"
    assert memory_source =~ "distinct from the governed control-plane jcp:Decision record"
    assert control_plane_source =~ "jcp:Decision a owl:Class"
    assert control_plane_source =~ "distinct from memory:Decision"
  end

  test "35.3.1.2 canonical governed IRI helpers remain stable for every governed record kind" do
    managed_repo_id = "repo-35"

    assert Enum.sort(GovernedReference.kinds()) == Enum.sort(@expected_kinds)

    normalized =
      Enum.map(@expected_kinds, fn kind ->
        id = if(kind == :managed_repo, do: managed_repo_id, else: "#{kind}-35")

        assert {:ok, reference} =
                 GovernedReference.normalize(managed_repo_id, %{kind: kind, id: id})

        assert reference.kind == kind
        assert reference.id == id
        assert reference.iri == GovernedReference.iri(managed_repo_id, kind, id)
        assert reference.label == GovernedReference.label(kind, id)
        assert String.starts_with?(reference.iri, GovernedReference.base_iri(managed_repo_id))

        reference
      end)

    assert Enum.uniq_by(normalized, & &1.iri) == normalized
  end

  test "35.3.1.3 stronger semantic model keeps the existing three named graphs" do
    graph_names =
      [SourceCodeGraph.graph_name() | MemoryGraph.graph_names()]
      |> Enum.sort()

    assert graph_names == ["memory", "source_code", "workflow_provenance"]
    refute "governance" in graph_names

    assert SourceCodeGraph.named_graph_iri() == "https://jido.run/graphs/source_code"

    assert MemoryGraph.named_graph_iris() == %{
             memory: "https://jido.run/graphs/memory",
             workflow_provenance: "https://jido.run/graphs/workflow_provenance"
           }
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "35.3.2.1 relevant ADRs, specs, and topology stay aligned on the ontology split" do
    assert_file_contains!(
      spec_path("decisions/jido_code.memory_graph_and_coding_memory_ontology_adoption.md"),
      [
        "companion governed control-plane ontology",
        "through typed relations such as `aboutManagedRepo`, `aboutRun`"
      ]
    )

    assert_file_contains!(
      spec_path("decisions/jido_code.memory_capture_plane_and_insertion_seams.md"),
      [
        "contract instead of generic artifact naming",
        "governed product records through one typed governed-reference"
      ]
    )

    assert_file_contains!(
      spec_path("specs/memory_ontology.spec.md"),
      [
        "companion governed control-plane ontology",
        "through typed relations such as `aboutManagedRepo`"
      ]
    )

    assert_file_contains!(
      spec_path("specs/memory_capture_plane.spec.md"),
      [
        "typed governed-reference contract",
        "instead of generic artifact-path semantics"
      ]
    )
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "35.3.2.2 topology stays aligned with semantic planes and product route boundaries" do
    assert_file_contains!(
      spec_path("topology.md"),
      [
        "The stronger semantic model does **not** add a fourth governance graph.",
        "repository-scoped routes and bounded projections"
      ]
    )
  end

  defp assert_file_contains!(path, snippets) do
    contents = File.read!(path)

    Enum.each(snippets, fn snippet ->
      assert contents =~ snippet
    end)
  end

  defp spec_path(relative_path) do
    Path.expand(Path.join([__DIR__, "..", "..", ".spec", relative_path]))
  end
end
