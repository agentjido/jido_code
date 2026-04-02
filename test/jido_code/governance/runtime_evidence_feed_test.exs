defmodule JidoCode.Governance.RuntimeEvidenceFeedTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{RepoPosture, RuntimeEvidenceFeed}
  alias JidoCode.Projects.Project

  test "loads runtime posture summaries from governed repo posture" do
    {:ok, project} =
      Project.create(%{
        name: "runtime-evidence-feed-repo",
        github_full_name: "owner/runtime-evidence-feed-repo",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, _repo_posture} =
      RepoPosture.upsert_for_managed_repo(
        %{
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
        },
        actor: Actor.operator_actor()
      )

    assert {:ok, [summary], nil} = RuntimeEvidenceFeed.load()
    assert summary.repo_label == managed_repo.display_name
    assert summary.status == "degraded"
    assert summary.delivery_mode == "replay_recovery"
    assert summary.reason_code == "live_delivery_detached"
    assert summary.latest_provider == "github"
    assert summary.review_required == true
  end
end
