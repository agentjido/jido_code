defmodule JidoCodeWeb.RunDetailLiveTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  # covers: architecture.runtime_service_overlay.runtime_topology_details_remain_opaque_to_product
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RepoPosture
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  test "renders persisted status transition timeline entries with per-step durations", %{
    conn: _conn
  } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail",
        github_full_name: "owner/repo-run-detail",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-123",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render transition timeline"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 22:00:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 22:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 22:02:00Z]
      })

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/projects/#{project.id}/runs/run-detail-123", on_error: :warn)

    assert has_element?(view, "#run-detail-title", "Workflow run detail")
    assert has_element?(view, "#run-detail-run-id", "run-detail-123")
    assert has_element?(view, "#run-detail-status", "awaiting_approval")
    assert has_element?(view, "#run-detail-current-step", "approval_gate")

    assert has_element?(view, "#run-detail-timeline-entry-1")
    assert has_element?(view, "#run-detail-timeline-transition-1", "pending")
    assert has_element?(view, "#run-detail-timeline-step-1", "queued")
    assert has_element?(view, "#run-detail-timeline-duration-1", "1m 0s")
    assert has_element?(view, "#run-detail-timeline-at-1", "2026-02-14T22:00:00Z")

    assert has_element?(view, "#run-detail-timeline-entry-2")
    assert has_element?(view, "#run-detail-timeline-transition-2", "running")
    assert has_element?(view, "#run-detail-timeline-step-2", "plan_changes")
    assert has_element?(view, "#run-detail-timeline-duration-2", "1m 0s")
    assert has_element?(view, "#run-detail-timeline-at-2", "2026-02-14T22:01:00Z")

    assert has_element?(view, "#run-detail-timeline-entry-3")
    assert has_element?(view, "#run-detail-timeline-transition-3", "awaiting_approval")
    assert has_element?(view, "#run-detail-timeline-step-3", "approval_gate")
    assert has_element?(view, "#run-detail-timeline-duration-3", "unknown")
    assert has_element?(view, "#run-detail-timeline-at-3", "2026-02-14T22:02:00Z")
  end

  test "updates timeline entries in near real time for active runs and marks missing duration as unknown",
       %{conn: _conn} do
    register_owner("timeline-live-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("timeline-live-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-live-timeline",
        github_full_name: "owner/repo-run-detail-live-timeline",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-detail-live-timeline-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render near real-time timeline"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 22:10:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 22:11:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "running")
    assert has_element?(view, "#run-detail-timeline-transition-2", "running")
    assert has_element?(view, "#run-detail-timeline-duration-2", "unknown")

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 22:12:00Z]
      })

    assert_eventually(fn ->
      has_element?(view, "#run-detail-status", "awaiting_approval") and
        has_element?(view, "#run-detail-timeline-transition-3", "awaiting_approval") and
        has_element?(view, "#run-detail-timeline-duration-2", "1m 0s") and
        has_element?(view, "#run-detail-timeline-duration-3", "unknown")
    end)
  end

  test "renders governed evidence and review state alongside workflow-run compatibility details", %{
    conn: _conn
  } do
    register_owner("governed-run-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("governed-run-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-governed-run-detail",
        github_full_name: "owner/repo-governed-run-detail",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-governed-detail-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render governance panels"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "governed-run-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-03-31 21:00:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+14/-2).",
          "test_summary" => "mix test: 12 passed, 0 failed.",
          "risk_notes" => ["Touches governed run presentation paths."],
          "approval_context" => %{
            "diff_summary" => "2 files changed (+14/-2).",
            "test_summary" => "mix test: 12 passed, 0 failed.",
            "risk_notes" => ["Touches governed run presentation paths."]
          }
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-03-31 21:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-03-31 21:02:00Z]
      })

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/projects/#{project.id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(view, "#run-detail-current-stage", "approval")
    assert has_element?(view, "#run-detail-evidence-list")
    assert has_element?(view, "#run-detail-evidence-key-1")
    assert has_element?(view, "#run-detail-change-request-status", "open")
    assert has_element?(view, "#run-detail-decisions-empty")
  end

  test "renders bounded runtime evidence using product-oriented posture language", %{conn: _conn} do
    register_owner("runtime-run-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("runtime-run-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-runtime-run-detail",
        github_full_name: "owner/repo-runtime-run-detail",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-runtime-detail-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "coding_turn_plan",
        workflow_version: 1,
        trigger: %{
          source: "public_turn_runtime",
          mode: "conversation_runtime",
          turn_id: "turn-run-detail-1"
        },
        inputs: %{"turn_id" => "turn-run-detail-1"},
        input_metadata: %{"turn_id" => %{required: true, source: "test"}},
        initiating_actor: %{id: "owner-1", email: "runtime-run-owner@example.com"},
        current_step: "public_turn_materialized",
        started_at: ~U[2026-04-01 12:00:00Z],
        step_results: %{
          "coding_turn_summary" => %{
            "turn_id" => "turn-run-detail-1",
            "conversation_id" => "conversation-run-detail-1",
            "state" => "completed",
            "assistant_output" => %{"message" => "Live delivery resumed through replay."}
          },
          "runtime_service_delivery" => %{
            "delivery_mode" => "replay_recovery",
            "reason_code" => "live_delivery_detached",
            "terminal_handoff_kind" => "replay_terminal_lookup",
            "terminal_state" => "completed",
            "turn_id" => "turn-run-detail-1",
            "session_id" => "conversation-run-detail-1",
            "conversation_id" => "conversation-run-detail-1",
            "summary" => "Coding turn delivery repaired through replay recovery."
          }
        }
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "public_turn_in_progress",
        transitioned_at: ~U[2026-04-01 12:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-01 12:02:00Z]
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, _repo_posture} =
      RepoPosture.upsert_for_managed_repo(
        %{
          managed_repo_id: managed_repo.id,
          summary: "Repo posture remains governed.",
          overall_trust: "medium",
          execution_readiness: "medium",
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
              "Runtime evidence requires operator review before execution trust can be restored.",
            "runtime_service_evidence_state" => %{
              "status" => "degraded",
              "review_required" => true,
              "runtime_delivery" => %{
                "delivery_mode" => "replay_recovery",
                "reason_code" => "live_delivery_detached"
              },
              "integration_outcomes" => %{
                "latest_invocation" => %{
                  "provider" => "github",
                  "summary" => "github installation delivery recovered"
                }
              }
            }
          }
        },
        actor: Actor.operator_actor()
      )

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/projects/#{project.id}/runs/#{run_id}", on_error: :warn)

    vue =
      assert_vue_component(
        view,
        "RunGovernanceOverviewWidget",
        id: "run-detail-governance-overview-widget"
      )

    assert vue.props["runStatus"] == "awaiting_approval"
    assert vue.props["runtimeEvidence"]["statusLabel"] == "review required"
    assert vue.props["evidenceCount"] == 3
    assert vue.props["decisionCount"] == 0

    assert has_element?(view, "#run-detail-runtime-evidence")
    assert has_element?(view, "#run-detail-runtime-evidence-status", "review required")

    assert has_element?(
             view,
             "#run-detail-runtime-evidence-summary",
             "operator review before execution trust can be restored"
           )

    assert has_element?(
             view,
             "#run-detail-runtime-evidence-delivery-mode",
             "replay recovery"
           )

    assert has_element?(
             view,
             "#run-detail-runtime-evidence-reason",
             "live delivery detached"
           )

    assert has_element?(
             view,
             "#run-detail-runtime-evidence-integration",
             "github installation delivery recovered"
           )

    assert has_element?(view, "#run-detail-runtime-evidence-note", "Product governance stores bounded runtime evidence")
  end

  test "renders run artifact browser categories with stable view identifiers", %{conn: _conn} do
    register_owner("artifact-browser-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("artifact-browser-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-artifact-browser",
        github_full_name: "owner/repo-run-detail-artifact-browser",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-detail-artifact-browser-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render artifact browser"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "artifact-browser-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 06:45:00Z],
        step_results: %{
          "run_logs" => [
            %{
              "event" => "step_started",
              "message" => "Preparing implementation branch."
            }
          ],
          "diff_summary" => "3 files changed (+12/-3).",
          "failure_report" => %{
            "step" => "run_tests",
            "summary" => "1 test failed in CI."
          },
          "pull_request" => %{
            "number" => 451,
            "url" => "https://github.com/owner/repo-run-detail-artifact-browser/pull/451",
            "head_branch" => "jidocode/implement-task/run-abc123"
          }
        }
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-artifact-browser")
    assert has_element?(view, "#run-detail-artifact-category-title-logs", "Logs")

    assert has_element?(
             view,
             "#run-detail-artifact-category-title-diff_summaries",
             "Diff summaries"
           )

    assert has_element?(view, "#run-detail-artifact-category-title-reports", "Reports")
    assert has_element?(view, "#run-detail-artifact-category-title-pr_metadata", "PR metadata")

    assert has_element?(view, "#run-detail-artifact-entry-logs-run-logs")
    assert has_element?(view, "#run-detail-artifact-view-logs-run-logs", "View artifact")
    assert has_element?(view, "#run-detail-artifact-source-logs-run-logs", "run_logs")

    assert has_element?(view, "#run-detail-artifact-entry-diff-summaries-diff-summary")

    assert has_element?(
             view,
             "#run-detail-artifact-view-diff-summaries-diff-summary",
             "View artifact"
           )

    assert has_element?(view, "#run-detail-artifact-entry-reports-failure-report")
    assert has_element?(view, "#run-detail-artifact-view-reports-failure-report", "View artifact")

    assert has_element?(view, "#run-detail-artifact-entry-pr-metadata-pull-request")

    assert has_element?(
             view,
             "#run-detail-artifact-view-pr-metadata-pull-request",
             "View artifact"
           )

    assert has_element?(
             view,
             "#run-detail-artifact-payload-content-pr-metadata-pull-request",
             "pull/451"
           )

    refute has_element?(view, "#run-detail-artifact-category-missing-logs")
    refute has_element?(view, "#run-detail-artifact-category-missing-diff_summaries")
    refute has_element?(view, "#run-detail-artifact-category-missing-reports")
    refute has_element?(view, "#run-detail-artifact-category-missing-pr_metadata")
  end

  test "shows missing artifact status per category when artifact records are unavailable", %{
    conn: _conn
  } do
    register_owner("artifact-missing-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("artifact-missing-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-artifact-missing",
        github_full_name: "owner/repo-run-detail-artifact-missing",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-detail-artifact-missing-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render missing artifact states"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "artifact-missing-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 06:50:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+2/-0)."
        }
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-title", "Workflow run detail")
    assert has_element?(view, "#run-detail-artifact-browser")
    assert has_element?(view, "#run-detail-artifact-entry-diff-summaries-diff-summary")
    refute has_element?(view, "#run-detail-artifact-category-missing-diff_summaries")

    assert has_element?(
             view,
             "#run-detail-artifact-category-missing-logs",
             "Missing artifact records for this category."
           )

    assert has_element?(
             view,
             "#run-detail-artifact-category-missing-reports",
             "Missing artifact records for this category."
           )

    assert has_element?(
             view,
             "#run-detail-artifact-category-missing-pr_metadata",
             "Missing artifact records for this category."
           )
  end

  test "renders issue triage artifact set for issue_triage workflow runs", %{conn: _conn} do
    register_owner("issue-triage-artifacts-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("issue-triage-artifacts-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-issue-triage-artifacts",
        github_full_name: "owner/repo-run-detail-issue-triage-artifacts",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-detail-issue-triage-artifacts-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{
          source: "github_webhook",
          mode: "webhook",
          source_issue: %{"number" => 91, "id" => 91_001}
        },
        inputs: %{"issue_reference" => "owner/repo-run-detail-issue-triage-artifacts#91"},
        input_metadata: %{
          "issue_reference" => %{
            "required" => true,
            "source" => "github_webhook",
            "source_issue" => %{"number" => 91, "id" => 91_001}
          }
        },
        initiating_actor: %{id: "github_webhook", email: nil},
        current_step: "queued",
        started_at: ~U[2026-02-15 06:00:00Z],
        step_results: %{
          "run_issue_triage" => %{
            "classification" => "bug",
            "summary" => "Issue triage classified this report as bug.",
            "linked_run" => %{
              "run_id" => run_id,
              "workflow_name" => "issue_triage",
              "issue_reference" => "owner/repo-run-detail-issue-triage-artifacts#91",
              "source_issue" => %{"number" => 91, "id" => 91_001}
            }
          },
          "run_issue_research" => %{
            "summary" => "Initial research summary for issue reproduction and root-cause direction.",
            "linked_run" => %{
              "run_id" => run_id,
              "workflow_name" => "issue_triage",
              "issue_reference" => "owner/repo-run-detail-issue-triage-artifacts#91",
              "source_issue" => %{"number" => 91, "id" => 91_001}
            }
          },
          "compose_issue_response" => %{
            "proposed_response" => "Thanks for the report. We triaged this as bug and prepared a response draft.",
            "linked_run" => %{
              "run_id" => run_id,
              "workflow_name" => "issue_triage",
              "issue_reference" => "owner/repo-run-detail-issue-triage-artifacts#91",
              "source_issue" => %{"number" => 91, "id" => 91_001}
            }
          },
          "issue_bot_artifact_lineage" => %{
            "status" => "persisted",
            "artifact_keys" => [
              "compose_issue_response",
              "run_issue_research",
              "run_issue_triage"
            ],
            "linked_run" => %{
              "run_id" => run_id,
              "workflow_name" => "issue_triage",
              "issue_reference" => "owner/repo-run-detail-issue-triage-artifacts#91",
              "source_issue" => %{"number" => 91, "id" => 91_001}
            }
          },
          "post_issue_response" => %{
            "status" => "posted",
            "provider" => "github",
            "posted" => true,
            "approval_mode" => "auto_post",
            "approval_decision" => "auto_approved",
            "comment_url" =>
              "https://github.com/owner/repo-run-detail-issue-triage-artifacts/issues/91#issuecomment-91001",
            "comment_id" => 91_001,
            "posted_at" => "2026-02-15T06:02:00Z"
          }
        }
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-issue-triage-artifacts")
    assert has_element?(view, "#run-detail-issue-artifact-persistence-status", "persisted")
    assert has_element?(view, "#run-detail-issue-triage-classification", "bug")

    assert has_element?(
             view,
             "#run-detail-issue-research-summary",
             "Initial research summary for issue reproduction and root-cause direction."
           )

    assert has_element?(
             view,
             "#run-detail-issue-response-draft",
             "We triaged this as bug and prepared a response draft."
           )

    assert has_element?(view, "#run-detail-issue-response-post-status", "posted")

    assert has_element?(
             view,
             "#run-detail-issue-response-post-url",
             "https://github.com/owner/repo-run-detail-issue-triage-artifacts/issues/91#issuecomment-91001"
           )

    assert has_element?(view, "#run-detail-issue-response-post-comment-id", "91001")
    assert has_element?(view, "#run-detail-issue-response-posted-at", "2026-02-15T06:02:00Z")

    assert has_element?(
             view,
             "#run-detail-issue-artifact-issue-reference",
             "owner/repo-run-detail-issue-triage-artifacts#91"
           )

    assert has_element?(view, "#run-detail-issue-artifact-source-issue-number", "91")
    assert has_element?(view, "#run-detail-issue-artifact-run-id", run_id)
    refute has_element?(view, "#run-detail-issue-artifact-persistence-error")
    refute has_element?(view, "#run-detail-issue-response-post-error")
  end

  test "renders typed Issue Bot response post failure artifact details", %{conn: _conn} do
    register_owner("issue-triage-post-failure-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("issue-triage-post-failure-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-issue-triage-post-failure",
        github_full_name: "owner/repo-run-detail-issue-triage-post-failure",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-detail-issue-triage-post-failure-#{System.unique_integer([:positive])}"

    {:ok, _run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{
          source: "github_webhook",
          mode: "webhook",
          source_issue: %{"number" => 102, "id" => 102_001}
        },
        inputs: %{"issue_reference" => "owner/repo-run-detail-issue-triage-post-failure#102"},
        input_metadata: %{
          "issue_reference" => %{
            "required" => true,
            "source" => "github_webhook"
          }
        },
        initiating_actor: %{id: "github_webhook", email: nil},
        current_step: "post_github_comment",
        started_at: ~U[2026-02-15 06:30:00Z],
        step_results: %{
          "run_issue_triage" => %{"classification" => "bug"},
          "run_issue_research" => %{"summary" => "Research summary for failed posting run."},
          "compose_issue_response" => %{
            "proposed_response" => "Thanks for the report. We attempted to post this response."
          },
          "post_issue_response" => %{
            "status" => "failed",
            "provider" => "github",
            "posted" => false,
            "approval_mode" => "approval_required",
            "approval_decision" => "approved",
            "attempted_at" => "2026-02-15T06:31:00Z",
            "typed_failure" => %{
              "error_type" => "github_issue_comment_authentication_failed",
              "reason_type" => "auth_error",
              "detail" => "Bad credentials for GitHub issue comment post.",
              "remediation" => "Rotate posting token and retry."
            }
          }
        }
      })

    {:ok, run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run_id
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "post_github_comment",
        transitioned_at: ~U[2026-02-15 06:30:30Z]
      })

    {:ok, _failed_run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "post_github_comment",
        transitioned_at: ~U[2026-02-15 06:31:00Z],
        transition_metadata: %{
          "typed_failure" => %{
            "error_type" => "github_issue_comment_authentication_failed",
            "reason_type" => "auth_error",
            "detail" => "Bad credentials for GitHub issue comment post.",
            "remediation" => "Rotate posting token and retry.",
            "failed_step" => "post_github_comment",
            "last_successful_step" => "compose_issue_response"
          }
        }
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-issue-response-post-status", "failed")
    assert has_element?(view, "#run-detail-issue-response-post-error")

    assert has_element?(
             view,
             "#run-detail-issue-response-post-error-type",
             "github_issue_comment_authentication_failed"
           )

    assert has_element?(
             view,
             "#run-detail-issue-response-post-error-detail",
             "Bad credentials for GitHub issue comment post."
           )

    assert has_element?(
             view,
             "#run-detail-issue-response-post-error-remediation",
             "Rotate posting token and retry."
           )

    refute has_element?(view, "#run-detail-issue-response-post-url")
  end

  test "renders approval payload context and enables explicit approve action", %{
    conn: _conn
  } do
    register_owner("approval-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval",
        github_full_name: "owner/repo-run-detail-approval",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render approval payload"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:00:00Z],
        step_results: %{
          "diff_summary" => "3 files changed (+42/-8).",
          "test_summary" => "mix test: 120 passed, 0 failed.",
          "risk_notes" => [
            "Touches approval gate orchestration.",
            "No credential or secret writes detected."
          ]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:02:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-approval-diff-summary", "3 files changed (+42/-8).")

    assert has_element?(
             view,
             "#run-detail-approval-test-summary",
             "mix test: 120 passed, 0 failed."
           )

    assert has_element?(
             view,
             "#run-detail-approval-risk-note-1",
             "Touches approval gate orchestration."
           )

    assert has_element?(
             view,
             "#run-detail-approval-risk-note-2",
             "No credential or secret writes detected."
           )

    assert has_element?(view, "#run-detail-approve-button")
    refute has_element?(view, "#run-detail-approve-button[disabled]")
    assert has_element?(view, "#run-detail-reject-button")
    refute has_element?(view, "#run-detail-reject-button[disabled]")
  end

  test "approves awaiting run, resumes execution, and records timeline audit metadata", %{
    conn: _conn
  } do
    register_owner("approval-resume-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-resume-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval-resume",
        github_full_name: "owner/repo-run-detail-approval-resume",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-resume-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Resume on approval"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:05:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+9/-1).",
          "test_summary" => "mix test: 18 passed, 0 failed.",
          "risk_notes" => ["Touches approval resume wiring."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:06:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:07:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_click(element(view, "#run-detail-approve-button"))

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    timeline_index = length(persisted_run.status_transitions)

    assert has_element?(view, "#run-detail-status", "running")
    refute has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-timeline-transition-#{timeline_index}", "running")
    assert has_element?(view, "#run-detail-timeline-step-#{timeline_index}", "resume_execution")

    assert has_element?(
             view,
             "#run-detail-timeline-approval-audit-#{timeline_index}",
             "approval-resume-owner@example.com"
           )

    assert persisted_run.status == :running
    assert get_in(persisted_run.step_results, ["approval_decision", "decision"]) == "approved"

    assert get_in(persisted_run.step_results, ["approval_decision", "actor", "email"]) ==
             "approval-resume-owner@example.com"
  end

  test "shows typed approval action failure when approval context generation is blocked", %{
    conn: _conn
  } do
    register_owner("approval-failure-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("approval-failure-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-approval-failure",
        github_full_name: "owner/repo-run-detail-approval-failure",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-approval-failure-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Block approval payload"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:10:00Z],
        step_results: %{
          "approval_context_generation_error" => "Git diff artifact is missing from prior step output."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:11:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:12:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-context-missing",
             "Approval context is unavailable."
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-error-message",
             "Approval context generation failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-error-detail",
             "Git diff artifact is missing from prior step output."
           )

    assert has_element?(
             view,
             "#run-detail-approval-context-remediation",
             "Publish diff summary, test summary, and risk notes"
           )

    render_click(element(view, "#run-detail-approve-button"))

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-action-error-type",
             "workflow_run_approval_action_failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-detail",
             "Approve action is blocked because approval context generation failed."
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-remediation",
             "Regenerate diff summary, test summary, and risk notes before retrying approval."
           )

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert has_element?(view, "#run-detail-reject-button")
  end

  test "rejects awaiting run in run detail with rationale metadata and cancelled state", %{
    conn: _conn
  } do
    register_owner("rejection-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("rejection-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-rejection",
        github_full_name: "owner/repo-run-detail-rejection",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-rejection-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Reject run from run detail"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:20:00Z],
        step_results: %{
          "diff_summary" => "5 files changed (+64/-20).",
          "test_summary" => "mix test: 77 passed, 0 failed.",
          "risk_notes" => ["Requires a second pass before shipping."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:22:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_submit(element(view, "#run-detail-reject-form"), %{
      "rationale" => "Needs clearer test coverage before merge."
    })

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    timeline_index = length(persisted_run.status_transitions)

    assert has_element?(view, "#run-detail-status", "cancelled")
    refute has_element?(view, "#run-detail-approval-panel")
    assert has_element?(view, "#run-detail-timeline-transition-#{timeline_index}", "cancelled")
    assert has_element?(view, "#run-detail-timeline-step-#{timeline_index}", "approval_gate")

    assert has_element?(
             view,
             "#run-detail-timeline-approval-audit-#{timeline_index}",
             "rationale=Needs clearer test coverage before merge."
           )

    assert persisted_run.status == :cancelled
    assert get_in(persisted_run.step_results, ["approval_decision", "decision"]) == "rejected"

    assert get_in(persisted_run.step_results, ["approval_decision", "rationale"]) ==
             "Needs clearer test coverage before merge."
  end

  test "shows typed rejection retry guidance when rejection policy routing is invalid", %{
    conn: _conn
  } do
    register_owner("rejection-failure-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("rejection-failure-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-rejection-failure",
        github_full_name: "owner/repo-run-detail-rejection-failure",
        default_branch: "main",
        settings: %{}
      })

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-detail-rejection-failure-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{
          source: "workflows",
          mode: "manual",
          approval_policy: %{
            on_reject: %{
              action: "retry_route",
              retry_step: " "
            }
          }
        },
        inputs: %{"task_summary" => "Reject run with invalid policy"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 23:30:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+2/-1).",
          "test_summary" => "mix test: 12 passed, 0 failed.",
          "risk_notes" => ["Rejection policy validation test."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:31:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 23:32:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{run.run_id}",
        on_error: :warn
      )

    render_submit(element(view, "#run-detail-reject-form"), %{
      "rationale" => "Routing policy is invalid."
    })

    assert has_element?(view, "#run-detail-status", "awaiting_approval")

    assert has_element?(
             view,
             "#run-detail-approval-action-error-type",
             "workflow_run_approval_action_failed"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-detail",
             "retry route"
           )

    assert has_element?(
             view,
             "#run-detail-approval-action-error-remediation",
             "retry rejection"
           )

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert persisted_run.current_step == "approval_gate"
  end

  test "renders standardized failure context with remediation hints for failed runs", %{
    conn: _conn
  } do
    register_owner("failure-context-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("failure-context-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-failure-context",
        github_full_name: "owner/repo-run-detail-failure-context",
        default_branch: "main",
        settings: %{}
      })

    failed_run_id = "run-detail-failure-context-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render typed failure context"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:40:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 04:41:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:42:00Z],
        transition_metadata: %{
          "failure_context" => %{
            "error_type" => "workflow_step_failed",
            "reason_type" => "verification_failed",
            "detail" => "Verification failed while running test suite.",
            "remediation" => "Inspect failing tests, patch, and retry from run detail.",
            "last_successful_step" => "plan_changes"
          }
        }
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{failed_run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "failed")
    assert has_element?(view, "#run-detail-failure-context")
    assert has_element?(view, "#run-detail-failure-error-type", "workflow_step_failed")
    assert has_element?(view, "#run-detail-failure-reason-type", "verification_failed")
    assert has_element?(view, "#run-detail-failure-last-successful-step", "plan_changes")
    assert has_element?(view, "#run-detail-failure-failed-step", "run_tests")
    assert has_element?(view, "#run-detail-failure-remediation", "retry from run detail")
    refute has_element?(view, "#run-detail-failure-missing-fields")
  end

  test "renders missing failure context fields when only minimal typed reason is available", %{
    conn: _conn
  } do
    register_owner("failure-context-minimal-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("failure-context-minimal-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-failure-context-minimal",
        github_full_name: "owner/repo-run-detail-failure-context-minimal",
        default_branch: "main",
        settings: %{}
      })

    failed_run_id = "run-detail-failure-context-minimal-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render missing failure fields"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:50:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:51:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:52:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{failed_run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "failed")
    assert has_element?(view, "#run-detail-failure-error-type", "workflow_run_failed")
    assert has_element?(view, "#run-detail-failure-reason-type", "workflow_run_failed")
    assert has_element?(view, "#run-detail-failure-last-successful-step", "unknown")
    assert has_element?(view, "#run-detail-failure-remediation", "retry from run detail")
    assert has_element?(view, "#run-detail-failure-missing-fields", "error_type")
    assert has_element?(view, "#run-detail-failure-missing-fields", "remediation")
    assert has_element?(view, "#run-detail-failure-missing-fields", "last_successful_step")
  end

  test "retries a failed run from run detail and preserves prior failure lineage on the new attempt",
       %{
         conn: _conn
       } do
    register_owner("retry-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("retry-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-retry",
        github_full_name: "owner/repo-run-detail-retry",
        default_branch: "main",
        settings: %{}
      })

    failed_run_id = "run-detail-retry-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Retry failed run from detail"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 05:00:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "2 tests failed."},
          "diff_summary" => "4 files changed (+50/-7)."
        },
        error: %{
          "error_type" => "workflow_step_failed",
          "reason_type" => "verification_failed",
          "detail" => "Verification failed while running test suite."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:01:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:02:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{failed_run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-status", "failed")
    assert has_element?(view, "#run-detail-retry-button")

    render_click(element(view, "#run-detail-retry-button"))

    retry_run_id = "#{failed_run_id}-retry-2"
    retry_path = ~p"/projects/#{project.id}/runs/#{retry_run_id}"
    assert_redirect(view, retry_path)

    {:ok, retried_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: retry_run_id
      })

    assert retried_run.retry_of_run_id == failed_run_id
    assert retried_run.retry_attempt == 2
    assert [%{"run_id" => ^failed_run_id}] = retried_run.retry_lineage

    {:ok, retry_view, _html} = live(recycle(authed_conn), retry_path, on_error: :warn)

    assert has_element?(retry_view, "#run-detail-retry-parent-run", failed_run_id)
    assert has_element?(retry_view, "#run-detail-retry-lineage-run-id-1", failed_run_id)

    assert has_element?(
             retry_view,
             "#run-detail-retry-lineage-reason-type-1",
             "verification_failed"
           )

    assert has_element?(retry_view, "#run-detail-retry-lineage-artifact-count-1", "2")
  end

  test "blocks retry from run detail with typed policy violation details when retry policy disallows full-run",
       %{
         conn: _conn
       } do
    register_owner("retry-policy-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("retry-policy-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-retry-policy-blocked",
        github_full_name: "owner/repo-run-detail-retry-policy-blocked",
        default_branch: "main",
        settings: %{}
      })

    blocked_run_id = "run-detail-retry-policy-blocked-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: blocked_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{
          source: "workflows",
          mode: "manual",
          retry_policy: %{full_run: false, mode: "step_only"}
        },
        inputs: %{"task_summary" => "Retry blocked by policy"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 05:10:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "1 test failed."}
        },
        error: %{
          "error_type" => "workflow_step_failed",
          "reason_type" => "verification_failed",
          "detail" => "Verification failed while running test suite."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:11:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:12:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{blocked_run_id}",
        on_error: :warn
      )

    render_click(element(view, "#run-detail-retry-button"))

    assert has_element?(view, "#run-detail-status", "failed")

    assert has_element?(
             view,
             "#run-detail-retry-action-error-type",
             "workflow_run_retry_action_failed"
           )

    assert has_element?(view, "#run-detail-retry-action-error-detail", "disallowed")
    assert has_element?(view, "#run-detail-retry-action-error-remediation", "retry policy")

    {:ok, no_retry_runs} =
      WorkflowRun.read(
        query: [
          filter: [project_id: project.id, run_id: "#{blocked_run_id}-retry-2"]
        ]
      )

    assert no_retry_runs == []
  end

  test "shows step-level retry control only for workflows that declare step retry and preserves lineage on retry",
       %{conn: _conn} do
    register_owner("step-retry-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("step-retry-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-step-retry",
        github_full_name: "owner/repo-run-detail-step-retry",
        default_branch: "main",
        settings: %{}
      })

    failed_run_id = "run-detail-step-retry-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{
          source: "workflows",
          mode: "manual",
          retry_policy: %{full_run: false, mode: "step_only", retry_step: "run_tests"}
        },
        inputs: %{"task_summary" => "Retry from contract step"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 05:20:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "2 tests failed."}
        },
        error: %{
          "error_type" => "workflow_step_failed",
          "reason_type" => "verification_failed",
          "detail" => "Verification failed while running test suite."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:21:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:22:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{failed_run_id}",
        on_error: :warn
      )

    assert has_element?(view, "#run-detail-step-retry-button")
    assert has_element?(view, "#run-detail-step-retry-note", "run_tests")
    refute has_element?(view, "#run-detail-step-retry-guidance")

    render_click(element(view, "#run-detail-step-retry-button"))

    retry_run_id = "#{failed_run_id}-retry-2"
    retry_path = ~p"/projects/#{project.id}/runs/#{retry_run_id}"
    assert_redirect(view, retry_path)

    {:ok, retried_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: retry_run_id
      })

    assert retried_run.current_step == "run_tests"
    assert retried_run.retry_of_run_id == failed_run_id
    assert get_in(retried_run.step_results, ["retry_context", "policy"]) == "step_level"
    assert get_in(retried_run.step_results, ["retry_context", "retry_step"]) == "run_tests"

    {:ok, retry_view, _html} = live(recycle(authed_conn), retry_path, on_error: :warn)
    assert has_element?(retry_view, "#run-detail-retry-parent-run", failed_run_id)
    assert has_element?(retry_view, "#run-detail-retry-lineage-run-id-1", failed_run_id)
  end

  test "hides step-level retry control and shows guidance when workflow contract does not declare step retry",
       %{conn: _conn} do
    register_owner("step-retry-guidance-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("step-retry-guidance-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-run-detail-step-retry-guidance",
        github_full_name: "owner/repo-run-detail-step-retry-guidance",
        default_branch: "main",
        settings: %{}
      })

    failed_run_id = "run-detail-step-retry-guidance-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Step-level retry guidance"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 05:30:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "1 test failed."}
        },
        error: %{
          "error_type" => "workflow_step_failed",
          "reason_type" => "verification_failed",
          "detail" => "Verification failed while running test suite."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:31:00Z]
      })

    {:ok, _run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 05:32:00Z]
      })

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/projects/#{project.id}/runs/#{failed_run_id}",
        on_error: :warn
      )

    refute has_element?(view, "#run-detail-step-retry-button")
    assert has_element?(view, "#run-detail-step-retry-guidance-detail", "does not declare")
    assert has_element?(view, "#run-detail-step-retry-guidance-remediation", "step-level retry")
  end

  defp assert_eventually(assertion_fun, attempts \\ 20)

  defp assert_eventually(assertion_fun, attempts) when attempts > 0 do
    if assertion_fun.() do
      :ok
    else
      receive do
      after
        25 ->
          assert_eventually(assertion_fun, attempts - 1)
      end
    end
  end

  defp assert_eventually(_assertion_fun, 0) do
    flunk("expected condition to become true")
  end
end
