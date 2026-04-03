defmodule JidoCodeWeb.PhaseElevenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RepoPosture
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "dashboard and run detail stay review-safe when runtime rollout is blocked", %{conn: _conn} do
    register_owner("phase-eleven-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase-eleven-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-phase-eleven-live",
        github_full_name: "owner/repo-phase-eleven-live",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-phase-eleven-live-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "coding_turn_plan",
        workflow_version: 1,
        trigger: %{
          source: "public_turn_runtime",
          mode: "conversation_runtime",
          turn_id: "turn-phase-eleven-live-1"
        },
        inputs: %{"turn_id" => "turn-phase-eleven-live-1"},
        input_metadata: %{"turn_id" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "phase-eleven-owner@example.com"},
        current_step: "public_turn_materialized",
        started_at: ~U[2026-04-02 12:00:00Z],
        step_results: %{
          "coding_turn_summary" => %{
            "turn_id" => "turn-phase-eleven-live-1",
            "conversation_id" => "conversation-phase-eleven-live-1",
            "state" => "completed",
            "assistant_output" => %{"message" => "Governed review remains available."}
          },
          "runtime_service_delivery" => %{
            "delivery_mode" => "replay_fallback",
            "reason_code" => "rollout_withheld",
            "terminal_handoff_kind" => "replay_terminal_lookup",
            "terminal_state" => "completed",
            "turn_id" => "turn-phase-eleven-live-1",
            "session_id" => "conversation-phase-eleven-live-1",
            "conversation_id" => "conversation-phase-eleven-live-1",
            "summary" => "Coding turn delivery fell back to replay because rollout was withheld."
          }
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "public_turn_in_progress",
        transitioned_at: ~U[2026-04-02 12:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-02 12:02:00Z]
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, repo_posture} =
      RepoPosture.upsert_for_managed_repo(
        %{
          managed_repo_id: managed_repo.id,
          summary: "Repo posture remains governed.",
          overall_trust: "medium",
          execution_readiness: "low",
          validation_reliability: "high",
          review_burden: "high",
          drift_rate: "low",
          recovery_resilience: "medium",
          requirements_confidence: "high",
          supervision_mode: "guided",
          escalation_status: "review",
          contributing_check_ids: [],
          posture_metadata: %{
            "runtime_service_evidence_summary" =>
              "Runtime rollout was withheld, but governed review remains available through bounded fallback evidence.",
            "runtime_service_evidence_state" => %{
              "status" => "blocked",
              "review_required" => true,
              "runtime_delivery" => %{
                "delivery_mode" => "replay_fallback",
                "reason_code" => "rollout_withheld"
              },
              "integration_outcomes" => %{
                "latest_invocation" => %{
                  "provider" => "github",
                  "summary" => "github review handoff remains available"
                }
              }
            }
          }
        },
        actor: Actor.operator_actor()
      )

    {:ok, dashboard_view, dashboard_html} =
      live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-runtime-evidence-count-blocked", "1")

    assert has_element?(
             dashboard_view,
             "#dashboard-runtime-evidence-summary",
             "Runtime posture tracks 1 repo(s): 1 blocked"
           )

    assert has_element?(
             dashboard_view,
             "#dashboard-runtime-evidence-note",
             "Product records remain the source of truth"
           )

    assert has_element?(
             dashboard_view,
             "#dashboard-runtime-evidence-item-details-#{dom_token(repo_posture.id)}",
             "Delivery: replay fallback"
           )

    assert has_element?(
             dashboard_view,
             "#dashboard-runtime-evidence-item-details-#{dom_token(repo_posture.id)}",
             "Latest provider: github"
           )

    refute dashboard_html =~ "GlobalSignalBus"
    refute dashboard_html =~ "subscriber_ref"

    {:ok, run_view, run_html} =
      live(recycle(authed_conn), ~p"/projects/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(run_view, "#run-detail-governance-summary")
    assert has_element?(run_view, "#run-detail-runtime-evidence-status", "blocked")

    assert has_element?(
             run_view,
             "#run-detail-runtime-evidence-summary",
             "governed review remains available"
           )

    assert has_element?(
             run_view,
             "#run-detail-runtime-evidence-delivery-mode",
             "replay fallback"
           )

    assert has_element?(run_view, "#run-detail-runtime-evidence-reason", "rollout withheld")

    assert has_element?(
             run_view,
             "#run-detail-runtime-evidence-note",
             "Product governance stores bounded runtime evidence"
           )

    refute run_html =~ "GlobalSignalBus"
    refute run_html =~ "subscriber_ref"
  end

  defp dom_token(value) do
    value
    |> to_string()
    |> String.replace(~r/[^a-zA-Z0-9_-]/, "-")
  end
end
