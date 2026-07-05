defmodule JidoCode.ControlPlane.BackupRecoveryIntegrationTest do
  use ExUnit.Case, async: false

  alias JidoCode.Control.{ManagedRepoStore, RepoBridge}
  alias JidoCode.ControlPlane.{Health, Integrity, StoreServer}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.Governance.RecordStore, as: GovernanceStore
  alias JidoCode.Operations.{RecordStore, WorkItem}
  alias JidoCode.Orchestration.{Run, RunBridge}

  setup do
    token = System.unique_integer([:positive])
    base_path = Path.join(System.tmp_dir!(), "jido_code_control_plane_backup_recovery/#{token}")

    original_store = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original_store)
      File.rm_rf(base_path)
    end)

    {:ok,
     source_name: :"control_plane_backup_source_#{token}",
     source_path: Path.join(base_path, "source"),
     target_name: :"control_plane_backup_target_#{token}",
     target_path: Path.join(base_path, "target"),
     export_path: Path.join(base_path, "exports/control-plane.nq")}
  end

  test "exported control-plane store restores and serves product projections after restart", context do
    start_store!(context.source_name, context.source_path, :reset_on_start)
    use_product_store!(context.source_name)

    smoke = create_product_smoke_records!()

    assert {:ok, source_integrity} = Integrity.check(context.source_name)
    assert source_integrity.status == :ok

    assert {:ok, export_report} = StoreServer.export(context.source_name, context.export_path)
    assert export_report.exported_quad_count > 0
    assert export_report.redacted_graphs == [:auth, :security]

    assert :ok = stop_supervised!(context.source_name)

    start_store!(context.target_name, context.target_path, :reset_on_start)
    assert {:ok, restore_report} = StoreServer.restore(context.target_name, context.export_path)
    assert restore_report.restored_quad_count == export_report.exported_quad_count
    assert restore_report.integrity.status == :ok

    use_product_store!(context.target_name)
    verify_product_smoke_records!(smoke)

    assert :ok = stop_supervised!(context.target_name)

    start_store!(context.target_name, context.target_path, :bootstrap_if_empty)
    use_product_store!(context.target_name)

    assert %{state: :ready} = Health.status(context.target_name)
    verify_product_smoke_records!(smoke)
  end

  defp create_product_smoke_records! do
    suffix = System.unique_integer([:positive])
    repo_full_name = "owner/recovery-#{suffix}"

    {:ok, %{managed_repo: managed_repo, source_repo: source_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: repo_full_name,
        full_name: repo_full_name,
        default_branch: "main",
        settings: %{"workspace_path" => "/workspace/recovery-#{suffix}"}
      })

    {:ok, work_item} =
      WorkItem.create(%{
        managed_repo_id: managed_repo.id,
        category: :implementation,
        status: :open,
        priority: :medium,
        recommended_action: "launch_fix_workflow",
        summary: "Verify backup and restore through product projections.",
        dedup_key: "backup-recovery-#{suffix}",
        initiating_actor: %{"id" => "backup-recovery", "actor_class" => "system"}
      })

    {:ok, %{workflow_run: workflow_run, run: run}} =
      RunBridge.launch_work_item(work_item, %{"workflow_name" => "implement_task"})

    {:ok, evidence} =
      Evidence.create(%{
        managed_repo_id: managed_repo.id,
        run_id: run.id,
        work_item_id: work_item.id,
        key: "backup-recovery-#{suffix}",
        source_key: "backup-recovery-#{suffix}",
        evidence_type: "recovery_test",
        summary: "Control-plane backup and restore preserved governed evidence.",
        evidence_details: %{"workflow_run_id" => workflow_run.id}
      })

    decision_key = "backup-recovery-#{suffix}:decision"

    {:ok, decision} =
      Decision.create(%{
        managed_repo_id: managed_repo.id,
        run_id: run.id,
        work_item_id: work_item.id,
        decision_key: decision_key,
        decision: :approve,
        actor: %{"id" => "backup-recovery", "actor_class" => "system"},
        rationale: "Recovered store served the product smoke projection.",
        evidence_ids: [evidence.id]
      })

    %{
      managed_repo_id: managed_repo.id,
      source_repo_id: source_repo.id,
      work_item_id: work_item.id,
      workflow_run_id: workflow_run.id,
      run_id: run.id,
      evidence_id: evidence.id,
      decision_key: decision.decision_key
    }
  end

  defp verify_product_smoke_records!(smoke) do
    assert {:ok, managed_repo} = ManagedRepoStore.get_by_id(smoke.managed_repo_id)
    assert managed_repo.id == smoke.managed_repo_id
    assert managed_repo.source_repo_id == smoke.source_repo_id

    assert {:ok, work_items} = RecordStore.list_work_by_managed_repo(smoke.managed_repo_id)
    assert Enum.any?(work_items, &(&1.id == smoke.work_item_id))

    assert {:ok, run} = Run.get_by_workflow_run_id(smoke.workflow_run_id)
    assert run.id == smoke.run_id
    assert run.managed_repo_id == smoke.managed_repo_id

    assert {:ok, evidence} = GovernanceStore.list_evidence(%{managed_repo_id: smoke.managed_repo_id})
    assert Enum.any?(evidence, &(&1.id == smoke.evidence_id and &1.run_id == smoke.run_id))

    assert {:ok, decisions} = GovernanceStore.list_decisions(%{managed_repo_id: smoke.managed_repo_id})
    assert Enum.any?(decisions, &(&1.decision_key == smoke.decision_key))
  end

  defp start_store!(name, path, reset_policy) do
    start_supervised!({StoreServer, name: name, id: name, path: path, reset_policy: reset_policy})
  end

  defp use_product_store!(name) do
    Application.put_env(:jido_code, :control_plane_product_store_server, name)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
