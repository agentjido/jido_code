defmodule JidoCode.PhaseNinetyThreeIntegrationTest do
  # covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics
  # covers: architecture.context_compaction_policy.compaction_is_threshold_driven
  # covers: architecture.context_compaction_policy.raw_context_is_not_durable_compaction_metadata
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace

  test "automatic compaction helper stores summaries for eligible monitor recommendations" do
    managed_repo_id = "phase-93-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-93-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, status} =
             AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, %{
               workflow: :execute,
               specialist_role: :coder,
               conversation_id: "conversation-93",
               turn_id: "turn-2",
               context_budget: high_water_budget()
             })

    assert status["state"] == "recommend_compaction"

    snapshot = %{
      conversation_id: "conversation-93",
      managed_repo_id: managed_repo_id,
      work_item_id: work_item_id,
      turns: [
        %{id: "turn-1", state: "completed", payload: %{"instruction" => "older implementation context"}},
        %{id: "turn-2", state: "running", payload: %{"instruction" => "active implementation request"}}
      ],
      child_works: [
        %{id: "child-1", turn_id: "turn-1", state: "completed", result: %{"summary" => "older result"}}
      ]
    }

    assert {:ok, compacted_status} = AgentWorkspace.auto_compact_context(managed_repo_id, work_item_id, snapshot)

    assert compacted_status["summary_count"] == 1
    assert compacted_status["auto_compaction"]["state"] == "compacted"
    assert compacted_status["auto_compaction"]["source_span_ids"] == ["turn:turn-1"]

    assert {:ok, skipped} = AgentWorkspace.auto_compact_context(managed_repo_id, work_item_id, snapshot)

    assert skipped["state"] == "skip"
    assert skipped["reason"] == "source_span_already_compacted"
  end

  test "automatic compaction helper returns metadata-only skips when disabled" do
    managed_repo_id = "phase-93-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-93-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path,
               context_management: [auto_compaction_enabled?: false]
             )

    assert {:ok, _status} =
             AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, %{
               workflow: :execute,
               specialist_role: :coder,
               context_budget: high_water_budget()
             })

    assert {:ok, skipped} =
             AgentWorkspace.auto_compact_context(managed_repo_id, work_item_id, %{
               conversation_id: "conversation-93",
               managed_repo_id: managed_repo_id,
               work_item_id: work_item_id,
               turns: []
             })

    assert skipped["state"] == "skip"
    assert skipped["reason"] == "auto_compaction_disabled"
  end

  test "automatic compaction helper persists degraded state for ineligible candidates" do
    managed_repo_id = "phase-93-repo-#{System.unique_integer([:positive])}"
    work_item_id = "phase-93-work-#{System.unique_integer([:positive])}"
    workspace_path = create_workspace_path!()

    on_exit(fn -> File.rm_rf!(workspace_path) end)

    assert {:ok, _pod_name} =
             AgentWorkspace.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, _status} =
             AgentWorkspace.record_context_observation(managed_repo_id, work_item_id, %{
               workflow: :execute,
               specialist_role: :coder,
               context_budget: high_water_budget()
             })

    assert {:error, {:ineligible_compaction_candidate, %{reason: :no_eligible_history}}} =
             AgentWorkspace.auto_compact_context(managed_repo_id, work_item_id, %{
               conversation_id: "conversation-93",
               managed_repo_id: managed_repo_id,
               work_item_id: work_item_id,
               turns: [
                 %{id: "turn-active", state: "running", payload: %{"instruction" => "active request"}}
               ],
               child_works: []
             })

    degraded_status = AgentWorkspace.context_management_status(managed_repo_id, work_item_id)
    assert degraded_status["state"] == "degraded"
    assert get_in(degraded_status, ["latest_compaction", "retryable?"])
  end

  defp high_water_budget do
    %{
      "policy_id" => "context-budget:v1",
      "state" => "packed",
      "model_budget" => 1_000,
      "estimated_input_tokens" => 900,
      "diagnostics" => []
    }
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_93_context_management_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))
    File.write!(Path.join(workspace_path, "mix.exs"), "defmodule Phase93.MixProject do\nend\n")
    File.write!(Path.join(workspace_path, "lib/example.ex"), "defmodule Phase93.Example do\nend\n")

    workspace_path
  end
end
