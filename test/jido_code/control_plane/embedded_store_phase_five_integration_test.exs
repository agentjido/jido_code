defmodule JidoCode.ControlPlane.EmbeddedStorePhaseFiveIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.demand_ingress.external_object_tracks_repo_external_entities
  # covers: architecture.work_synthesis.work_item_is_canonical_operational_record
  # covers: architecture.run_governance.run_is_preferred_execution_record
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  # covers: architecture.run_governance.decision_records_capture_governance_outcomes
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Governance.{PolicyBridge, PostureBridge}
  alias JidoCode.Governance.RecordStore, as: GovernanceStore
  alias JidoCode.Operations.{Ingress, RecordStore, WorkItem}
  alias JidoCode.Orchestration.RecordStore, as: OrchestrationStore

  setup do
    setup_product_store()
  end

  test "operations demand flows from external object through work projections over the embedded store" do
    {:ok, %{managed_repo: managed_repo}} =
      create_managed_repo("owner/phase-five-operations", %{
        "support_agent_config" => %{"github_issue_bot" => %{"approval_mode" => "auto_post"}}
      })

    delivery = github_issue_delivery("delivery-phase-five-1", managed_repo.display_name, 451, 73)

    assert {:ok,
            %{
              external_object: external_object,
              observation: observation,
              event: event,
              assessment: assessment,
              work_item: %WorkItem{} = work_item,
              work_action: :created
            }} = Ingress.record_github_webhook_delivery(delivery)

    assert external_object.managed_repo_id == managed_repo.id
    assert external_object.canonical_key == "github:github_issue:owner/phase-five-operations:451"
    assert observation.external_object_id == external_object.id
    assert event.observation_id == observation.id
    assert assessment.event_id == event.id
    assert work_item.assessment_id == assessment.id
    assert work_item.external_object_id == external_object.id
    assert work_item.dedup_key =~ external_object.canonical_key

    assert {:ok,
            %{
              external_object: duplicate_external_object,
              work_item: duplicate_work_item,
              work_action: :suppressed_duplicate
            }} = Ingress.record_github_webhook_delivery(delivery)

    assert duplicate_external_object.id == external_object.id
    assert duplicate_work_item.id == work_item.id
    assert length(duplicate_work_item.audit_log) == 2

    assert {:ok, [repo_work_item]} = RecordStore.list_work_by_managed_repo(managed_repo.id)
    assert {:ok, [external_work_item]} = RecordStore.list_work_by_external_object(external_object.id)
    assert {:ok, [open_work_item]} = RecordStore.list_work_by_status(:open)
    assert {:ok, [high_work_item]} = RecordStore.list_work_by_priority("high")

    assert repo_work_item.id == work_item.id
    assert external_work_item.id == work_item.id
    assert open_work_item.id == work_item.id
    assert high_work_item.id == work_item.id

    assert {:ok, summary} = RecordStore.repository_monitoring_summary(managed_repo.id)
    assert summary.status == :ready
    assert summary.empty? == false
    assert summary.work_item_count == 1
    assert summary.status_counts == %{open: 1}
    assert summary.priority_counts == %{high: 1}
  end

  test "governance and orchestration records can be created queried and governed without Ash relationship loading" do
    {:ok, %{managed_repo: managed_repo}} =
      create_managed_repo("owner/phase-five-governed", %{
        "execution" => %{
          "sandbox_profile" => %{"shape" => "standard"},
          "validation_plan" => ["tests"],
          "governed_stages" => ["repo_attach", "plan", "implement", "validation", "approval", "cleanup"]
        }
      })

    {:ok, %{work_item: %WorkItem{} = work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: "operator-phase-five", email: "phase-five@example.com"},
        payload: %{"workflow_name" => "implement_task", "task_summary" => "Exercise embedded governance records"}
      })

    {:ok, execution_profile} =
      OrchestrationStore.upsert_execution_profile(%{
        managed_repo_id: managed_repo.id,
        name: "workflow:implement_task",
        sandbox_profile: %{"engine" => "jido_runic", "shape" => "standard"},
        validation_plan: ["tests"],
        governed_stages: ["repo_attach", "plan", "implement", "validation", "approval", "cleanup"]
      })

    {:ok, awaiting_run} =
      OrchestrationStore.upsert_run(%{
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        execution_profile_id: execution_profile.id,
        run_id: "phase-five-governed-run",
        workflow_name: "implement_task",
        workflow_version: 1,
        status: :awaiting_approval,
        current_step: "approval_gate",
        current_stage: "approval",
        governed_stages: ["repo_attach", "plan", "implement", "validation", "approval", "cleanup"],
        stage_statuses: %{"approval" => "awaiting_decision"},
        trigger: %{"source" => "integration_test"},
        inputs: %{"work_item_id" => work_item.id},
        initiating_actor: %{"id" => "operator-phase-five"},
        execution_engine: "jido_runic",
        workflow_state_ref: %{"engine" => "jido_runic"},
        run_metadata: %{"projection_source" => "embedded_store_phase_five"}
      })

    {:ok, diff_evidence} =
      GovernanceStore.upsert_evidence(%{
        managed_repo_id: managed_repo.id,
        run_id: awaiting_run.id,
        work_item_id: work_item.id,
        key: "diff_summary",
        evidence_type: "diff_summary",
        summary: "2 files changed (+18/-3).",
        evidence_details: %{"summary" => "2 files changed (+18/-3)."},
        source: "integration_test"
      })

    {:ok, test_evidence} =
      GovernanceStore.upsert_evidence(%{
        managed_repo_id: managed_repo.id,
        run_id: awaiting_run.id,
        work_item_id: work_item.id,
        key: "test_summary",
        evidence_type: "test_summary",
        summary: "mix test passed.",
        evidence_details: %{"summary" => "mix test passed."},
        source: "integration_test"
      })

    evidence_ids = [diff_evidence.id, test_evidence.id]

    {:ok, change_request} =
      GovernanceStore.upsert_change_request(%{
        managed_repo_id: managed_repo.id,
        run_id: awaiting_run.id,
        work_item_id: work_item.id,
        status: :open,
        summary: "Review embedded governance run",
        review_context: %{"current_step" => "approval_gate", "evidence_keys" => ["diff_summary", "test_summary"]},
        request_metadata: %{"review_policy" => %{"mode" => "approval_required"}},
        evidence_ids: evidence_ids
      })

    {:ok, decision} =
      GovernanceStore.upsert_decision(%{
        managed_repo_id: managed_repo.id,
        run_id: awaiting_run.id,
        change_request_id: change_request.id,
        work_item_id: work_item.id,
        decision_key: "#{awaiting_run.id}:approve:phase-five",
        decision: :approve,
        actor: %{"id" => "admin-phase-five", "email" => "admin-phase-five@example.com"},
        rationale: "Embedded store review records are linked.",
        evidence_ids: evidence_ids
      })

    {:ok, completed_run} =
      OrchestrationStore.upsert_run(%{
        managed_repo_id: managed_repo.id,
        work_item_id: work_item.id,
        execution_profile_id: execution_profile.id,
        run_id: awaiting_run.run_id,
        workflow_name: awaiting_run.workflow_name,
        workflow_version: awaiting_run.workflow_version,
        status: :completed,
        current_step: "cleanup",
        current_stage: "cleanup",
        governed_stages: awaiting_run.governed_stages,
        stage_statuses: %{"approval" => "completed", "cleanup" => "completed"},
        trigger: awaiting_run.trigger,
        inputs: awaiting_run.inputs,
        initiating_actor: awaiting_run.initiating_actor,
        execution_engine: awaiting_run.execution_engine,
        workflow_state_ref: awaiting_run.workflow_state_ref,
        run_metadata: awaiting_run.run_metadata,
        completed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      })

    assert completed_run.id == awaiting_run.id
    assert completed_run.status == :completed

    assert {:ok, [persisted_run]} = OrchestrationStore.list_runs(%{managed_repo_id: managed_repo.id})
    assert persisted_run.id == awaiting_run.id

    assert {:ok, evidence_records} =
             GovernanceStore.list_evidence(%{run_id: awaiting_run.id}, query: [sort: [key: :asc]])

    assert Enum.map(evidence_records, & &1.key) == ["diff_summary", "test_summary"]

    assert {:ok, persisted_change_request} = GovernanceStore.get_change_request_by_run_id(awaiting_run.id)
    assert persisted_change_request.id == change_request.id
    assert persisted_change_request.evidence_ids == evidence_ids

    assert {:ok, [persisted_decision]} = GovernanceStore.list_decisions(%{run_id: awaiting_run.id})
    assert persisted_decision.id == decision.id
    assert persisted_decision.change_request_id == change_request.id

    assert {:ok, %{repo_posture: synced_posture}} = PostureBridge.sync_managed_repo(managed_repo)
    assert {:ok, persisted_posture} = GovernanceStore.get_repo_posture_by_managed_repo_id(managed_repo.id)
    assert persisted_posture.id == synced_posture.id

    assert {:ok, review_policy} = PolicyBridge.review_policy_for_managed_repo(managed_repo.id)
    assert review_policy["mode"] == "approval_required"
    assert review_policy["supervision_mode"] in ["directed", "guided", "delegated", "autonomous"]
  end

  defp create_managed_repo(full_name, settings) do
    RepoBridge.upsert_managed_repo(%{
      name: full_name,
      full_name: full_name,
      default_branch: "main",
      settings: settings
    })
  end

  defp github_issue_delivery(delivery_id, repo_full_name, issue_id, issue_number) do
    %{
      delivery_id: delivery_id,
      event: "issues",
      payload: %{
        "action" => "opened",
        "repository" => %{
          "id" => 10_001,
          "name" => repo_full_name |> String.split("/") |> List.last(),
          "full_name" => repo_full_name,
          "html_url" => "https://github.com/#{repo_full_name}",
          "visibility" => "public"
        },
        "issue" => %{
          "id" => issue_id,
          "number" => issue_number,
          "title" => "Exercise embedded product store integration",
          "html_url" => "https://github.com/#{repo_full_name}/issues/#{issue_number}",
          "state" => "open"
        }
      }
    }
  end

  defp setup_product_store do
    store_name = :"phase_five_embedded_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_phase_five_embedded_store/#{store_name}")

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
