defmodule JidoCode.PhaseThirtyIntegrationTest do
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: architecture.memory_capture_plane.transient_llm_output_is_not_inserted_as_memory_without_adoption
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_ontology.change_and_revision_provenance_is_explicit
  # covers: architecture.memory_ontology.decision_structure_supports_supersession_and_consequence
  # covers: architecture.memory_ontology.freshness_evidence_and_validation_metadata_are_explicit
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.MemoryGraph
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.{GovernedAdoption, ProductService, WorkflowService}

  @moduletag :integration

  setup do
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  describe "30.3.1 Durable memory adoption scenarios" do
    test "30.3.1.1 transient workflow output does not become durable memory until explicitly adopted", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()
      work_item_id = "work-#{System.unique_integer([:positive])}"
      revision = "rev-30-adoption"

      assert {:ok, _source_graph} =
               AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, _memory_graph} =
               AgentWorkspace.refresh_memory_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, plan_result} =
               WorkflowService.plan(
                 managed_repo.id,
                 work_item_id,
                 "Plan with semantic context before durable memory adoption",
                 workspace_path: workspace_path,
                 semantic: [
                   workspace_path: workspace_path,
                   prepare: :none,
                   revision: revision,
                   functions: [module_name: "ExampleWorkspace", function_name: "greet"]
                 ]
               )

      assert {:ok, transient_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?session
                 WHERE {
                   ?session jido:sessionId "#{plan_result.workflow_provenance.session_id}" .
                 }
                 """,
                 graph_name: "memory",
                 revision: revision,
                 allow_stale?: true
               )

      assert transient_query.row_count == 0

      assert {:ok, projection} =
               ProductService.functions(
                 managed_repo.id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 function_name: "greet",
                 revision: revision
               )

      assert {:ok, workflow_memory} =
               WorkflowService.record_memory(
                 projection,
                 actor_id: "system:phase-thirty-memory",
                 workspace_path: workspace_path,
                 work_item_id: work_item_id,
                 query: %{module_name: "ExampleWorkspace", function_name: "greet"},
                 memory_kind: :pattern,
                 classification_reason: "The workflow intentionally adopted a reusable greeting pattern.",
                 content: "ExampleWorkspace.greet/1 is the canonical greeting entry point."
               )

      assert workflow_memory.record.status == :durable_memory_recorded

      assert {:ok, workflow_memory_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?memory ?session ?function
                 WHERE {
                   ?memory jido:content "ExampleWorkspace.greet/1 is the canonical greeting entry point." ;
                     jido:sourceSession ?session ;
                     jido:aboutFunction ?function .
                 }
                 """,
                 revision: revision,
                 allow_stale?: true
               )

      assert workflow_memory_query.row_count == 1

      assert {:ok, governed_memory} =
               GovernedAdoption.adopt_memory(
                 projection,
                 actor_id: "system:phase-thirty-memory",
                 workspace_path: workspace_path,
                 work_item_id: work_item_id,
                 observation_id: "observation-30-#{System.unique_integer([:positive])}",
                 query: %{module_name: "ExampleWorkspace", function_name: "greet"},
                 memory_kind: :known_issue,
                 classification_reason: "Governed review adopted the finding as a durable known issue.",
                 content: "Greeting contract changes require governed review."
               )

      assert governed_memory.record.status == :durable_memory_recorded

      assert {:ok, governed_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?memory ?artifact
                 WHERE {
                   ?memory a jido:KnownIssue ;
                     jido:content "Greeting contract changes require governed review." ;
                     jido:evidenceArtifact ?artifact .
                 }
                 """,
                 revision: revision,
                 allow_stale?: true
               )

      assert governed_query.row_count >= 1
    end
  end

  describe "30.3.2 Freshness and invalidation scenarios" do
    test "30.3.2.1 validation and later invalidation remain explicit on durable memory", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()
      work_item_id = "work-#{System.unique_integer([:positive])}"
      revision = "rev-30-validation"

      assert {:ok, _source_graph} =
               AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, _memory_graph} =
               AgentWorkspace.refresh_memory_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, projection} =
               ProductService.functions(
                 managed_repo.id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 function_name: "greet",
                 revision: revision
               )

      assert {:ok, workflow_memory} =
               WorkflowService.record_memory(
                 projection,
                 actor_id: "system:phase-thirty-validation",
                 workspace_path: workspace_path,
                 work_item_id: work_item_id,
                 query: %{module_name: "ExampleWorkspace", function_name: "greet"},
                 memory_kind: :fact,
                 classification_reason: "The workflow explicitly adopted a durable fact.",
                 content: "ExampleWorkspace.greet/1 currently accepts a single binary argument.",
                 confidence: 0.9
               )

      assert {:ok, validation_result} =
               AgentWorkspace.record_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_validation(
                   memory_iri: workflow_memory.record.capture.resource_iri,
                   actor_id: "system:test",
                   session_id: workflow_memory.session_id,
                   revision: revision,
                   freshness_score: 0.98,
                   test_run: %{id: "mix-test-phase-thirty", label: "mix test"}
                 ),
                 revision: revision
               )

      assert validation_result.status == :durable_memory_validated

      assert {:ok, validated_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?score ?validatedAt ?testRun
                 WHERE {
                   <#{workflow_memory.record.capture.resource_iri}> jido:freshnessScore ?score ;
                     jido:lastValidatedAt ?validatedAt ;
                     jido:validatedByTestRun ?testRun .
                 }
                 """,
                 revision: revision,
                 allow_stale?: true
               )

      assert validated_query.row_count == 1
      assert get_in(List.first(validated_query.bindings), ["score", :lexical]) == "0.98"

      rewrite_workspace_module!(workspace_path, "ExampleWorkspaceUpdated")
      {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
      updated_revision = revision_metadata.current_revision

      assert {:ok, invalidation_result} =
               AgentWorkspace.record_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.memory_invalidation(
                   memory_iri: workflow_memory.record.capture.resource_iri,
                   actor_id: "system:test",
                   session_id: workflow_memory.session_id,
                   revision: updated_revision,
                   stale_reason: :workspace_revision_changed
                 ),
                 revision: updated_revision
               )

      assert invalidation_result.status == :durable_memory_invalidated

      assert {:ok, invalidated_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?revision ?reason
                 WHERE {
                   <#{workflow_memory.record.capture.resource_iri}> jido:invalidatedByRevision ?revision ;
                     jido:staleReason ?reason .
                 }
                 """,
                 revision: updated_revision,
                 allow_stale?: true
               )

      assert invalidated_query.row_count == 1
      assert get_in(List.first(invalidated_query.bindings), ["reason", :value]) == "workspace_revision_changed"
    end

    test "30.3.2.2 superseded decisions remain queryable instead of silently disappearing", %{
      workspace_path: workspace_path
    } do
      managed_repo = create_managed_repo!()
      work_item_id = "work-#{System.unique_integer([:positive])}"
      revision = "rev-30-supersession"

      assert {:ok, _source_graph} =
               AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, _memory_graph} =
               AgentWorkspace.refresh_memory_graph(managed_repo.id, workspace_path, revision: revision)

      assert {:ok, projection} =
               ProductService.impact(
                 managed_repo.id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 revision: revision
               )

      assert {:ok, prior_decision} =
               WorkflowService.record_memory(
                 projection,
                 actor_id: "system:phase-thirty-decision",
                 workspace_path: workspace_path,
                 work_item_id: work_item_id,
                 query: %{module_name: "ExampleWorkspace"},
                 memory_kind: :decision,
                 classification_reason: "The workflow explicitly adopted the prior decision.",
                 content: "Keep the original greeting contract wording.",
                 rationale: "It matched the current API."
               )

      assert {:ok, newer_decision} =
               WorkflowService.record_memory(
                 projection,
                 actor_id: "system:phase-thirty-decision",
                 workspace_path: workspace_path,
                 work_item_id: work_item_id,
                 query: %{module_name: "ExampleWorkspace"},
                 memory_kind: :decision,
                 classification_reason: "The workflow explicitly adopted the newer decision.",
                 content: "Document the stronger greeting contract wording.",
                 rationale: "The repo now treats this as the preferred wording."
               )

      assert {:ok, supersession_result} =
               AgentWorkspace.record_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 JidoCode.MemoryGraph.DurableMemoryUpdateEnvelope.decision_supersession(
                   memory_iri: newer_decision.record.capture.resource_iri,
                   superseded_memory_iri: prior_decision.record.capture.resource_iri,
                   actor_id: "system:test",
                   session_id: newer_decision.session_id,
                   revision: revision
                 ),
                 revision: revision
               )

      assert supersession_result.status == :durable_memory_superseded

      assert {:ok, prior_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?status
                 WHERE {
                   <#{prior_decision.record.capture.resource_iri}> jido:decisionStatus ?status .
                 }
                 """,
                 revision: revision,
                 allow_stale?: true
               )

      assert Enum.any?(prior_query.bindings, fn row ->
               get_in(row, ["status", :value]) == "https://jido.run/ontology/memory#superseded"
             end)

      assert {:ok, current_query} =
               AgentWorkspace.query_memory_graph(
                 managed_repo.id,
                 workspace_path,
                 """
                 SELECT ?prior
                 WHERE {
                   <#{newer_decision.record.capture.resource_iri}> jido:supersedes ?prior .
                 }
                 """,
                 revision: revision,
                 allow_stale?: true
               )

      assert current_query.row_count == 1
      assert get_in(List.first(current_query.bindings), ["prior", :value]) == prior_decision.record.capture.resource_iri
    end
  end

  defp create_managed_repo! do
    name = "phase-30-integration-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirty.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule ExampleWorkspace do
        def greet(name) when is_binary(name), do: "hello \#{name}"
      end
      """
    )

    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello \#{name}"
      end
      """
    )
  end
end
