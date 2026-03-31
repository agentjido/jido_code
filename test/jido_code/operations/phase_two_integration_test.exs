defmodule JidoCode.Operations.PhaseTwoIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.demand_ingress.external_object_tracks_repo_external_entities
  # covers: architecture.demand_ingress.observation_captures_repo_and_system_facts
  # covers: architecture.demand_ingress.intake_captures_operator_and_trusted_requests
  # covers: architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  # covers: architecture.event_assessment_synthesis.event_records_derived_from_ingress
  # covers: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
  # covers: architecture.event_assessment_synthesis.assessment_records_interpret_events
  # covers: architecture.event_assessment_synthesis.assessment_priority_and_next_action
  # covers: architecture.work_synthesis.work_item_is_canonical_operational_record
  # covers: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  # covers: architecture.work_synthesis.work_item_creation_can_stop_before_execution
  # covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  # covers: architecture.work_synthesis.work_item_auditability_preserved
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.GitHub.{Repo, WebhookDelivery, WebhookPipeline}
  alias JidoCode.Operations.{Assessment, Event, ExternalObject, Intake, Observation, WorkItem}
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Workbench.FixWorkflowKickoff

  @managed_env_keys [
    :setup_project_importer,
    :setup_project_clone_provisioner,
    :setup_project_baseline_syncer,
    :workbench_fix_workflow_launcher
  ]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :setup_project_clone_provisioner)
    Application.delete_env(:jido_code, :setup_project_baseline_syncer)

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      {:ok, %{run_id: "phase-two-fix-run-#{System.unique_integer([:positive])}"}}
    end)

    :ok
  end

  test "verified webhook pipeline records the full demand-to-work chain for tracked GitHub issues" do
    {:ok, project} =
      Project.create(%{
        name: "repo-pipeline",
        github_full_name: "owner/repo-pipeline",
        default_branch: "main",
        settings: %{
          "support_agent_config" => %{
            "github_issue_bot" => %{"enabled" => false}
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, _github_repo} =
      Repo.create(%{
        owner: "owner",
        name: "repo-pipeline",
        settings: %{}
      })

    delivery = %{
      delivery_id: "phase-two-webhook-1",
      event: "issues.opened",
      payload: %{
        "action" => "opened",
        "repository" => %{
          "id" => 112,
          "name" => "repo-pipeline",
          "full_name" => "owner/repo-pipeline",
          "html_url" => "https://github.com/owner/repo-pipeline",
          "visibility" => "public"
        },
        "issue" => %{
          "id" => 99123,
          "number" => 34,
          "title" => "Investigate pipeline regression",
          "html_url" => "https://github.com/owner/repo-pipeline/issues/34",
          "state" => "open"
        }
      },
      raw_payload: "{}"
    }

    assert :ok = WebhookPipeline.route_verified_delivery(delivery)

    assert {:ok, %WebhookDelivery{} = webhook_delivery} =
             WebhookDelivery.get_by_github_delivery_id("phase-two-webhook-1", authorize?: false)

    assert webhook_delivery.event_type == "issues.opened"

    assert {:ok, external_object} =
             ExternalObject.get_by_canonical_key(
               "github:github_issue:owner/repo-pipeline:99123",
               actor: Actor.operator_actor()
             )

    assert {:ok, [observation]} =
             Observation.read(
               query: [filter: [managed_repo_id: managed_repo.id, external_object_id: external_object.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [event]} =
             Event.read(
               query: [filter: [managed_repo_id: managed_repo.id, observation_id: observation.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [assessment]} =
             Assessment.read(
               query: [filter: [managed_repo_id: managed_repo.id, event_id: event.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [work_item]} =
             WorkItem.read(
               query: [filter: [managed_repo_id: managed_repo.id, assessment_id: assessment.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert observation.captured_by["delivery_id"] == "phase-two-webhook-1"
    assert event.category == "external.github.issue.opened"
    assert event.correlation_key == "owner/repo-pipeline#34:opened"
    assert assessment.recommended_action == "triage_issue"
    assert work_item.recommended_action == "triage_issue"
    assert work_item.summary == "Triage owner/repo-pipeline#34."
    assert work_item.initiating_actor["actor_class"] == "external_ingress"
  end

  test "project import records durable work without requiring a workflow run" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-import-phase-two", "default_branch" => "develop"}
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-import-phase-two", onboarding_state)

    refute ProjectImport.blocked?(report)

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(report.project_record.id, actor: Actor.operator_actor())

    assert {:ok, [intake]} =
             Intake.read(
               query: [
                 filter: [managed_repo_id: managed_repo.id, channel: "setup", intent: "project_import"],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, [event]} =
             Event.read(
               query: [filter: [managed_repo_id: managed_repo.id, intake_id: intake.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [assessment]} =
             Assessment.read(
               query: [filter: [managed_repo_id: managed_repo.id, event_id: event.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [work_item]} =
             WorkItem.read(
               query: [filter: [managed_repo_id: managed_repo.id, assessment_id: assessment.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert work_item.recommended_action == "prepare_managed_repo"
    assert work_item.status == :open
    assert work_item.initiating_actor["actor_class"] == "operator"

    assert {:ok, []} =
             WorkflowRun.read(
               query: [filter: [project_id: report.project_record.id]],
               actor: Actor.operator_actor()
             )
  end

  test "repeated workbench kickoff suppresses duplicate work while preserving auditability" do
    {:ok, project} =
      Project.create(%{
        name: "repo-fix-phase-two",
        github_full_name: "owner/repo-fix-phase-two",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, _first_run} =
             FixWorkflowKickoff.kickoff(
               project,
               :issue,
               %{id: "operator-55", email: "operator55@example.com"}
             )

    assert {:ok, _second_run} =
             FixWorkflowKickoff.kickoff(
               project,
               :issue,
               %{id: "operator-55", email: "operator55@example.com"}
             )

    assert {:ok, [work_item]} =
             WorkItem.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   recommended_action: "launch_fix_workflow",
                   status: :open
                 ],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, work_items} =
             WorkItem.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   recommended_action: "launch_fix_workflow",
                   status: :open
                 ]
               ],
               actor: Actor.operator_actor()
             )

    assert length(work_items) == 1

    assert Enum.map(work_item.audit_log, &Map.fetch!(&1, "action")) == [
             "created",
             "suppressed_duplicate"
           ]

    assert work_item.initiating_actor["id"] == "operator-55"
    assert work_item.work_metadata["source_record_type"] == "intake"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
