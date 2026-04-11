defmodule JidoCode.PhaseThirtySixIntegrationTest do
  # covers: architecture.memory_capture_plane.product_and_runtime_callers_emit_capture_envelopes_not_raw_triples
  # covers: architecture.memory_capture_plane.typed_governed_reference_contract_is_canonical
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  # covers: architecture.memory_ontology.memory_and_provenance_link_to_governed_records_through_typed_relations
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph

  @moduletag :integration

  setup do
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!("PhaseThirtySix")

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "36.3.1.1 typed governed relations are written across provenance, durable memory, and update flows", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-36-#{System.unique_integer([:positive])}"
    revision = "phase-36-typed"

    assert {:ok, refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               JidoCode.MemoryGraph.CaptureEnvelope.work_session(
                 session_id: "phase-36-session",
                 actor_id: "system:phase-thirty-six",
                 workflow: :plan,
                 work_item_id: "work-36",
                 revision: revision,
                 goal: "Seed typed governed provenance."
               ),
               revision: revision,
               graph_name: MemoryGraph.workflow_provenance_graph_name()
             )

    assert {:ok, plan_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               JidoCode.MemoryGraph.CaptureEnvelope.plan(
                 id: "phase-36-plan",
                 session_id: "phase-36-session",
                 actor_id: "system:phase-thirty-six",
                 workflow: :plan,
                 work_item_id: "work-36",
                 revision: revision,
                 content: "Plan artifact with governed context.",
                 governed_references: [
                   %{kind: :run, id: "run-36"},
                   %{kind: :work_item, id: "work-36"}
                 ]
               ),
               revision: revision,
               graph_name: MemoryGraph.workflow_provenance_graph_name()
             )

    assert {:ok, memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               JidoCode.MemoryGraph.DurableMemoryEnvelope.fact(
                 id: "phase-36-memory",
                 session_id: "phase-36-session",
                 actor_id: "system:phase-thirty-six",
                 revision: revision,
                 content: "Durable memory with governed links.",
                 confidence: 0.91,
                 classification: %{
                   source: "phase_thirty_six_integration",
                   reason: "Integration-proof memory classification."
                 },
                 governed_references: [
                   %{kind: :run, id: "run-36"},
                   %{kind: :evidence, id: "evidence-36"}
                 ]
               ),
               revision: revision
             )

    assert {:ok, update_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                 memory_iri: memory_result.capture.resource_iri,
                 actor_id: "system:phase-thirty-six",
                 session_id: "phase-36-session",
                 revision: revision,
                 freshness_score: 0.97,
                 governed_references: [
                   %{kind: :run, id: "run-36"},
                   %{kind: :decision, id: "decision-36"}
                 ]
               ),
               revision: revision
             )

    assert {:ok, provenance_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?run ?workItem
               WHERE {
                 <#{plan_result.capture.resource_iri}> jido:aboutRun ?run ;
                   jido:aboutWorkItem ?workItem .
                 ?run a <https://jido.run/ontology/control-plane#Run> .
                 ?workItem a <https://jido.run/ontology/control-plane#WorkItem> .
               }
               """,
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert provenance_query.row_count == 1

    assert {:ok, memory_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?run ?evidence
               WHERE {
                 <#{memory_result.capture.resource_iri}> jido:aboutRun ?run ;
                   jido:aboutEvidence ?evidence .
                 ?run a <https://jido.run/ontology/control-plane#Run> .
                 ?evidence a <https://jido.run/ontology/control-plane#Evidence> .
               }
               """,
               revision: revision
             )

    assert memory_query.row_count == 1

    assert {:ok, update_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?run ?decision
               WHERE {
                 <#{update_result.capture.update_iri}> jido:aboutRun ?run ;
                   jido:aboutDecision ?decision .
                 ?decision a <https://jido.run/ontology/control-plane#Decision> .
               }
               """,
               revision: revision
             )

    assert update_query.row_count == 1

    assert {:ok, not_artifact_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_id,
               workspace_path,
               """
               SELECT ?evidence
               WHERE {
                 <#{memory_result.capture.resource_iri}> jido:aboutEvidence ?evidence .
                 ?evidence a jido:EvidenceArtifact .
               }
               """,
               revision: revision
             )

    assert not_artifact_query.row_count == 0
    assert refresh_result.latest_validation_status.graph_name == MemoryGraph.memory_graph_name()
  end

  test "36.3.2.1 legacy governed artifact state is detected and bounded recovery preserves named-graph topology", %{
    workspace_path: workspace_path
  } do
    managed_repo_id = "repo-36-legacy-#{System.unique_integer([:positive])}"
    revision = "phase-36-legacy"

    assert {:ok, refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert refresh_result.named_graph_iris == MemoryGraph.named_graph_iris()

    inject_legacy_governed_artifact!(managed_repo_id, workspace_path)

    assert {:ok, validate_result} =
             AgentWorkspace.validate_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert validate_result.status == :memory_graph_recovery_required
    assert validate_result.semantic_model.legacy_governed_artifact_count > 0
    assert validate_result.latest_failure.kind == :memory_graph_semantic_cutover_required

    assert {:ok, status_result} =
             AgentWorkspace.memory_graph_status(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    assert status_result.semantic_model.rebuild_required? == true
    assert status_result.recovery_action == :recover
    assert status_result.named_graph_iri == MemoryGraph.memory_named_graph_iri()

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
    assert recovery_result.graph_status.ready? == true

    assert MemoryGraph.named_graph_iris() == %{
             memory: "https://jido.run/graphs/memory",
             workflow_provenance: "https://jido.run/graphs/workflow_provenance"
           }
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_thirty_six_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtySixWorkspace.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_six_workspace, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
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
end
