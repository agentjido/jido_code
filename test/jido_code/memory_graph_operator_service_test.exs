defmodule JidoCode.MemoryGraphOperatorServiceTest do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_mutations_flow_through_capture_plane_updates
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_actions_preserve_freshness_supersession_and_provenance
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.Decision
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, OperatorService, ProductService}
  alias JidoCode.Orchestration.Run
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Projects.Project

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    workspace_path = create_workspace_path!()

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
      File.rm_rf!(workspace_path)
    end)

    {:ok, workspace_path: workspace_path}
  end

  test "validate and invalidate route through bounded durable-memory update helpers", %{
    workspace_path: workspace_path
  } do
    {_project, managed_repo} = create_managed_repo!(workspace_path)
    revision = "rev-33-validate"
    actor = Actor.operator_actor(%{"id" => "operator-validate", "email" => "validate@example.com"})

    %{known_issue_memory_iri: memory_iri} =
      seed_operator_memory_graph!(managed_repo.id, workspace_path, revision)

    assert {:ok, projection} =
             ProductService.memories(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    assert {:ok, validation} =
             OperatorService.validate(
               projection,
               memory_iri,
               workspace_path: workspace_path,
               actor: actor,
               run_id: "run-33-operator"
             )

    assert validation.status == :memory_validated

    assert {:ok, validated_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?score ?validatedAt
               WHERE {
                 <#{memory_iri}> jido:freshnessScore ?score ;
                   jido:lastValidatedAt ?validatedAt .
               }
               """,
               allow_stale?: true,
               revision: revision
             )

    assert validated_query.row_count == 1

    rewrite_workspace_module!(workspace_path, "ExampleMemoryOperatorUpdated")
    {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
    updated_revision = revision_metadata.current_revision

    assert {:ok, invalidation} =
             OperatorService.invalidate(
               projection,
               memory_iri,
               workspace_path: workspace_path,
               actor: actor,
               revision: updated_revision,
               stale_reason: :workspace_revision_changed,
               run_id: "run-33-operator"
             )

    assert invalidation.status == :memory_invalidated

    assert {:ok, invalidated_query} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?revision ?reason
               WHERE {
                 <#{memory_iri}> jido:invalidatedByRevision ?revision ;
                   jido:staleReason ?reason .
               }
               """,
               allow_stale?: true,
               revision: updated_revision
             )

    assert invalidated_query.row_count == 1
  end

  test "supersede_with_governed_decision preserves successor and superseded links", %{
    workspace_path: workspace_path
  } do
    {_project, managed_repo} = create_managed_repo!(workspace_path)
    revision = "rev-33-supersede"
    actor = Actor.operator_actor(%{"id" => "operator-supersede", "email" => "supersede@example.com"})

    %{decision_memory_iri: memory_iri, run: run} =
      seed_operator_memory_graph!(managed_repo.id, workspace_path, revision)

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-33-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          decision: :approve,
          actor: %{"id" => "operator-supersede", "email" => "supersede@example.com"},
          rationale: "The governed run now has an updated decision that supersedes the earlier memory.",
          decision_metadata: %{"source" => "memory_graph_operator_service_test"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    assert {:ok, projection} =
             ProductService.memories(
               managed_repo.id,
               workspace_path,
               kinds: [:decision],
               revision: revision
             )

    assert {:ok, result} =
             OperatorService.supersede_with_governed_decision(
               projection,
               memory_iri,
               decision,
               workspace_path: workspace_path,
               actor: actor,
               run_id: run.run_id,
               decision_id: decision.id
             )

    assert result.status == :memory_superseded

    successor_iri = result.successor_record.capture.resource_iri

    assert {:ok, query_result} =
             AgentWorkspace.query_memory_graph(
               managed_repo.id,
               workspace_path,
               """
               SELECT ?successor ?status ?supersededStatus
               WHERE {
                 ?successor jido:supersedes <#{memory_iri}> ;
                   jido:decisionStatus ?status .
                 <#{memory_iri}> jido:decisionStatus ?supersededStatus .
               }
               """,
               allow_stale?: true,
               revision: revision
             )

    assert query_result.row_count >= 1

    assert Enum.any?(query_result.bindings, fn binding ->
             get_in(binding, ["successor", :value]) == successor_iri
           end)
  end

  test "promote_follow_up creates governed work from selected durable memory", %{
    workspace_path: workspace_path
  } do
    {_project, managed_repo} = create_managed_repo!(workspace_path)
    revision = "rev-33-promote"
    actor = Actor.operator_actor(%{"id" => "operator-promote", "email" => "promote@example.com"})

    %{known_issue_memory_iri: memory_iri, run: run} =
      seed_operator_memory_graph!(managed_repo.id, workspace_path, revision)

    assert {:ok, projection} =
             ProductService.memories(
               managed_repo.id,
               workspace_path,
               revision: revision
             )

    assert {:ok, promotion} =
             OperatorService.promote_follow_up(
               projection,
               memory_iri,
               workspace_path: workspace_path,
               actor: actor,
               run_id: run.run_id
             )

    assert promotion.status == :memory_promoted
    assert promotion.target == :work_item
    assert promotion.result.work_item.managed_repo_id == managed_repo.id

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(
               query: [filter: [id: promotion.result.work_item.id]],
               actor: Actor.operator_actor()
             )

    assert persisted_work_item.work_metadata["memory_finding"]["freshness"]["state"] == "ready"
  end

  defp create_managed_repo!(workspace_path) do
    name = "phase-33-operator-#{System.unique_integer([:positive])}"

    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{workspace: %{workspace_path: workspace_path}}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
  end

  defp seed_operator_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    run_id = "run-33-operator-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: legacy_project_id!(managed_repo_id),
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "operator", mode: "manual"},
        inputs: %{"task_summary" => "Seed operator memory graph"},
        input_metadata: %{"task_summary" => %{required: true}},
        initiating_actor: %{id: "operator-seed", email: "seed@example.com"},
        current_step: "approval_gate",
        started_at: DateTime.utc_now()
      })

    {:ok, run} =
      Run.get_by_managed_repo_and_run_id(
        managed_repo_id,
        workflow_run.run_id,
        actor: Actor.operator_actor()
      )

    session_id = "memory-operator-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:memory-graph-operator",
                 workflow: :review,
                 work_item_id: "work-33",
                 goal: "Seed operator memory actions"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _review_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:memory-graph-operator",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Review artifact for operator memory actions.",
                 anchors: %{module_name: "ExampleMemoryOperator"},
                 governed_context: %{run_id: run.run_id}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, known_issue_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 session_id: session_id,
                 actor_id: "system:memory-graph-operator",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Operator actions should stay bounded and governed.",
                 revision: revision,
                 anchors: %{module_name: "ExampleMemoryOperator"},
                 governed_context: %{run_id: run.run_id},
                 classification: %{
                   source: "memory_graph_operator_service_test",
                   reason: "Section 33.2 needs durable memory for operator action coverage."
                 }
               ),
               revision: revision
             )

    assert {:ok, decision_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:memory-graph-operator",
                 workflow: :review,
                 work_item_id: "work-33",
                 content: "Governed run decisions should stay traceable in memory history.",
                 rationale: "The first durable decision memory provides the supersession baseline.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExampleMemoryOperator"},
                 governed_context: %{run_id: run.run_id},
                 classification: %{
                   source: "memory_graph_operator_service_test",
                   reason: "Section 33.2 needs a durable decision memory for supersession coverage."
                 }
               ),
               revision: revision
             )

    %{
      known_issue_memory_iri: known_issue_result.capture.resource_iri,
      decision_memory_iri: decision_result.capture.resource_iri,
      run: run
    }
  end

  defp legacy_project_id!(managed_repo_id) do
    {:ok, [managed_repo]} =
      ManagedRepo.read(
        query: [filter: [id: managed_repo_id], limit: 1],
        actor: Actor.operator_actor()
      )

    managed_repo.legacy_project_id
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_memory_graph_operator_service_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyThreeOperator.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_three_operator, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_memory_operator.ex"),
      """
      defmodule ExampleMemoryOperator do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_memory_operator.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end
end
