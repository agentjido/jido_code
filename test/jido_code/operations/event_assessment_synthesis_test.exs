defmodule JidoCode.Operations.EventAssessmentSynthesisTest do
  # covers: architecture.event_assessment_synthesis.event_records_derived_from_ingress
  # covers: architecture.event_assessment_synthesis.event_categories_and_repo_correlation_preserved
  # covers: architecture.event_assessment_synthesis.assessment_records_interpret_events
  # covers: architecture.event_assessment_synthesis.assessment_priority_and_next_action
  # covers: architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  # covers: architecture.event_assessment_synthesis.correlation_prefers_persisted_requested_by_actor_identity
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{Assessment, Event, Ingress}
  alias JidoCode.Projects.Project

  test "github webhook ingress synthesizes a durable event and assessment for issue demand" do
    {:ok, project} =
      Project.create(%{
        name: "repo-events",
        github_full_name: "owner/repo-events",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    delivery = %{
      delivery_id: "event-delivery-1",
      event: "issues",
      payload: %{
        "action" => "opened",
        "repository" => %{
          "id" => 77,
          "name" => "repo-events",
          "full_name" => "owner/repo-events",
          "html_url" => "https://github.com/owner/repo-events",
          "visibility" => "public"
        },
        "issue" => %{
          "id" => 4401,
          "number" => 12,
          "title" => "Broken integration path",
          "html_url" => "https://github.com/owner/repo-events/issues/12",
          "state" => "open"
        }
      }
    }

    assert {:ok,
            %{
              external_object: external_object,
              observation: observation,
              event: event,
              assessment: assessment
            }} = Ingress.record_github_webhook_delivery(delivery)

    assert event.managed_repo_id == managed_repo.id
    assert event.external_object_id == external_object.id
    assert event.observation_id == observation.id
    assert event.intake_id == nil
    assert event.category == "external.github.issue.opened"
    assert event.correlation_key == "owner/repo-events#12:opened"
    assert event.summary == observation.summary
    assert event.source_metadata["source_record_type"] == "observation"
    assert event.source_metadata["source_record_id"] == observation.id

    assert assessment.managed_repo_id == managed_repo.id
    assert assessment.event_id == event.id
    assert assessment.external_object_id == external_object.id
    assert assessment.category == "github_issue_demand"
    assert assessment.priority == :high
    assert assessment.urgency == :high
    assert assessment.recommended_action == "triage_issue"
    assert assessment.inputs["event_category"] == event.category
    assert assessment.inputs["observation_id"] == observation.id
    assert assessment.assessment_metadata["assessment_origin"] == "observation"
    assert assessment.assessment_metadata["external_reference"] == "owner/repo-events#12"

    assert {:ok, [persisted_event]} =
             Event.read(query: [filter: [id: event.id]], actor: Actor.operator_actor())

    assert {:ok, [persisted_assessment]} =
             Assessment.read(query: [filter: [id: assessment.id]], actor: Actor.operator_actor())

    assert persisted_event.id == event.id
    assert persisted_assessment.id == assessment.id
  end

  test "operator intake ingress synthesizes a typed event and assessment with next-action guidance" do
    {:ok, project} =
      Project.create(%{
        name: "repo-workbench",
        github_full_name: "owner/repo-workbench",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{intake: intake, event: event, assessment: assessment}} =
             Ingress.record_operator_intake(%{
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               project_id: project.id,
               actor: %{id: "operator-7", email: "operator7@example.com"},
               payload: %{
                 "workflow_name" => "fix_failing_tests",
                 "context_item" => %{"type" => "issue"}
               },
               source_metadata: %{
                 "trigger" => %{"source" => "workbench", "mode" => "manual"}
               }
             })

    assert event.managed_repo_id == managed_repo.id
    assert event.intake_id == intake.id
    assert event.observation_id == nil
    assert event.category == "operator.workbench.fix_workflow_kickoff.requested"
    assert event.summary == "Operator requested fix workflow kickoff via workbench."

    assert event.correlation_key =~
             "#{managed_repo.id}:operator.workbench.fix_workflow_kickoff.requested:"

    assert event.source_metadata["source_record_type"] == "intake"
    assert event.source_metadata["source_record_id"] == intake.id
    assert event.source_metadata["trigger"]["source"] == "workbench"

    assert assessment.managed_repo_id == managed_repo.id
    assert assessment.event_id == event.id
    assert assessment.category == "operator_work_request"
    assert assessment.priority == :high
    assert assessment.urgency == :high
    assert assessment.recommended_action == "launch_fix_workflow"
    assert assessment.inputs["intake_id"] == intake.id
    assert assessment.inputs["channel"] == "workbench"
    assert assessment.inputs["intent"] == "fix_workflow_kickoff"
    assert assessment.assessment_metadata["assessment_origin"] == "intake"
    assert assessment.assessment_metadata["requested_by_actor_id"] == "operator-7"
  end
end
