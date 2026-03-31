defmodule JidoCode.Control.PhaseSixIntegrationTest do
  # covers: architecture.policy_layers.legacy_and_ingress_surfaces_require_explicit_actor_context
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.run_governance.legacy_workflow_history_backfills_into_governed_runs
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{ChangeRequest, Decision}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Orchestration.{Run, RunBridge, WorkflowRun}
  alias JidoCode.Projects.Project

  test "explicit actor context stays required while governed review flow preserves actor attribution" do
    Actor.clear_policy_actor()

    assert {:error, _reason} =
             Project.create(%{
               name: "repo-phase-six-anonymous",
               github_full_name: "owner/repo-phase-six-anonymous",
               default_branch: "main",
               settings: %{}
             })

    operator_actor = Actor.operator_actor(%{"id" => "operator-phase-six", "email" => "phase-six@example.com"})
    admin_actor = Actor.admin_actor(%{"id" => "admin-phase-six", "email" => "admin-phase-six@example.com"})

    {:ok, project} =
      Project.create(
        %{
          name: "repo-phase-six-governed",
          github_full_name: "owner/repo-phase-six-governed",
          default_branch: "main",
          settings: %{}
        },
        actor: operator_actor
      )

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{work_item: work_item}} =
             Ingress.record_operator_intake(%{
               channel: "workflows",
               intent: "manual_run_request",
               project_id: project.id,
               actor: %{
                 "id" => "operator-phase-six",
                 "email" => "phase-six@example.com",
                 "actor_class" => "operator"
               },
               payload: %{"workflow_name" => "implement_task"},
               source_metadata: %{"trigger" => %{"source" => "phase_six_integration_test"}}
             })

    assert {:ok, %{workflow_run: workflow_run, run: run}} =
             RunBridge.launch_work_item(work_item, %{
               workflow_name: "implement_task",
               initiating_actor: %{
                 "id" => "operator-phase-six",
                 "email" => "phase-six@example.com",
                 "actor_class" => "operator"
               }
             })

    assert {:ok, workflow_run} =
             Actor.with_policy_actor(operator_actor, fn ->
               WorkflowRun.transition_status(workflow_run, %{
                 to_status: :running,
                 current_step: "plan_changes",
                 transitioned_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
             end)

    assert {:ok, workflow_run} =
             Actor.with_policy_actor(operator_actor, fn ->
               WorkflowRun.transition_status(workflow_run, %{
                 to_status: :awaiting_approval,
                 current_step: "approval_gate",
                 transitioned_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
             end)

    assert {:ok, _approved_workflow_run} =
             WorkflowRun.approve(workflow_run, %{
               actor: admin_actor,
               approved_at: DateTime.utc_now() |> DateTime.truncate(:second)
             })

    assert run.managed_repo_id == managed_repo.id
    assert run.initiating_actor["actor_class"] == "operator"

    {:ok, refreshed_run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    {:ok, change_request} = ChangeRequest.get_by_run_id(refreshed_run.id, actor: Actor.operator_actor())

    {:ok, [decision]} =
      Decision.read(
        query: [filter: [run_id: refreshed_run.id], sort: [decided_at: :desc]],
        actor: Actor.operator_actor()
      )

    assert change_request.status == :approved
    assert decision.actor["id"] == "admin-phase-six"
    assert decision.actor["actor_class"] == "admin"
  end
end
