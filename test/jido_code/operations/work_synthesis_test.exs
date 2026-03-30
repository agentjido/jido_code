defmodule JidoCode.Operations.WorkSynthesisTest do
  # covers: architecture.work_synthesis.work_item_is_canonical_operational_record
  # covers: architecture.work_synthesis.work_item_metadata_and_origin_links_preserved
  # covers: architecture.work_synthesis.work_item_creation_can_stop_before_execution
  # covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  # covers: architecture.work_synthesis.work_item_auditability_preserved
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{Assessment, Event, Ingress, Intake, WorkItem, WorkSynthesis}
  alias JidoCode.Projects.Project

  test "verified issue demand creates an open work item linked to initiating records" do
    {:ok, project} =
      Project.create(%{
        name: "repo-work",
        github_full_name: "owner/repo-work",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    delivery = %{
      delivery_id: "work-delivery-1",
      event: "issues",
      payload: %{
        "action" => "opened",
        "repository" => %{
          "id" => 88,
          "name" => "repo-work",
          "full_name" => "owner/repo-work",
          "html_url" => "https://github.com/owner/repo-work",
          "visibility" => "public"
        },
        "issue" => %{
          "id" => 9912,
          "number" => 21,
          "title" => "Repair repo sync",
          "html_url" => "https://github.com/owner/repo-work/issues/21",
          "state" => "open"
        }
      }
    }

    assert {:ok,
            %{
              external_object: external_object,
              observation: observation,
              event: event,
              assessment: assessment,
              work_item: work_item,
              work_action: :created
            }} = Ingress.record_github_webhook_delivery(delivery)

    assert work_item.id
    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.assessment_id == assessment.id
    assert work_item.event_id == event.id
    assert work_item.external_object_id == external_object.id
    assert work_item.observation_id == observation.id
    assert work_item.intake_id == nil
    assert work_item.category == "github_issue_demand"
    assert work_item.status == :open
    assert work_item.priority == :high
    assert work_item.recommended_action == "triage_issue"
    assert work_item.summary == "Triage owner/repo-work#21."
    assert work_item.initiating_actor["actor_class"] == "external_ingress"
    assert work_item.work_metadata["source_record_type"] == "observation"
    assert work_item.work_metadata["event_category"] == event.category
    assert work_item.work_metadata["assessment_category"] == assessment.category
    assert work_item.audit_log |> List.first() |> Map.fetch!("action") == "created"

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(query: [filter: [id: work_item.id]], actor: Actor.operator_actor())

    assert persisted_work_item.id == work_item.id
  end

  test "operator intake can stop at durable work creation without immediate execution" do
    {:ok, project} =
      Project.create(%{
        name: "repo-intake-work",
        github_full_name: "owner/repo-intake-work",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok,
            %{
              intake: intake,
              event: event,
              assessment: assessment,
              work_item: work_item,
              work_action: :created
            }} =
             Ingress.record_operator_intake(%{
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               project_id: project.id,
               actor: %{id: "operator-13", email: "operator13@example.com"},
               payload: %{
                 "workflow_name" => "fix_failing_tests",
                 "context_item" => %{"type" => "issue"}
               },
               source_metadata: %{
                 "trigger" => %{"source" => "workbench", "mode" => "manual"}
               }
             })

    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.assessment_id == assessment.id
    assert work_item.event_id == event.id
    assert work_item.intake_id == intake.id
    assert work_item.observation_id == nil
    assert work_item.category == "operator_work_request"
    assert work_item.status == :open
    assert work_item.priority == :high
    assert work_item.recommended_action == "launch_fix_workflow"
    assert work_item.initiating_actor["id"] == "operator-13"
    assert work_item.initiating_actor["actor_class"] == "operator"
    assert work_item.work_metadata["source_record_type"] == "intake"
    assert work_item.work_metadata["intake_id"] == intake.id
  end

  test "equivalent work candidates reprioritize and suppress duplicates with audit history" do
    {:ok, project} =
      Project.create(%{
        name: "repo-dedup",
        github_full_name: "owner/repo-dedup",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, intake} =
      Intake.create(
        %{
          managed_repo_id: managed_repo.id,
          channel: "workbench",
          intent: "fix_workflow_kickoff",
          payload: %{
            "workflow_name" => "fix_failing_tests",
            "context_item" => %{"type" => "issue"}
          },
          source_metadata: %{},
          requested_by: Actor.operator_actor(%{"id" => "operator-17", "email" => "operator17@example.com"})
        },
        actor: Actor.operator_actor()
      )

    {:ok, event_one} = create_fix_event(managed_repo.id, intake.id, "repo-dedup-fix")
    {:ok, assessment_one} = create_fix_assessment(managed_repo.id, event_one.id, :medium)

    assert {:ok, %{work_item: work_item_one, action: :created}} =
             WorkSynthesis.from_assessment(assessment_one, event: event_one, intake: intake)

    {:ok, event_two} = create_fix_event(managed_repo.id, intake.id, "repo-dedup-fix")
    {:ok, assessment_two} = create_fix_assessment(managed_repo.id, event_two.id, :critical)

    assert {:ok, %{work_item: work_item_two, action: :reprioritized}} =
             WorkSynthesis.from_assessment(assessment_two, event: event_two, intake: intake)

    {:ok, event_three} = create_fix_event(managed_repo.id, intake.id, "repo-dedup-fix")
    {:ok, assessment_three} = create_fix_assessment(managed_repo.id, event_three.id, :critical)

    assert {:ok, %{work_item: work_item_three, action: :suppressed_duplicate}} =
             WorkSynthesis.from_assessment(assessment_three, event: event_three, intake: intake)

    assert work_item_one.id == work_item_two.id
    assert work_item_two.id == work_item_three.id
    assert work_item_three.priority == :critical

    assert Enum.map(work_item_three.audit_log, &Map.fetch!(&1, "action")) == [
             "created",
             "reprioritized",
             "suppressed_duplicate"
           ]
  end

  defp create_fix_event(managed_repo_id, intake_id, correlation_key) do
    Event.create(
      %{
        managed_repo_id: managed_repo_id,
        intake_id: intake_id,
        category: "operator.workbench.fix_workflow_kickoff.requested",
        summary: "Operator requested fix workflow kickoff via workbench.",
        correlation_key: correlation_key,
        payload: %{},
        source_metadata: %{"source_record_type" => "intake"},
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      actor: Actor.factory_system_actor()
    )
  end

  defp create_fix_assessment(managed_repo_id, event_id, priority) do
    Assessment.create(
      %{
        managed_repo_id: managed_repo_id,
        event_id: event_id,
        category: "operator_work_request",
        summary: "Assess operator work request for downstream synthesis.",
        priority: priority,
        urgency: :high,
        recommended_action: "launch_fix_workflow",
        rationale: "Regression test assessment.",
        inputs: %{},
        assessment_metadata: %{},
        assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      },
      actor: Actor.factory_system_actor()
    )
  end
end
