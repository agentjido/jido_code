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

  @control_plane_ns "https://jido.run/ontology/control-plane#"
  @owl_class_iri RDF.iri("http://www.w3.org/2002/07/owl#Class")
  @owl_datatype_property_iri RDF.iri("http://www.w3.org/2002/07/owl#DatatypeProperty")

  @current_product_classes %{
    control: ~w(ManagedRepo SourceRepo),
    operations: ~w(Intake ExternalObject Event Observation Assessment WorkItem),
    governance: ~w(Evidence ChangeRequest Decision PolicySet ReviewPolicy RepoPosture PostureCheck),
    orchestration: ~w(Run WorkflowRun ExecutionProfile),
    conversations: ~w(Conversation ConversationEvent ConversationSnapshot),
    execution_runtime: ~w(ExecutionWorkflow SandboxSession RuntimeEvent Checkpoint ExecSession SpriteSpec),
    accounts: ~w(AccountRecord User UserIdentity ApiKey Token),
    auth_providers: ~w(ProviderConfig),
    github: ~w(GitHubRepo WebhookDelivery IssueAnalysis),
    security: ~w(SecurityRecord SecretRef SecretLifecycleAudit),
    setup: ~w(SystemConfig),
    legacy: ~w(Project WorkflowRun)
  }

  @shared_predicates ~w(
    recordId recordKind recordStatus insertedAt updatedAt metadataJson payloadJson
    recordLabel displayName sourceKind sourceKey provider providerHost externalId
    canonicalKey canonicalReference title summary priority occurredAt
  )

  @forbidden_secret_predicates ~w(
    plaintext ciphertext hashedPassword apiKeyHash tokenValue webhookSecret privateKey
    rawLlmResponse output
  )

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

  test "control-plane ontology covers current product record families" do
    assert {:ok, graph} = RDF.Turtle.read_file(MemoryGraph.control_plane_ontology_path())

    Enum.each(@current_product_classes, fn {_family, class_names} ->
      Enum.each(class_names, fn class_name ->
        assert ontology_class?(graph, class_name), "#{class_name} is missing from the control-plane ontology"
      end)
    end)
  end

  test "control-plane ontology keeps previous-era concepts explicit" do
    source = File.read!(MemoryGraph.control_plane_ontology_path())

    assert source =~ "A legacy project record retained for compatibility"
    assert source =~ "A previous-era workflow run record retained as compatibility input"
  end

  test "control-plane ontology defines shared bounded projection predicates" do
    assert {:ok, graph} = RDF.Turtle.read_file(MemoryGraph.control_plane_ontology_path())

    Enum.each(@shared_predicates, fn predicate_name ->
      assert datatype_property?(graph, predicate_name),
             "#{predicate_name} is missing as a shared control-plane datatype predicate"
    end)
  end

  test "control-plane ontology documents sensitive projection exclusions" do
    assert {:ok, graph} = RDF.Turtle.read_file(MemoryGraph.control_plane_ontology_path())
    source = File.read!(MemoryGraph.control_plane_ontology_path())

    assert source =~ "API key projection excludes raw key material and key hashes"
    assert source =~ "Token projection excludes bearer token values"
    assert source =~ "GitHub repository projection excludes webhook secrets"
    assert source =~ "Secret reference projection excludes plaintext values, ciphertext"
    assert source =~ "unbounded command output is intentionally excluded"
    assert source =~ "Raw secrets, ciphertext, key hashes, private keys, bearer tokens"

    Enum.each(@forbidden_secret_predicates, fn predicate_name ->
      refute datatype_property?(graph, predicate_name),
             "#{predicate_name} must not be modeled as a semantic projection predicate"
    end)
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

  defp ontology_class?(graph, class_name) do
    RDF.Graph.include?(graph, {control_plane_iri(class_name), RDF.type(), @owl_class_iri})
  end

  defp datatype_property?(graph, predicate_name) do
    RDF.Graph.include?(
      graph,
      {control_plane_iri(predicate_name), RDF.type(), @owl_datatype_property_iri}
    )
  end

  defp control_plane_iri(name), do: RDF.iri(@control_plane_ns <> name)
end
