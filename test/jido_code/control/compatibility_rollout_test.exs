defmodule JidoCode.Control.CompatibilityRolloutTest do
  # covers: architecture.factory_control_plane.compatibility_rollout_backfills_legacy_repo_records
  # covers: architecture.factory_control_plane.compatibility_rollout_exposes_removal_and_rollback_state
  # covers: architecture.execution_pipeline.legacy_workflow_state_projects_forward_without_reexecution
  # covers: architecture.run_governance.legacy_workflow_history_backfills_into_governed_runs
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, CompatibilityRollout, ManagedRepo, RepoBridge}
  alias JidoCode.Orchestration.{Run, RunBridge, WorkflowRun}
  alias JidoCode.Repo

  test "backfill and report restore legacy project and workflow history into control-plane projections" do
    legacy_project_id = insert_legacy_project()
    legacy_run_id = insert_legacy_workflow_run(legacy_project_id)

    {:ok, pre_report} = CompatibilityRollout.report()
    assert pre_report.counts.projects_missing_managed_repo == 1
    assert pre_report.counts.workflow_runs_missing_governed_run == 1

    {:ok, %{backfill: backfill, report: report}} = CompatibilityRollout.backfill_and_report()

    assert backfill.projects_backfilled == 1
    assert backfill.workflow_runs_backfilled == 1
    assert backfill.rollback_safe == true
    assert report.counts.projects_missing_managed_repo == 0
    assert report.counts.workflow_runs_missing_governed_run == 0

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    {:ok, workflow_run} =
      WorkflowRun.get_by_project_and_run_id(
        %{project_id: legacy_project_id, run_id: legacy_run_id},
        actor: Actor.operator_actor()
      )

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())

    assert managed_repo.legacy_project_id == legacy_project_id
    assert run.legacy_project_id == legacy_project_id
    assert run.run_id == legacy_run_id
  end

  test "repo scope auto-backfills a managed repo for legacy project rows" do
    legacy_project_id = insert_legacy_project()

    {:ok, scope} = RepoBridge.repo_scope(legacy_project_id)

    assert scope.project_id == legacy_project_id
    assert is_binary(scope.managed_repo_id)
    assert scope.managed_repo.legacy_project_id == legacy_project_id
  end

  test "legacy workflow history can be projected into governed runs on demand" do
    legacy_project_id = insert_legacy_project()
    {:ok, _managed_repo} = RepoBridge.managed_repo_for_project(legacy_project_id)
    legacy_run_id = insert_legacy_workflow_run(legacy_project_id)

    {:ok, workflow_run} =
      WorkflowRun.get_by_project_and_run_id(
        %{project_id: legacy_project_id, run_id: legacy_run_id},
        actor: Actor.operator_actor()
      )

    {:ok, run} = RunBridge.projected_run_for_workflow_run(workflow_run)

    assert run.legacy_project_id == legacy_project_id
    assert run.run_id == legacy_run_id
    assert is_binary(run.managed_repo_id)
  end

  defp insert_legacy_project do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    unique = System.unique_integer([:positive])
    project_id = Ecto.UUID.generate()
    project_db_id = Ecto.UUID.dump!(project_id)
    repo_name = "owner/legacy-rollout-#{unique}"

    {1, nil} =
      Repo.insert_all("projects", [
        %{
          id: project_db_id,
          name: "legacy-rollout-#{unique}",
          source_kind: "github",
          source_identifier: repo_name,
          github_full_name: repo_name,
          local_path: nil,
          default_branch: "main",
          settings: %{},
          inserted_at: now,
          updated_at: now
        }
      ])

    project_id
  end

  defp insert_legacy_workflow_run(project_id) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    run_id = "legacy-run-#{System.unique_integer([:positive])}"
    workflow_run_id = Ecto.UUID.dump!(Ecto.UUID.generate())
    project_db_id = Ecto.UUID.dump!(project_id)

    {1, nil} =
      Repo.insert_all("workflow_runs", [
        %{
          id: workflow_run_id,
          run_id: run_id,
          project_id: project_db_id,
          managed_repo_id: nil,
          workflow_name: "implement_task",
          workflow_version: 1,
          status: "pending",
          trigger: %{"source" => "compatibility_rollout_test", "mode" => "manual"},
          inputs: %{"task_summary" => "Backfill legacy workflow run history"},
          input_metadata: %{"task_summary" => %{"required" => true, "source" => "test"}},
          initiating_actor: %{"id" => "operator-1", "email" => "operator@example.com"},
          current_step: "queued",
          status_transitions: [],
          step_results: %{},
          error: nil,
          started_at: now,
          completed_at: nil,
          retry_of_run_id: nil,
          retry_attempt: 1,
          retry_lineage: [],
          inserted_at: now,
          updated_at: now
        }
      ])

    run_id
  end
end
