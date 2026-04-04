defmodule JidoCode.Orchestration.PhaseEighteenIntegrationTest do
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Orchestration.{Run, RunBridge, RunSummaryFeed, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.RunOutcomes

  test "canonical dashboard and workbench feeds resolve governed runs when projection exists" do
    {:ok, project} = create_project("phase-eighteen-canonical-feeds")
    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "phase-eighteen-run-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "phase_eighteen_test", "mode" => "manual"},
        inputs: %{"task_summary" => "Canonical feed projection"},
        input_metadata: %{"task_summary" => %{"required" => true, "source" => "test"}},
        initiating_actor: %{id: "operator-1", email: "operator@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-04 10:00:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    {:ok, run_summaries, nil} = RunSummaryFeed.default_loader()

    assert Enum.any?(run_summaries, &(&1.run_id == run.run_id))

    outcomes =
      RunOutcomes.load([
        %{id: project.id, legacy_project_id: project.id, managed_repo_id: managed_repo.id}
      ])

    assert outcomes[project.id].run_id == run.run_id
    assert outcomes[project.id].status == "pending"
  end

  test "public turn materialization feeds canonical governed run summaries and outcomes" do
    {:ok, project} = create_project("phase-eighteen-turn-materialization")
    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{run: run}} =
             RunBridge.materialize_turn(%{
               project_id: project.id,
               managed_repo_id: managed_repo.id,
               actor_id: "operator-turn",
               actor_email: "turn@example.com",
               conversation_id: "phase-eighteen-conversation",
               turn: %{
                 turn_id: "phase-eighteen-turn",
                 session_id: "phase-eighteen-conversation",
                 conversation_id: "phase-eighteen-conversation",
                 operation: "plan",
                 objective: "Verify canonical run feeds after turn materialization",
                 state: "completed",
                 terminal_at: "2026-04-04T10:15:00Z",
                 assistant_output: %{message: "Canonical run feeds are ready."},
                 summary_status: %{state: "completed"}
               },
               review: %{
                 turn_id: "phase-eighteen-turn",
                 assistant_output: %{message: "Canonical run feeds are ready."}
               },
               artifacts: [
                 %{
                   artifact_id: "artifact-1",
                   kind: "report",
                   title: "Canonical feed proof",
                   summary: "Run summary and workbench outcome should resolve from Run."
                 }
               ],
               events: [
                 %{event_id: "event-1", family: "completed", content: "Canonical run feeds are ready."}
               ]
             })

    {:ok, run_summaries, nil} = RunSummaryFeed.default_loader()
    assert Enum.any?(run_summaries, &(&1.run_id == run.run_id))

    outcomes =
      RunOutcomes.load([
        %{id: project.id, legacy_project_id: project.id, managed_repo_id: managed_repo.id}
      ])

    assert outcomes[project.id].run_id == run.run_id
    assert outcomes[project.id].status == "completed"
  end

  test "orphaned workflow history is absent from canonical feeds once the governed projection is removed" do
    {:ok, project} = create_project("phase-eighteen-orphaned-history")
    {:ok, managed_repo} = ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "phase-eighteen-orphan-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{"source" => "phase_eighteen_test", "mode" => "manual"},
        inputs: %{"task_summary" => "Orphaned history should not leak"},
        input_metadata: %{"task_summary" => %{"required" => true, "source" => "test"}},
        initiating_actor: %{id: "operator-1", email: "operator@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-04 10:30:00Z]
      })

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    :ok = Ash.destroy(run, actor: Actor.factory_system_actor())

    {:ok, persisted_workflow_run} =
      WorkflowRun.get_by_project_and_run_id(
        %{project_id: project.id, run_id: workflow_run.run_id},
        actor: Actor.operator_actor()
      )

    assert persisted_workflow_run.id == workflow_run.id

    assert {:ok, [], nil} = RunSummaryFeed.default_loader()

    outcomes =
      RunOutcomes.load([
        %{id: project.id, legacy_project_id: project.id, managed_repo_id: managed_repo.id}
      ])

    refute Map.has_key?(outcomes, project.id)
  end

  defp create_project(name) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{}
    })
  end
end
