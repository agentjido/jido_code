defmodule JidoCode.Orchestration.RunActionsTest do
  use ExUnit.Case, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.RecordStore, as: ControlPlaneRecordStore
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Orchestration.{RecordStore, Run, RunActions, RunBridge, WorkflowRun}

  setup do
    store_name = :"run_actions_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_run_actions/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  test "approve transitions governed run and workflow compatibility projections" do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{full_name: "owner/run-actions", name: "run-actions"})

    {:ok, %WorkflowRun{} = workflow_run} =
      RecordStore.upsert_workflow_run_compatibility(%{
        managed_repo_id: managed_repo.id,
        project_id: JidoCode.UUID.generate(),
        run_id: "run-actions-approval",
        workflow_name: "implement_task",
        workflow_version: 1,
        status: :awaiting_approval,
        current_step: "approval_gate",
        trigger: %{"source" => "test"},
        inputs: %{},
        input_metadata: %{},
        initiating_actor: %{"id" => "operator"},
        status_transitions: [],
        step_results: %{},
        started_at: ~U[2026-04-01 10:00:00Z]
      })

    assert {:ok, %Run{} = run} = RunBridge.sync_workflow_run(workflow_run)
    assert run.status == :awaiting_approval

    assert {:ok, %Run{} = approved_run} =
             RunActions.approve(run, %{
               actor: %{"id" => "operator-1", "email" => "operator@example.com"},
               current_step: "resume_execution",
               approved_at: ~U[2026-04-01 10:03:00Z]
             })

    assert approved_run.status == :running
    assert approved_run.current_step == "resume_execution"

    assert get_in(approved_run.run_metadata, ["workflow_audit", "step_results", "approval_decision", "decision"]) ==
             "approved"

    assert {:ok, workflow_run_record} =
             ControlPlaneRecordStore.get_by_identity(
               :workflow_run,
               :unique_workflow_run,
               "workflowRunId",
               workflow_run.id
             )

    updated_workflow_run = RecordStore.to_workflow_run(workflow_run_record)
    assert updated_workflow_run.status == :running
    assert updated_workflow_run.current_step == "resume_execution"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
