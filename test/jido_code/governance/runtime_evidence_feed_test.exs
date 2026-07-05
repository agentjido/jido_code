defmodule JidoCode.Governance.RuntimeEvidenceFeedTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.ManagedRepoStore
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Governance.RecordStore, as: GovernanceStore
  alias JidoCode.Governance.RuntimeEvidenceFeed
  alias JidoCode.Projects.Project

  setup do
    setup_product_store()
  end

  test "loads runtime posture summaries from governed repo posture" do
    {:ok, project} =
      Project.create(%{
        name: "runtime-evidence-feed-repo",
        github_full_name: "owner/runtime-evidence-feed-repo",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} = ManagedRepoStore.get_by_legacy_project_id(project.id)

    {:ok, _repo_posture} =
      GovernanceStore.upsert_repo_posture(%{
        managed_repo_id: managed_repo.id,
        summary: "Repo posture remains governed.",
        overall_trust: "medium",
        execution_readiness: "high",
        validation_reliability: "high",
        review_burden: "high",
        drift_rate: "low",
        recovery_resilience: "medium",
        requirements_confidence: "high",
        supervision_mode: "guided",
        escalation_status: "review",
        contributing_check_ids: [],
        posture_metadata: %{
          "runtime_service_evidence_summary" => "Runtime service evidence indicates degraded execution trust.",
          "runtime_service_evidence_state" => %{
            "status" => "degraded",
            "runtime_delivery" => %{
              "delivery_mode" => "replay_recovery",
              "reason_code" => "live_delivery_detached"
            },
            "integration_outcomes" => %{
              "latest_invocation" => %{"provider" => "github"}
            }
          }
        }
      })

    assert {:ok, [summary], nil} = RuntimeEvidenceFeed.load()
    assert summary.repo_label == managed_repo.display_name
    assert summary.status == "degraded"
    assert summary.delivery_mode == "replay_recovery"
    assert summary.reason_code == "live_delivery_detached"
    assert summary.latest_provider == "github"
    assert summary.review_required == true
  end

  defp setup_product_store do
    store_name = :"runtime_evidence_feed_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_runtime_evidence_feed/#{store_name}")

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
