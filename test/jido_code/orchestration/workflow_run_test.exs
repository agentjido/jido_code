defmodule JidoCode.Orchestration.WorkflowRunTest do
  # covers: architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.Actor
  alias JidoCode.Orchestration.{RunPubSub, WorkflowRun}
  alias JidoCode.Projects.Project

  defmodule FailingRunEventBroadcaster do
    def broadcast(_pubsub, _topic, _message),
      do: {:error, %{error_type: "forced_publish_failure"}}
  end

  setup do
    original_broadcaster =
      Application.get_env(:jido_code, :workflow_run_event_broadcaster, Phoenix.PubSub)

    original_issue_triage_response_poster =
      Application.get_env(:jido_code, :issue_triage_response_poster, :__missing__)

    on_exit(fn ->
      Application.put_env(:jido_code, :workflow_run_event_broadcaster, original_broadcaster)
      restore_env(:issue_triage_response_poster, original_issue_triage_response_poster)
    end)

    Application.put_env(:jido_code, :workflow_run_event_broadcaster, Phoenix.PubSub)
    :ok
  end

  test "persists allowed lifecycle transitions with timestamps and current step context" do
    {:ok, project} = create_project("owner/repo-lifecycle")

    started_at = ~U[2026-02-14 20:00:00Z]
    running_at = ~U[2026-02-14 20:01:00Z]
    awaiting_approval_at = ~U[2026-02-14 20:02:00Z]
    resumed_at = ~U[2026-02-14 20:03:00Z]
    completed_at = ~U[2026-02-14 20:04:00Z]

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-lifecycle-123",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Persist lifecycle transitions"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: started_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: running_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: awaiting_approval_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "apply_feedback",
        transitioned_at: resumed_at
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: completed_at
      })

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :completed
    assert persisted_run.current_step == "publish_pr"

    assert DateTime.compare(DateTime.truncate(persisted_run.started_at, :second), started_at) ==
             :eq

    assert DateTime.compare(DateTime.truncate(persisted_run.completed_at, :second), completed_at) ==
             :eq

    assert [
             %{
               "from_status" => nil,
               "to_status" => "pending",
               "current_step" => "queued",
               "transitioned_at" => "2026-02-14T20:00:00Z"
             },
             %{
               "from_status" => "pending",
               "to_status" => "running",
               "current_step" => "plan_changes",
               "transitioned_at" => "2026-02-14T20:01:00Z"
             },
             %{
               "from_status" => "running",
               "to_status" => "awaiting_approval",
               "current_step" => "approval_gate",
               "transitioned_at" => "2026-02-14T20:02:00Z"
             },
             %{
               "from_status" => "awaiting_approval",
               "to_status" => "running",
               "current_step" => "apply_feedback",
               "transitioned_at" => "2026-02-14T20:03:00Z"
             },
             %{
               "from_status" => "running",
               "to_status" => "completed",
               "current_step" => "publish_pr",
               "transitioned_at" => "2026-02-14T20:04:00Z"
             }
           ] = persisted_run.status_transitions
  end

  test "requires an explicit actor for workflow run creation when the compatibility policy actor is absent" do
    {:ok, project} = create_project("owner/repo-run-policy")
    Actor.clear_policy_actor()

    assert {:error, %Ash.Error.Forbidden{}} =
             WorkflowRun.create(%{
               project_id: project.id,
               run_id: "run-policy-denied",
               workflow_name: "implement_task",
               workflow_version: 1,
               trigger: %{source: "workflows", mode: "manual"},
               inputs: %{"task_summary" => "Denied without actor"},
               input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
               initiating_actor: %{id: "owner-1", email: "owner@example.com"},
               current_step: "queued",
               started_at: ~U[2026-02-14 20:10:00Z]
             })

    assert {:ok, %WorkflowRun{} = run} =
             WorkflowRun.create(
               %{
                 project_id: project.id,
                 run_id: "run-policy-allowed",
                 workflow_name: "implement_task",
                 workflow_version: 1,
                 trigger: %{source: "workflows", mode: "manual"},
                 inputs: %{"task_summary" => "Allowed with actor"},
                 input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
                 initiating_actor: %{
                   id: "orchestrator-1",
                   email: "orchestrator-1@example.com",
                   actor_class: "managed_repo_orchestrator"
                 },
                 current_step: "queued",
                 started_at: ~U[2026-02-14 20:11:00Z]
               },
               actor:
                 Actor.managed_repo_orchestrator_actor(%{
                   "id" => "orchestrator-1",
                   "email" => "orchestrator-1@example.com"
                 })
             )

    assert run.run_id == "run-policy-allowed"
    assert get_in(run.initiating_actor, ["actor_class"]) == "managed_repo_orchestrator"
  end

  test "preserves actor class in retry lineage and retried run attribution" do
    {:ok, project} = create_project("owner/repo-retry-actor-class")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-retry-actor-class-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Preserve retry actor class"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-20 01:10:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-20 01:11:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-20 01:12:00Z]
      })

    retry_actor = Actor.operator_actor(%{"id" => "reviewer-1", "email" => "reviewer@example.com"})

    assert {:ok, %WorkflowRun{} = retried_run} =
             WorkflowRun.retry(run, %{
               actor: retry_actor,
               retry_started_at: ~U[2026-02-20 01:13:00Z]
             })

    assert get_in(retried_run.initiating_actor, ["actor_class"]) == "operator"
    assert get_in(List.last(retried_run.retry_lineage), ["retry_actor", "actor_class"]) == "operator"
    assert get_in(List.last(retried_run.retry_lineage), ["retry_actor", "id"]) == "reviewer-1"
  end

  test "persists typed failure context and exposes remediation metadata for postmortem queries" do
    {:ok, project} = create_project("owner/repo-failure-context")
    run_id = "run-failure-context-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Persist typed failure context"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 01:10:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 01:11:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 01:12:00Z],
        transition_metadata: %{
          "failure_context" => %{
            "error_type" => "workflow_step_failed",
            "reason_type" => "verification_failed",
            "detail" => "Verification failed while running test suite.",
            "remediation" => "Inspect failing tests, patch, then retry from run detail.",
            "last_successful_step" => "plan_changes"
          }
        }
      })

    assert run.status == :failed
    assert get_in(run.error, ["error_type"]) == "workflow_step_failed"
    assert get_in(run.error, ["reason_type"]) == "verification_failed"
    assert get_in(run.error, ["last_successful_step"]) == "plan_changes"
    assert get_in(run.error, ["failed_step"]) == "run_tests"
    assert get_in(run.error, ["remediation"]) =~ "retry from run detail"
    assert get_in(run.error, ["failure_context_complete"]) == true
    assert Map.get(run.error, "missing_failure_context_fields", []) == []

    {:ok, failed_runs} =
      WorkflowRun.read(
        query: [
          filter: [project_id: project.id, status: :failed]
        ]
      )

    assert [%WorkflowRun{run_id: ^run_id} = postmortem_run] = failed_runs
    assert get_in(postmortem_run.error, ["error_type"]) == "workflow_step_failed"
    assert get_in(postmortem_run.error, ["last_successful_step"]) == "plan_changes"
    assert get_in(postmortem_run.error, ["remediation"]) =~ "retry from run detail"
  end

  test "captures minimal typed reason and indicates missing fields when failure context is incomplete" do
    {:ok, project} = create_project("owner/repo-failure-context-minimal")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-failure-context-minimal-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Capture minimal failure context"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 01:20:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 01:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 01:22:00Z]
      })

    assert run.status == :failed
    assert get_in(run.error, ["error_type"]) == "workflow_run_failed"
    assert get_in(run.error, ["reason_type"]) == "workflow_run_failed"
    assert get_in(run.error, ["last_successful_step"]) == "unknown"
    assert get_in(run.error, ["remediation"]) =~ "retry from run detail"
    assert get_in(run.error, ["failure_context_complete"]) == false

    missing_fields = get_in(run.error, ["missing_failure_context_fields"])
    assert "error_type" in missing_fields
    assert "remediation" in missing_fields
    assert "last_successful_step" in missing_fields
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(get_in(run.error, ["timestamp"]))
  end

  test "builds approval context payload with diff test and risk summaries when entering awaiting_approval" do
    {:ok, project} = create_project("owner/repo-approval-context")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-approval-context-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render approval payload"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 02:00:00Z],
        step_results: %{
          "diff_summary" => "3 files changed (+42/-8).",
          "test_summary" => "mix test: 120 passed, 0 failed.",
          "risk_notes" => [
            "Touches workflow dispatch logic for approval gates.",
            "No schema or credential writes detected."
          ]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 02:01:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 02:02:00Z]
      })

    assert run.status == :awaiting_approval

    assert %{
             "diff_summary" => "3 files changed (+42/-8).",
             "test_summary" => "mix test: 120 passed, 0 failed.",
             "risk_notes" => [
               "Touches workflow dispatch logic for approval gates.",
               "No schema or credential writes detected."
             ]
           } = get_in(run.step_results, ["approval_context"])

    assert [] == Map.get(run.error || %{}, "approval_context_diagnostics", [])
  end

  test "keeps run blocked with typed remediation diagnostics when approval context generation fails" do
    {:ok, project} = create_project("owner/repo-approval-context-blocked")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-approval-context-blocked-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Fail approval payload generation"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:00:00Z],
        step_results: %{
          "approval_context_generation_error" => "Git diff artifact is missing from prior step output."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:01:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:02:00Z]
      })

    assert run.status == :awaiting_approval
    assert is_nil(get_in(run.step_results, ["approval_context"]))

    assert [diagnostic] = get_in(run.error, ["approval_context_diagnostics"])
    assert diagnostic["error_type"] == "approval_context_generation_failed"
    assert diagnostic["operation"] == "build_approval_context"
    assert diagnostic["reason_type"] == "approval_payload_blocked"
    assert diagnostic["detail"] =~ "Git diff artifact is missing"
    assert diagnostic["remediation"] =~ "diff summary"
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(diagnostic["timestamp"])
  end

  test "approve transitions run from awaiting_approval to running with approval audit metadata" do
    {:ok, project} = create_project("owner/repo-approval-resume")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-approval-resume-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Resume run after approval"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:10:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+14/-3).",
          "test_summary" => "mix test: 44 passed, 0 failed.",
          "risk_notes" => ["Touches approval gate resume path."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:11:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:12:00Z]
      })

    approved_at = ~U[2026-02-15 03:13:00Z]

    {:ok, approved_run} =
      WorkflowRun.approve(run, %{
        actor: %{id: "maintainer-1", email: "maintainer@example.com"},
        current_step: "resume_execution",
        approved_at: approved_at
      })

    assert approved_run.status == :running
    assert approved_run.current_step == "resume_execution"

    assert %{
             "decision" => "approved",
             "actor" => %{"id" => "maintainer-1", "email" => "maintainer@example.com"},
             "timestamp" => "2026-02-15T03:13:00Z"
           } = get_in(approved_run.step_results, ["approval_decision"])

    assert [
             %{
               "from_status" => "awaiting_approval",
               "to_status" => "running",
               "current_step" => "resume_execution",
               "transitioned_at" => "2026-02-15T03:13:00Z",
               "metadata" => %{
                 "approval_decision" => %{
                   "decision" => "approved",
                   "actor" => %{"id" => "maintainer-1", "email" => "maintainer@example.com"},
                   "timestamp" => "2026-02-15T03:13:00Z"
                 }
               }
             }
           ] = approved_run.status_transitions |> Enum.take(-1)
  end

  test "approve posts issue_triage response and persists posted GitHub URL artifact" do
    {:ok, project} = create_project("owner/repo-issue-triage-approved-post")
    test_pid = self()

    Application.put_env(:jido_code, :issue_triage_response_poster, fn post_request ->
      send(test_pid, {:issue_triage_post_request, post_request})

      {:ok,
       %{
         status: "posted",
         provider: "github",
         comment_url: "https://github.com/owner/repo-issue-triage-approved-post/issues/41#issuecomment-41001",
         comment_api_url: "https://api.github.com/repos/owner/repo-issue-triage-approved-post/issues/comments/41001",
         comment_id: 41_001,
         posted_at: "2026-02-15T04:13:00Z"
       }}
    end)

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-issue-triage-approved-post-#{System.unique_integer([:positive])}",
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{
          source: "github_webhook",
          mode: "webhook",
          source_row: %{"project_github_full_name" => "owner/repo-issue-triage-approved-post"},
          source_issue: %{"id" => 4101, "number" => 41},
          approval_policy: %{"mode" => "approval_required", "auto_post" => false}
        },
        inputs: %{"issue_reference" => "owner/repo-issue-triage-approved-post#41"},
        input_metadata: %{
          "issue_reference" => %{"required" => true, "source" => "github_webhook"}
        },
        initiating_actor: %{id: "github_webhook", email: nil},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:10:00Z],
        step_results: %{
          "run_issue_triage" => %{"classification" => "bug"},
          "run_issue_research" => %{"summary" => "Research summary for issue #41."},
          "compose_issue_response" => %{
            "proposed_response" => "Thanks for reporting this regression. We are preparing a fix."
          }
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_issue_research",
        transitioned_at: ~U[2026-02-15 04:11:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 04:12:00Z]
      })

    {:ok, approved_run} =
      WorkflowRun.approve(run, %{
        actor: %{id: "maintainer-41", email: "maintainer-41@example.com"},
        current_step: "resume_execution",
        approved_at: ~U[2026-02-15 04:13:00Z]
      })

    assert_receive {:issue_triage_post_request, post_request}
    assert post_request.repo_full_name == "owner/repo-issue-triage-approved-post"
    assert post_request.issue_number == 41
    assert post_request.body =~ "Thanks for reporting"

    assert approved_run.status == :completed
    assert approved_run.current_step == "post_github_comment"

    post_artifact = get_in(approved_run.step_results, ["post_issue_response"])

    assert post_artifact["status"] == "posted"
    assert post_artifact["posted"] == true

    assert post_artifact["comment_url"] ==
             "https://github.com/owner/repo-issue-triage-approved-post/issues/41#issuecomment-41001"

    assert post_artifact["comment_id"] == 41_001
    assert post_artifact["approval_mode"] == "approval_required"
    assert post_artifact["approval_decision"] == "approved"

    assert get_in(approved_run.step_results, ["approval_decision", "decision"]) == "approved"
  end

  test "approve captures typed auth post failure for issue_triage and does not mark post successful" do
    {:ok, project} = create_project("owner/repo-issue-triage-post-failure")

    Application.put_env(:jido_code, :issue_triage_response_poster, fn _post_request ->
      {:error,
       %{
         error_type: "github_issue_comment_authentication_failed",
         reason_type: "authentication",
         detail: "GitHub token was rejected.",
         remediation: "Rotate GitHub token and retry posting."
       }}
    end)

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-issue-triage-post-failure-#{System.unique_integer([:positive])}",
        workflow_name: "issue_triage",
        workflow_version: 1,
        trigger: %{
          source: "github_webhook",
          mode: "webhook",
          source_row: %{"project_github_full_name" => "owner/repo-issue-triage-post-failure"},
          source_issue: %{"id" => 5101, "number" => 51},
          approval_policy: %{"mode" => "approval_required", "auto_post" => false}
        },
        inputs: %{"issue_reference" => "owner/repo-issue-triage-post-failure#51"},
        input_metadata: %{
          "issue_reference" => %{"required" => true, "source" => "github_webhook"}
        },
        initiating_actor: %{id: "github_webhook", email: nil},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:20:00Z],
        step_results: %{
          "run_issue_triage" => %{"classification" => "bug"},
          "run_issue_research" => %{"summary" => "Research summary for issue #51."},
          "compose_issue_response" => %{
            "proposed_response" => "We reproduced this issue and will prepare a patch."
          }
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_issue_research",
        transitioned_at: ~U[2026-02-15 04:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 04:22:00Z]
      })

    {:ok, approved_run} =
      WorkflowRun.approve(run, %{
        actor: %{id: "maintainer-51", email: "maintainer-51@example.com"},
        current_step: "resume_execution",
        approved_at: ~U[2026-02-15 04:23:00Z]
      })

    assert approved_run.status == :failed
    assert approved_run.current_step == "post_github_comment"
    assert get_in(approved_run.error, ["error_type"]) == "github_issue_comment_authentication_failed"
    assert get_in(approved_run.error, ["reason_type"]) == "auth_error"
    assert get_in(approved_run.error, ["failed_step"]) == "post_github_comment"
    assert get_in(approved_run.error, ["last_successful_step"]) == "compose_issue_response"

    post_artifact = get_in(approved_run.step_results, ["post_issue_response"])
    post_typed_failure = post_artifact["typed_failure"]

    assert post_artifact["status"] == "failed"
    assert post_artifact["posted"] == false
    assert post_artifact["approval_mode"] == "approval_required"
    assert post_artifact["approval_decision"] == "approved"
    assert is_nil(post_artifact["comment_url"])
    assert post_typed_failure["reason_type"] == "auth_error"
  end

  test "approve keeps run awaiting_approval and returns typed action failure when blocked" do
    {:ok, project} = create_project("owner/repo-approval-failure")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-approval-failure-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Block approval action"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:20:00Z],
        step_results: %{
          "approval_context_generation_error" => "Risk summary artifact is unavailable."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:22:00Z]
      })

    assert {:error, typed_failure} =
             WorkflowRun.approve(run, %{actor: %{id: "owner-1", email: "owner@example.com"}})

    assert typed_failure.error_type == "workflow_run_approval_action_failed"
    assert typed_failure.operation == "approve_run"
    assert typed_failure.reason_type == "approval_context_blocked"
    assert typed_failure.detail =~ "approval context generation failed"
    assert typed_failure.remediation =~ "diff summary"
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(typed_failure.timestamp)

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert persisted_run.current_step == "approval_gate"
  end

  test "reject cancels awaiting run by default and persists rejection metadata" do
    {:ok, project} = create_project("owner/repo-reject-cancel")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-reject-cancel-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Reject and cancel run"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:30:00Z],
        step_results: %{
          "diff_summary" => "4 files changed (+36/-6).",
          "test_summary" => "mix test: 92 passed, 0 failed.",
          "risk_notes" => ["Touches approval rejection path."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:31:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:32:00Z]
      })

    rejected_at = ~U[2026-02-15 03:33:00Z]

    {:ok, rejected_run} =
      WorkflowRun.reject(run, %{
        actor: %{id: "maintainer-2", email: "maintainer@example.com"},
        rationale: "Change does not meet release criteria.",
        rejected_at: rejected_at
      })

    assert rejected_run.status == :cancelled
    assert rejected_run.current_step == "approval_gate"

    assert DateTime.compare(DateTime.truncate(rejected_run.completed_at, :second), rejected_at) ==
             :eq

    assert %{
             "decision" => "rejected",
             "actor" => %{"id" => "maintainer-2", "email" => "maintainer@example.com"},
             "timestamp" => "2026-02-15T03:33:00Z",
             "rationale" => "Change does not meet release criteria.",
             "outcome" => "cancelled"
           } = get_in(rejected_run.step_results, ["approval_decision"])

    assert [
             %{
               "from_status" => "awaiting_approval",
               "to_status" => "cancelled",
               "current_step" => "approval_gate",
               "transitioned_at" => "2026-02-15T03:33:00Z",
               "metadata" => %{
                 "approval_decision" => %{
                   "decision" => "rejected",
                   "actor" => %{"id" => "maintainer-2", "email" => "maintainer@example.com"},
                   "timestamp" => "2026-02-15T03:33:00Z",
                   "rationale" => "Change does not meet release criteria.",
                   "outcome" => "cancelled"
                 }
               }
             }
           ] = rejected_run.status_transitions |> Enum.take(-1)
  end

  test "reject routes awaiting run to configured retry step according to policy" do
    {:ok, project} = create_project("owner/repo-reject-reroute")
    reroute_run_id = "run-reject-reroute-#{System.unique_integer([:positive])}"
    assert :ok = RunPubSub.subscribe_run(reroute_run_id)

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: reroute_run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{
          source: "workflows",
          mode: "manual",
          approval_policy: %{
            on_reject: %{
              action: "retry_route",
              retry_step: "revise_plan"
            }
          }
        },
        inputs: %{"task_summary" => "Reject and reroute run"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:40:00Z],
        step_results: %{
          "diff_summary" => "2 files changed (+10/-2).",
          "test_summary" => "mix test: 36 passed, 0 failed.",
          "risk_notes" => ["Requires another implementation pass."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:41:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:42:00Z]
      })

    {:ok, rerouted_run} =
      WorkflowRun.reject(run, %{
        actor: %{id: "maintainer-3", email: "maintainer-3@example.com"},
        rejected_at: ~U[2026-02-15 03:43:00Z]
      })

    assert rerouted_run.status == :running
    assert rerouted_run.current_step == "revise_plan"
    assert rerouted_run.completed_at == nil

    assert %{
             "decision" => "rejected",
             "actor" => %{"id" => "maintainer-3", "email" => "maintainer-3@example.com"},
             "timestamp" => "2026-02-15T03:43:00Z",
             "outcome" => "retry_route",
             "retry_step" => "revise_plan"
           } = get_in(rerouted_run.step_results, ["approval_decision"])

    assert_run_event_sequence(reroute_run_id, [
      "run_started",
      "step_started",
      "approval_requested",
      "approval_rejected",
      "step_started"
    ])
  end

  test "reject returns typed failure and leaves run unchanged when rejection policy is invalid" do
    {:ok, project} = create_project("owner/repo-reject-policy-invalid")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-reject-policy-invalid-#{System.unique_integer([:positive])}",
        workflow_name: "implement_task",
        workflow_version: 1,
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
        inputs: %{"task_summary" => "Reject with invalid policy"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 03:50:00Z],
        step_results: %{
          "diff_summary" => "1 file changed (+3/-1).",
          "test_summary" => "mix test: 8 passed, 0 failed.",
          "risk_notes" => ["Policy regression risk."]
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 03:51:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 03:52:00Z]
      })

    transition_count = length(run.status_transitions)

    assert {:error, typed_failure} =
             WorkflowRun.reject(run, %{
               actor: %{id: "maintainer-4", email: "maintainer-4@example.com"},
               rationale: "Policy route is misconfigured."
             })

    assert typed_failure.error_type == "workflow_run_approval_action_failed"
    assert typed_failure.operation == "reject_run"
    assert typed_failure.reason_type == "policy_invalid"
    assert typed_failure.detail =~ "retry route"
    assert typed_failure.remediation =~ "retry rejection"
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(typed_failure.timestamp)

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :awaiting_approval
    assert persisted_run.current_step == "approval_gate"
    assert length(persisted_run.status_transitions) == transition_count
  end

  test "retry creates a new full-run attempt and preserves failure artifacts plus typed reasons in lineage" do
    {:ok, project} = create_project("owner/repo-full-run-retry")
    failed_run_id = "run-full-retry-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Retry full run with lineage"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:00:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "2 tests failed."},
          "diff_summary" => "6 files changed (+80/-14)."
        },
        error: %{
          "error_type" => "workflow_step_failed",
          "reason_type" => "verification_failed",
          "detail" => "Verification failed while running test suite.",
          "remediation" => "Inspect failing tests and rerun with updated patch."
        }
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:01:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:02:00Z]
      })

    {:ok, retried_run} =
      WorkflowRun.retry(run, %{
        actor: %{id: "maintainer-5", email: "maintainer-5@example.com"},
        retry_started_at: ~U[2026-02-15 04:03:00Z]
      })

    assert retried_run.run_id == "#{failed_run_id}-retry-2"
    assert retried_run.status == :pending
    assert retried_run.current_step == "queued"
    assert retried_run.retry_of_run_id == failed_run_id
    assert retried_run.retry_attempt == 2

    assert [%{"run_id" => ^failed_run_id} = lineage_entry] = retried_run.retry_lineage
    assert lineage_entry["status"] == "failed"
    assert lineage_entry["failure_artifacts"]["failure_report"]["step"] == "run_tests"
    assert lineage_entry["typed_failure"]["reason_type"] == "verification_failed"
    assert lineage_entry["typed_failure"]["detail"] =~ "Verification failed"
    assert lineage_entry["retry_actor"]["email"] == "maintainer-5@example.com"

    assert get_in(retried_run.step_results, ["retry_context", "policy"]) == "full_run"
    assert get_in(retried_run.step_results, ["retry_context", "retry_of_run_id"]) == failed_run_id
    assert get_in(retried_run.step_results, ["retry_context", "retry_attempt"]) == 2

    {:ok, persisted_failed_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: failed_run_id
      })

    assert persisted_failed_run.status == :failed
    assert get_in(persisted_failed_run.step_results, ["failure_report", "step"]) == "run_tests"
    assert get_in(persisted_failed_run.error, ["reason_type"]) == "verification_failed"
  end

  test "retry is blocked with typed policy violation when full-run retry is disallowed" do
    {:ok, project} = create_project("owner/repo-full-run-retry-policy-blocked")
    blocked_run_id = "run-full-retry-blocked-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: blocked_run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{
          source: "workflows",
          mode: "manual",
          retry_policy: %{full_run: false, mode: "step_only"}
        },
        inputs: %{"task_summary" => "Retry policy blocked"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:10:00Z],
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
        transitioned_at: ~U[2026-02-15 04:11:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:12:00Z]
      })

    assert {:error, typed_failure} =
             WorkflowRun.retry(run, %{
               actor: %{id: "maintainer-6", email: "maintainer-6@example.com"}
             })

    assert typed_failure.error_type == "workflow_run_retry_action_failed"
    assert typed_failure.operation == "retry_run"
    assert typed_failure.reason_type == "policy_violation"
    assert typed_failure.detail =~ "disallowed"
    assert typed_failure.remediation =~ "retry policy"
    assert Map.get(typed_failure.policy, :full_run, Map.get(typed_failure.policy, "full_run")) == false

    {:ok, no_retry_runs} =
      WorkflowRun.read(
        query: [
          filter: [project_id: project.id, run_id: "#{blocked_run_id}-retry-2"]
        ]
      )

    assert no_retry_runs == []

    {:ok, persisted_blocked_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: blocked_run_id
      })

    assert persisted_blocked_run.status == :failed
  end

  test "step-level retry starts from contract step and preserves failure lineage when policy explicitly allows it" do
    {:ok, project} = create_project("owner/repo-step-retry")
    failed_run_id = "run-step-retry-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: failed_run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{
          source: "workflows",
          mode: "manual",
          retry_policy: %{full_run: false, mode: "step_only", retry_step: "run_tests"}
        },
        inputs: %{"task_summary" => "Retry from failed test step"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:20:00Z],
        step_results: %{
          "failure_report" => %{"step" => "run_tests", "summary" => "2 tests failed."},
          "diff_summary" => "7 files changed (+91/-15)."
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
        transitioned_at: ~U[2026-02-15 04:21:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:22:00Z]
      })

    {:ok, retried_run} =
      WorkflowRun.retry_step(run, %{
        actor: %{id: "maintainer-7", email: "maintainer-7@example.com"},
        retry_started_at: ~U[2026-02-15 04:23:00Z]
      })

    assert retried_run.run_id == "#{failed_run_id}-retry-2"
    assert retried_run.status == :pending
    assert retried_run.current_step == "run_tests"
    assert retried_run.retry_of_run_id == failed_run_id
    assert retried_run.retry_attempt == 2
    assert get_in(retried_run.step_results, ["retry_context", "policy"]) == "step_level"
    assert get_in(retried_run.step_results, ["retry_context", "retry_of_run_id"]) == failed_run_id
    assert get_in(retried_run.step_results, ["retry_context", "retry_attempt"]) == 2
    assert get_in(retried_run.step_results, ["retry_context", "retry_step"]) == "run_tests"

    assert [%{"run_id" => ^failed_run_id} = lineage_entry] = retried_run.retry_lineage
    assert lineage_entry["typed_failure"]["reason_type"] == "verification_failed"
    assert lineage_entry["failure_artifacts"]["failure_report"]["step"] == "run_tests"
    assert lineage_entry["retry_actor"]["email"] == "maintainer-7@example.com"
  end

  test "step-level retry is blocked with guidance when workflow contract does not declare capability" do
    {:ok, project} = create_project("owner/repo-step-retry-policy-blocked")
    blocked_run_id = "run-step-retry-blocked-#{System.unique_integer([:positive])}"

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: blocked_run_id,
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Step retry should be blocked"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-15 04:30:00Z],
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
        transitioned_at: ~U[2026-02-15 04:31:00Z]
      })

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 04:32:00Z]
      })

    assert {:error, typed_failure} =
             WorkflowRun.retry_step(run, %{
               actor: %{id: "maintainer-8", email: "maintainer-8@example.com"}
             })

    assert typed_failure.error_type == "workflow_run_retry_action_failed"
    assert typed_failure.operation == "retry_step"
    assert typed_failure.reason_type == "policy_violation"
    assert typed_failure.detail =~ "does not declare step retry capability"
    assert typed_failure.remediation =~ "step-level retry"
    assert typed_failure.policy == %{}

    {:ok, no_retry_runs} =
      WorkflowRun.read(
        query: [
          filter: [project_id: project.id, run_id: "#{blocked_run_id}-retry-2"]
        ]
      )

    assert no_retry_runs == []
  end

  test "publishes required run topic events with run metadata across step approval and terminal transitions" do
    {:ok, project} = create_project("owner/repo-run-events")

    completed_run_id = "run-events-completed-#{System.unique_integer([:positive])}"
    failed_run_id = "run-events-failed-#{System.unique_integer([:positive])}"
    rejected_run_id = "run-events-rejected-#{System.unique_integer([:positive])}"

    assert :ok = RunPubSub.subscribe_run(completed_run_id)
    assert :ok = RunPubSub.subscribe_run(failed_run_id)
    assert :ok = RunPubSub.subscribe_run(rejected_run_id)

    {:ok, completed_run} = create_run(project.id, completed_run_id, ~U[2026-02-14 22:00:00Z])

    {:ok, completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 22:01:00Z]
      })

    {:ok, completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-14 22:02:00Z]
      })

    {:ok, completed_run} =
      WorkflowRun.approve(completed_run, %{
        actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "apply_feedback",
        approved_at: ~U[2026-02-14 22:03:00Z]
      })

    {:ok, _completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: ~U[2026-02-14 22:04:00Z]
      })

    assert_run_event_sequence(
      completed_run_id,
      [
        "run_started",
        "step_started",
        "approval_requested",
        "approval_granted",
        "step_started",
        "step_completed",
        "run_completed"
      ]
    )

    {:ok, failed_run} = create_run(project.id, failed_run_id, ~U[2026-02-14 23:00:00Z])

    {:ok, failed_run} =
      WorkflowRun.transition_status(failed_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-14 23:01:00Z]
      })

    {:ok, _failed_run} =
      WorkflowRun.transition_status(failed_run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-14 23:02:00Z]
      })

    assert_run_event_sequence(failed_run_id, [
      "run_started",
      "step_started",
      "step_failed",
      "run_failed"
    ])

    {:ok, rejected_run} = create_run(project.id, rejected_run_id, ~U[2026-02-15 00:00:00Z])

    {:ok, rejected_run} =
      WorkflowRun.transition_status(rejected_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 00:01:00Z]
      })

    {:ok, rejected_run} =
      WorkflowRun.transition_status(rejected_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 00:02:00Z]
      })

    {:ok, _rejected_run} =
      WorkflowRun.transition_status(rejected_run, %{
        to_status: :cancelled,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-02-15 00:03:00Z]
      })

    assert_run_event_sequence(
      rejected_run_id,
      ["run_started", "step_started", "approval_requested", "approval_rejected", "run_cancelled"]
    )
  end

  test "publishes cross-run lifecycle events on the dashboard runs topic" do
    {:ok, project} = create_project("owner/repo-dashboard-run-events")
    assert :ok = RunPubSub.subscribe_runs()

    completed_run_id = "dashboard-run-events-completed-#{System.unique_integer([:positive])}"

    {:ok, completed_run} = create_run(project.id, completed_run_id, ~U[2026-02-15 05:00:00Z])

    {:ok, completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 05:01:00Z]
      })

    {:ok, _completed_run} =
      WorkflowRun.transition_status(completed_run, %{
        to_status: :completed,
        current_step: "publish_pr",
        transitioned_at: ~U[2026-02-15 05:02:00Z]
      })

    assert_runs_topic_event(completed_run_id, "run_started")
    assert_runs_topic_event(completed_run_id, "run_completed")

    failed_run_id = "dashboard-run-events-failed-#{System.unique_integer([:positive])}"

    {:ok, failed_run} = create_run(project.id, failed_run_id, ~U[2026-02-15 06:00:00Z])

    {:ok, failed_run} =
      WorkflowRun.transition_status(failed_run, %{
        to_status: :running,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 06:01:00Z]
      })

    {:ok, _failed_run} =
      WorkflowRun.transition_status(failed_run, %{
        to_status: :failed,
        current_step: "run_tests",
        transitioned_at: ~U[2026-02-15 06:02:00Z]
      })

    assert_runs_topic_event(failed_run_id, "run_started")
    assert_runs_topic_event(failed_run_id, "run_failed")
  end

  test "captures typed event-channel diagnostics when run topic publication fails" do
    Application.put_env(:jido_code, :workflow_run_event_broadcaster, FailingRunEventBroadcaster)

    {:ok, project} = create_project("owner/repo-run-event-failures")
    run_id = "run-events-failure-#{System.unique_integer([:positive])}"

    {:ok, run} = create_run(project.id, run_id, ~U[2026-02-15 01:00:00Z])

    assert diagnostics = get_in(run.error, ["event_channel_diagnostics"])
    assert length(diagnostics) == 1
    assert_typed_publication_diagnostic(List.first(diagnostics), run_id, "run_started")

    {:ok, run} =
      WorkflowRun.transition_status(run, %{
        to_status: :running,
        current_step: "plan_changes",
        transitioned_at: ~U[2026-02-15 01:01:00Z]
      })

    assert run.status == :running
    assert transition_diagnostics = get_in(run.error, ["event_channel_diagnostics"])
    assert length(transition_diagnostics) == 2

    assert_typed_publication_diagnostic(
      Enum.at(transition_diagnostics, 1),
      run_id,
      "step_started"
    )
  end

  test "rejects invalid transitions and leaves persisted run state unchanged" do
    {:ok, project} = create_project("owner/repo-invalid-transition")

    {:ok, run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: "run-invalid-123",
        workflow_name: "implement_task",
        workflow_version: 1,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Attempt invalid transition"},
        input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
        initiating_actor: %{id: "owner-1", email: "owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-02-14 21:00:00Z]
      })

    assert {:error, error} =
             WorkflowRun.transition_status(run, %{
               to_status: :completed,
               current_step: "publish_pr",
               transitioned_at: ~U[2026-02-14 21:01:00Z]
             })

    assert Exception.message(error) =~ "invalid lifecycle transition from pending to completed"

    {:ok, persisted_run} =
      WorkflowRun.get_by_project_and_run_id(%{
        project_id: project.id,
        run_id: run.run_id
      })

    assert persisted_run.status == :pending
    assert persisted_run.current_step == "queued"
    assert persisted_run.completed_at == nil

    assert [
             %{
               "from_status" => nil,
               "to_status" => "pending",
               "current_step" => "queued",
               "transitioned_at" => "2026-02-14T21:00:00Z"
             }
           ] = persisted_run.status_transitions
  end

  defp create_project(github_full_name) do
    Project.create(%{
      name: github_full_name,
      github_full_name: github_full_name,
      default_branch: "main",
      settings: %{}
    })
  end

  defp create_run(project_id, run_id, started_at) do
    WorkflowRun.create(%{
      project_id: project_id,
      run_id: run_id,
      workflow_name: "implement_task",
      workflow_version: 1,
      trigger: %{source: "workflows", mode: "manual"},
      inputs: %{"task_summary" => "Publish run topic events"},
      input_metadata: %{"task_summary" => %{required: true, source: "manual_workflows_ui"}},
      initiating_actor: %{id: "owner-1", email: "owner@example.com"},
      current_step: "queued",
      started_at: started_at,
      step_results: %{
        "diff_summary" => "1 file changed (+2/-0).",
        "test_summary" => "mix test: 1 passed, 0 failed.",
        "risk_notes" => ["No privileged operations detected."]
      }
    })
  end

  defp assert_run_event_sequence(run_id, expected_events) do
    Enum.each(expected_events, fn expected_event ->
      assert_receive {:run_event, payload}

      assert payload["event"] == expected_event
      assert payload["run_id"] == run_id
      assert payload["workflow_name"] == "implement_task"
      assert payload["workflow_version"] == 1
      assert is_binary(payload["correlation_id"])
      assert payload["correlation_id"] != ""
      assert {:ok, _timestamp, 0} = DateTime.from_iso8601(payload["timestamp"])
    end)
  end

  defp assert_runs_topic_event(run_id, expected_event, attempts \\ 16)

  defp assert_runs_topic_event(_run_id, expected_event, 0) do
    flunk("did not receive expected runs topic event #{expected_event}")
  end

  defp assert_runs_topic_event(run_id, expected_event, attempts) do
    assert_receive {:run_event, payload}

    if payload["run_id"] == run_id and payload["event"] == expected_event do
      assert payload["workflow_name"] == "implement_task"
      assert payload["workflow_version"] == 1
      assert is_binary(payload["correlation_id"])
      assert payload["correlation_id"] != ""
      assert {:ok, _timestamp, 0} = DateTime.from_iso8601(payload["timestamp"])
    else
      assert_runs_topic_event(run_id, expected_event, attempts - 1)
    end
  end

  defp assert_typed_publication_diagnostic(diagnostic, run_id, event_name) do
    assert diagnostic["error_type"] == "workflow_run_event_publication_failed"
    assert diagnostic["channel"] == "run_topic"
    assert diagnostic["operation"] == "broadcast_run_event"
    assert diagnostic["topic"] == RunPubSub.run_topic(run_id)
    assert diagnostic["event"] == event_name
    assert diagnostic["reason_type"] == "forced_publish_failure"
    assert diagnostic["message"] == "Run topic event publication failed."
    assert {:ok, _timestamp, 0} = DateTime.from_iso8601(diagnostic["timestamp"])
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
