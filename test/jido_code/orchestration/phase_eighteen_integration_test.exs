defmodule JidoCode.Orchestration.PhaseEighteenIntegrationTest do
  # covers: architecture.run_governance.execution_projection_stays_internal_to_canonical_run_model
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepoStore}
  alias JidoCode.ControlPlane.{ProductStore, StoreServer}
  alias JidoCode.Orchestration.{RecordStore, RunSummaryFeed, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.RunOutcomes

  setup do
    setup_product_store()
  end

  test "canonical dashboard and workbench feeds resolve governed runs when projection exists" do
    {:ok, project} = create_project("phase-eighteen-canonical-feeds")
    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

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

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)
    {:ok, run_summaries, nil} = RunSummaryFeed.default_loader()

    assert Enum.any?(run_summaries, &(&1.run_id == run.run_id))

    outcomes =
      RunOutcomes.load([
        %{id: project.id, legacy_project_id: project.id, managed_repo_id: managed_repo.id}
      ])

    assert outcomes[project.id].run_id == run.run_id
    assert outcomes[project.id].status == "pending"
  end

  test "orphaned workflow history is absent from canonical feeds once the governed projection is removed" do
    {:ok, project} = create_project("phase-eighteen-orphaned-history")
    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

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

    {:ok, run} = RecordStore.get_run_by_workflow_run_id(workflow_run.id)
    assert {:ok, %{status: :deleted}} = ProductStore.dispatch(:delete, :run, subject_iri: run_subject_iri(run))

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

  defp run_subject_iri(run) do
    run.__metadata__
    |> Map.fetch!(:control_plane_record)
    |> Map.fetch!(:subject_iri)
  end

  defp setup_product_store do
    store_name = :"phase_eighteen_integration_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_phase_eighteen_integration/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
