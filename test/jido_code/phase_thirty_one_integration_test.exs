defmodule JidoCode.PhaseThirtyOneIntegrationTest do
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_supports_cross_graph_provenance
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: architecture.memory_graph.cross_graph_consistency_and_isolation_are_explainable
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  # covers: architecture.memory_capture_plane.workflow_provenance_is_inserted_at_workspace_and_workflow_boundaries
  # covers: architecture.memory_capture_plane.durable_memories_are_inserted_through_explicit_classification_and_adoption
  # covers: architecture.memory_capture_plane.validation_and_invalidation_follow_revision_and_test_evidence
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.{ProductService, WorkflowService}

  @moduletag :integration

  setup do
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path_one = create_workspace_path!("PhaseThirtyOneOne")
    workspace_path_two = create_workspace_path!("PhaseThirtyOneTwo")

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      File.rm_rf!(workspace_path_one)
      File.rm_rf!(workspace_path_two)
    end)

    {:ok, workspace_path_one: workspace_path_one, workspace_path_two: workspace_path_two}
  end

  test "31.3.1.1 memory recovery remains explicit across workspace and workflow boundaries", %{
    workspace_path_one: workspace_path
  } do
    managed_repo = create_managed_repo!("phase-31-recovery")
    revision = "phase-31-recovery-rev"
    work_item_id = "work-#{System.unique_integer([:positive])}"

    assert {:ok, _source_graph} =
             AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path, revision: revision)

    assert {:ok, _memory_graph} =
             AgentWorkspace.refresh_memory_graph(managed_repo.id, workspace_path, revision: revision)

    assert {:ok, projection} =
             ProductService.functions(
               managed_repo.id,
               workspace_path,
               module_name: "PhaseThirtyOneOne",
               function_name: "greet",
               revision: revision
             )

    assert {:ok, invalidation_result} =
             AgentWorkspace.invalidate_memory_graph(
               managed_repo.id,
               workspace_path,
               revision: revision,
               reason: :manual_invalidation
             )

    assert invalidation_result.feedback.state == :invalidated
    assert invalidation_result.feedback.recovery.action == :validate

    assert {:ok, workflow_memory} =
             WorkflowService.record_memory(
               projection,
               actor_id: "system:phase-thirty-one",
               workspace_path: workspace_path,
               work_item_id: work_item_id,
                query: %{module_name: "PhaseThirtyOneOne", function_name: "greet"},
                memory_kind: :fact,
                classification_reason: "Explicit recovery should restore bounded durable memory capture.",
                content: "PhaseThirtyOneOne.greet/1 remains a durable greeting fact.",
                confidence: 0.96
              )

    assert workflow_memory.record.status == :durable_memory_recorded

    assert {:ok, status_result} =
             AgentWorkspace.memory_graph_status(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    assert status_result.ready? == true
    assert status_result.stale? == false
    assert status_result.feedback.state == :ready
  end

  test "31.3.1.2 cross-graph links remain coherent after restart-style recovery", %{
    workspace_path_one: workspace_path
  } do
    managed_repo = create_managed_repo!("phase-31-restart")
    revision = "phase-31-restart-rev"

    assert {:ok, _source_graph} =
             AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path, revision: revision)

    assert {:ok, _memory_graph} =
             AgentWorkspace.refresh_memory_graph(managed_repo.id, workspace_path, revision: revision)

    assert {:ok, projection} =
             ProductService.functions(
               managed_repo.id,
               workspace_path,
               module_name: "PhaseThirtyOneOne",
               function_name: "greet",
               revision: revision
             )

    assert {:ok, workflow_memory} =
             WorkflowService.record_memory(
               projection,
               actor_id: "system:phase-thirty-one-restart",
               workspace_path: workspace_path,
               work_item_id: "restart-#{System.unique_integer([:positive])}",
               query: %{module_name: "PhaseThirtyOneOne", function_name: "greet"},
               memory_kind: :pattern,
               classification_reason: "Restart recovery should preserve code anchors.",
               content: "PhaseThirtyOneOne.greet/1 remains the greeting pattern anchor."
             )

    memory_iri = workflow_memory.record.capture.resource_iri

    assert {:ok, pre_restart_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?function
               WHERE {
                 <#{memory_iri}> jido:aboutFunction ?function .
               }
               """,
               revision: revision,
               allow_stale?: true
             )

    assert pre_restart_query.row_count == 1
    anchored_function = get_in(List.first(pre_restart_query.bindings), ["function", :value])
    assert String.starts_with?(anchored_function, JidoCode.SourceCodeGraph.base_iri(managed_repo.id))

    :ok = AgentWorkspace.shutdown_kernel(managed_repo.id)

    assert {:ok, recovery_result} =
             AgentWorkspace.recover_memory_graph(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    assert recovery_result.graph_status.ready? == true

    assert {:ok, post_restart_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?function
               WHERE {
                 <#{memory_iri}> jido:aboutFunction ?function .
               }
               """,
               revision: revision,
               allow_stale?: true
             )

    assert post_restart_query.row_count == 1
    assert get_in(List.first(post_restart_query.bindings), ["function", :value]) == anchored_function
  end

  test "31.3.1.3 memory graph behavior stays isolated per repository", %{
    workspace_path_one: workspace_path_one,
    workspace_path_two: workspace_path_two
  } do
    managed_repo_one = create_managed_repo!("phase-31-isolated-one")
    managed_repo_two = create_managed_repo!("phase-31-isolated-two")
    revision = "phase-31-isolated-rev"

    assert {:ok, _source_graph_one} =
             AgentWorkspace.load_source_code_graph(managed_repo_one.id, workspace_path_one, revision: revision)

    assert {:ok, _source_graph_two} =
             AgentWorkspace.load_source_code_graph(managed_repo_two.id, workspace_path_two, revision: revision)

    assert {:ok, _memory_graph_one} =
             AgentWorkspace.refresh_memory_graph(managed_repo_one.id, workspace_path_one, revision: revision)

    assert {:ok, _memory_graph_two} =
             AgentWorkspace.refresh_memory_graph(managed_repo_two.id, workspace_path_two, revision: revision)

    assert {:ok, projection_one} =
             ProductService.functions(
               managed_repo_one.id,
               workspace_path_one,
               module_name: "PhaseThirtyOneOne",
               function_name: "greet",
               revision: revision
             )

    assert {:ok, workflow_memory} =
             WorkflowService.record_memory(
               projection_one,
               actor_id: "system:phase-thirty-one-isolated",
               workspace_path: workspace_path_one,
               work_item_id: "isolated-#{System.unique_integer([:positive])}",
               query: %{module_name: "PhaseThirtyOneOne", function_name: "greet"},
               memory_kind: :convention,
               classification_reason: "Only the owning repository should observe this durable memory.",
               content: "PhaseThirtyOneOne.greet/1 is the repo-one greeting convention."
             )

    assert workflow_memory.record.status == :durable_memory_recorded

    assert {:ok, status_one} =
             AgentWorkspace.memory_graph_status(managed_repo_one.id, workspace_path_one, revision: revision)

    assert {:ok, status_two} =
             AgentWorkspace.memory_graph_status(managed_repo_two.id, workspace_path_two, revision: revision)

    assert status_one.dataset.graph_store_path != status_two.dataset.graph_store_path

    assert {:ok, repo_one_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_one.id,
               workspace_path_one,
               """
               SELECT ?memory
               WHERE {
                 ?memory jido:content "PhaseThirtyOneOne.greet/1 is the repo-one greeting convention." .
               }
               """,
               revision: revision,
               allow_stale?: true
             )

    assert {:ok, repo_two_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo_two.id,
               workspace_path_two,
               """
               SELECT ?memory
               WHERE {
                 ?memory jido:content "PhaseThirtyOneOne.greet/1 is the repo-one greeting convention." .
               }
               """,
               revision: revision,
               allow_stale?: true
             )

    assert repo_one_query.row_count == 1
    assert repo_two_query.row_count == 0
  end

  test "31.3.2.1 contributor verification and guidance include the memory stack" do
    mixfile = File.read!("mix.exs")
    readme = File.read!("README.md")
    contributing = File.read!("CONTRIBUTING.md")
    agents = File.read!("AGENTS.md")
    guide = File.read!("memory_ontology_guide.md")

    assert mixfile =~ "\"memory.verify\""
    assert mixfile =~ "\"semantic.verify\""
    assert readme =~ "mix memory.verify"
    assert contributing =~ "mix memory.verify"
    assert agents =~ "mix memory.verify"
    assert guide =~ "Where Individuals Enter The Graph"
    assert String.downcase(guide) =~ "raw runtime or model output is not durable memory"
  end

  defp create_managed_repo!(name) do
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

  defp create_workspace_path!(module_name) do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_one_#{module_name}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyOne.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_one_example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello \#{name}"
      end
      """
    )

    workspace_path
  end
end
