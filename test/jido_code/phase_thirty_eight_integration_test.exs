defmodule JidoCode.PhaseThirtyEightIntegrationTest do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias TripleStore.QuadOperations

  setup do
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, true)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    workspace_path = create_workspace_path!("ExamplePhaseThirtyEight")

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "38.3.2.1 validation checks ontology pair, typed governed links, and graph coherence together", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-38-#{System.unique_integer([:positive])}"
    revision = "phase-38-typed"

    assert {:ok, _source_graph} =
             AgentWorkspace.load_source_code_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    seed_typed_governed_memory_graph!(managed_repo_id, workspace_path, revision)

    assert {:ok, validate_result} =
             AgentWorkspace.validate_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert validate_result.status == :memory_graph_validated
    assert validate_result.semantic_model.state == :typed_governed_references
    assert validate_result.semantic_model.ontology_pair.complete? == true
    assert validate_result.semantic_model.ontology_pair.memory.complete? == true
    assert validate_result.semantic_model.ontology_pair.workflow_provenance.complete? == true
    assert validate_result.semantic_model.typed_governed_link_count > 0
    assert validate_result.semantic_model.legacy_governed_artifact_count == 0
    assert validate_result.semantic_model.rebuild_required? == false
    assert validate_result.latest_failure == nil

    assert {:ok, status_result} =
             AgentWorkspace.memory_graph_status(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert status_result.ready? == true
    assert status_result.state == :ready
    assert status_result.cross_graph.consistency.state == :aligned
    assert status_result.feedback.detail =~ "bounded recall and capture"
  end

  test "38.3.2.2 missing ontology-pair state remains explainable and recoverable", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-38-ontology-#{System.unique_integer([:positive])}"
    revision = "phase-38-ontology-pair"

    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    replace_with_non_ontology_graphs!(managed_repo_id, workspace_path)

    assert {:ok, validate_result} =
             AgentWorkspace.validate_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert validate_result.status == :memory_graph_recovery_required
    assert validate_result.semantic_model.state == :ontology_pair_incomplete
    assert validate_result.semantic_model.ontology_pair.complete? == false
    assert validate_result.latest_failure.kind == :memory_graph_ontology_pair_incomplete

    assert {:ok, status_result} =
             AgentWorkspace.memory_graph_status(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert status_result.state == :failed
    assert status_result.recovery_action == :recover
    assert status_result.feedback.detail =~ "companion ontology pair"
    assert status_result.feedback.remediation =~ "revalidate typed governed links"

    assert {:ok, recovery_result} =
             AgentWorkspace.recover_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert recovery_result.recovery_action == :recover
    assert recovery_result.graph_status.ready? == true
    assert recovery_result.graph_status.semantic_model.ontology_pair.complete? == true
    assert recovery_result.graph_status.semantic_model.rebuild_required? == false
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "38.3.2.3 legacy governed-artifact recovery guidance and docs stay aligned", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-38-legacy-#{System.unique_integer([:positive])}"
    revision = "phase-38-legacy"

    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    inject_legacy_governed_artifact!(managed_repo_id, workspace_path)

    assert {:ok, validate_result} =
             AgentWorkspace.validate_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert validate_result.status == :memory_graph_recovery_required
    assert validate_result.latest_failure.kind == :memory_graph_semantic_cutover_required
    assert validate_result.semantic_model.legacy_governed_artifact_count > 0

    assert {:ok, status_result} =
             AgentWorkspace.memory_graph_status(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert status_result.state == :failed
    assert status_result.recovery_action == :recover
    assert status_result.feedback.detail =~ "legacy governed artifact links"
    assert status_result.feedback.remediation =~ "typed governed references"

    assert {:ok, recovery_result} =
             AgentWorkspace.recover_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert recovery_result.recovery_action == :recover
    assert recovery_result.result.store.reset_store? == true
    assert recovery_result.graph_status.semantic_model.legacy_governed_artifact_count == 0
    assert recovery_result.graph_status.semantic_model.state == :typed_governed_references

    assert_file_contains!(
      repo_path("README.md"),
      [
        "companion ontology pair",
        "typed `governed_references`",
        "governed truth still lives in Ash-backed control-plane records"
      ]
    )

    assert_file_contains!(
      repo_path("CONTRIBUTING.md"),
      [
        "typed `governed_references` directly",
        "legacy recovery-only store",
        "the companion ontology pair is present"
      ]
    )

    assert_file_contains!(
      repo_path(".spec/README.md"),
      [
        "Ash-backed governed truth",
        "typed governed references as the default semantic contract"
      ]
    )

    assert_file_contains!(
      repo_path(".spec/topology.md"),
      [
        "companion ontology pair",
        "generic artifact-style governed links remain legacy recovery-only state"
      ]
    )

    assert_file_contains!(
      repo_path(".spec/specs/developer_workflow.spec.md"),
      [
        "\"memory.verify\": \\[",
        "ontology pair",
        "governed_references"
      ]
    )

    assert_file_contains!(
      repo_path(".spec/specs/package_quality_standards.spec.md"),
      [
        "companion ontology pair",
        "typed governed-reference cutover"
      ]
    )

    assert_file_contains!(
      repo_path(".spec/specs/memory_graph.spec.md"),
      [
        "validates the ontology pair, typed governed links, and repository-local graph coherence together",
        "typed governed-reference contract"
      ]
    )
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_thirty_eight_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyEightWorkspace.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_eight_workspace, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_eight_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end

  defp seed_typed_governed_memory_graph!(managed_repo_id, workspace_path, revision) do
    session_id = "phase-38-session-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight",
                 workflow: :review,
                 work_item_id: "work-38",
                 revision: revision,
                 goal: "Seed validation coverage for phase 38."
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _plan_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.plan(
                 id: "phase-38-plan",
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight",
                 workflow: :review,
                 work_item_id: "work-38",
                 revision: revision,
                 content: "Repository memory verification should stay explainable.",
                 governed_references: [
                   %{kind: :run, id: "run-38"},
                   %{kind: :work_item, id: "work-38"}
                 ]
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 id: "phase-38-memory",
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight",
                 workflow: :review,
                 work_item_id: "work-38",
                 revision: revision,
                 content: "Phase 38 validation should preserve typed governed links.",
                 rationale: "Verification should trust typed governed references after the ontology pair loads.",
                 decision_status: :accepted,
                 governed_references: [
                   %{kind: :run, id: "run-38"},
                   %{kind: :decision, id: "decision-38"}
                 ],
                 classification: %{
                   source: "phase_thirty_eight_integration",
                   reason: "Integration coverage needs typed governed validation state."
                 }
               ),
               revision: revision
             )
  end

  defp replace_with_non_ontology_graphs!(managed_repo_id, workspace_path) do
    store_path = MemoryGraph.graph_store_path(workspace_path)
    memory_graph = MemoryGraph.memory_named_graph_resource()
    workflow_graph = MemoryGraph.workflow_provenance_named_graph_resource()

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      {:ok, _count} = QuadOperations.clear_graph(store.db, store.dict_manager, memory_graph)
      {:ok, _count} = QuadOperations.clear_graph(store.db, store.dict_manager, workflow_graph)

      memory_resource_iri = RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}fact/no-ontology-pair")

      workflow_resource_iri =
        RDF.iri("#{MemoryGraph.workflow_provenance_base_iri(managed_repo_id)}plan/no-ontology-pair")

      memory_only_graph =
        RDF.Graph.new([
          {memory_resource_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Fact")},
          {memory_resource_iri, RDF.iri("https://jido.run/ontology/memory#content"), "Missing ontology pair fixture"}
        ])

      workflow_only_graph =
        RDF.Graph.new([
          {workflow_resource_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Plan")},
          {workflow_resource_iri, RDF.iri("https://jido.run/ontology/memory#content"), "Missing ontology pair fixture"}
        ])

      {:ok, _count} = TripleStore.load_graph(store, memory_only_graph, graph: memory_graph)
      {:ok, _count} = TripleStore.load_graph(store, workflow_only_graph, graph: workflow_graph)
    after
      :ok = TripleStore.close(store)
    end
  end

  defp inject_legacy_governed_artifact!(managed_repo_id, workspace_path) do
    store_path = MemoryGraph.graph_store_path(workspace_path)
    legacy_memory_iri = RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}fact/legacy-governed-artifact")
    legacy_artifact_iri = MemoryGraph.artifact_iri(managed_repo_id, "run_id/run-legacy")

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      graph =
        RDF.Graph.new([
          {legacy_memory_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Fact")},
          {legacy_memory_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Memory")},
          {legacy_artifact_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#EvidenceArtifact")},
          {legacy_memory_iri, RDF.iri("https://jido.run/ontology/memory#supportedBy"), legacy_artifact_iri}
        ])

      {:ok, _triple_count} =
        TripleStore.load_graph(store, graph, graph: MemoryGraph.memory_named_graph_resource())
    after
      :ok = TripleStore.close(store)
    end
  end

  defp assert_file_contains!(path, snippets) do
    contents = File.read!(path)

    Enum.each(snippets, fn snippet ->
      assert contents =~ snippet
    end)
  end

  defp repo_path(relative_path) do
    Path.expand(Path.join([__DIR__, "..", "..", relative_path]))
  end
end
