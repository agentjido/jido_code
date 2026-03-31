defmodule JidoCode.Conversations.IngressTest do
  # covers: architecture.demand_ingress.conversation_turns_become_durable_intake
  # covers: architecture.demand_ingress.conversation_turns_preserve_session_and_correlation_context
  # covers: architecture.demand_ingress.conversation_turns_distinguish_new_work_from_steering
  # covers: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  # covers: architecture.work_synthesis.conversation_turns_can_steer_existing_work
  use JidoCode.DataCase, async: false

  alias JidoCode.Conversations.Ingress
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Projects.Project

  test "coding conversation turns become durable intake, event, assessment, and work records" do
    {:ok, project} = create_project("repo-conversation-ingress")

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok,
            %{
              turn_mode: :new_demand,
              intake: intake,
              event: event,
              assessment: assessment,
              work_item: work_item,
              work_action: :created
            }} =
             Ingress.record_turn(%{
               actor_id: "operator-conversation",
               actor_email: "conversation@example.com",
               project_id: project.id,
               conversation_id: "conversation-101",
               content: "Investigate the failing repo sync path and propose a safe fix.",
               request_id: "req-conversation-101",
               correlation_id: "corr-conversation-101",
               workspace_id: "/tmp/repo-conversation-ingress"
             })

    assert intake.managed_repo_id == managed_repo.id
    assert intake.channel == "conversation"
    assert intake.intent == "coding_turn_request"
    assert intake.requested_by["id"] == "operator-conversation"
    assert intake.payload["message_content"] =~ "Investigate the failing repo sync path"
    assert intake.payload["conversation_id"] == "conversation-101"
    assert intake.source_metadata["conversation_id"] == "conversation-101"
    assert intake.source_metadata["session_id"] == "conversation-101"
    assert intake.source_metadata["request_id"] == "req-conversation-101"
    assert intake.source_metadata["correlation_id"] == "corr-conversation-101"
    assert intake.source_metadata["turn_mode"] == "new_demand"
    assert event.category == "operator.conversation.coding_turn_request.requested"

    assert event.correlation_key ==
             "#{managed_repo.id}:operator.conversation.coding_turn_request.requested:conversation-101"

    assert assessment.category == "conversation_work_request"
    assert assessment.recommended_action == "review_operator_request"
    assert work_item.intake_id == intake.id
    assert work_item.category == "conversation_work_request"
    assert work_item.work_metadata["conversation_context"]["conversation_id"] == "conversation-101"
    assert work_item.work_metadata["conversation_context"]["request_id"] == "req-conversation-101"
  end

  test "conversation turns can explicitly steer an existing work item instead of creating a new one" do
    {:ok, project} = create_project("repo-conversation-steering")

    assert {:ok, %{work_item: original_work_item}} =
             Ingress.record_turn(%{
               actor_id: "operator-create",
               actor_email: "create@example.com",
               project_id: project.id,
               conversation_id: "conversation-create-1",
               content: "Open work to repair the approval gate.",
               request_id: "req-create-1",
               correlation_id: "corr-create-1"
             })

    assert {:ok,
            %{
              turn_mode: :steer_existing_work,
              intake: intake,
              event: event,
              assessment: assessment,
              work_item: steered_work_item,
              work_action: :steered
            }} =
             Ingress.record_turn(%{
               actor_id: "operator-steer",
               actor_email: "steer@example.com",
               project_id: project.id,
               conversation_id: "conversation-steer-1",
               content: "Continue that work item and focus on review diagnostics first.",
               work_item_id: original_work_item.id,
               request_id: "req-steer-1",
               correlation_id: "corr-steer-1"
             })

    assert steered_work_item.id == original_work_item.id
    assert intake.intent == "work_item_steering"
    assert intake.payload["work_item_id"] == original_work_item.id
    assert event.category == "operator.conversation.work_item_steering.requested"
    assert assessment.category == "conversation_work_steering"
    assert assessment.recommended_action == "steer_existing_work_item"
    assert steered_work_item.work_metadata["conversation_context"]["conversation_id"] == "conversation-steer-1"
    assert steered_work_item.summary =~ original_work_item.id
    assert Enum.any?(steered_work_item.audit_log, &(&1["action"] == "steered"))

    assert {:ok, [open_work_item]} =
             WorkItem.read(
               query: [filter: [managed_repo_id: steered_work_item.managed_repo_id, status: :open]],
               actor: Actor.operator_actor()
             )

    assert open_work_item.id == original_work_item.id
  end

  defp create_project(name) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{}
    })
  end
end
