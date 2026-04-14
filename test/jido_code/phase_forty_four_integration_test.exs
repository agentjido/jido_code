defmodule JidoCode.PhaseFortyFourIntegrationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "repo detail keeps intake bounded once productive work hands off to canonical work-item conversation identity" do
    {project, managed_repo} = managed_repo_fixture!("repo-detail-conversation")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    initial_projection =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert initial_projection.snapshot == nil
    assert initial_projection.conversation == nil
    assert initial_projection.action_label == "Open repo conversation"

    assert {:ok, %{conversation: conversation, snapshot: snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase44-open"})
             )

    assert snapshot.conversation_id == conversation.id
    assert snapshot.managed_repo_id == managed_repo.id
    assert snapshot.work_item_id == nil

    assert {:ok, latest_conversation} =
             AgentWorkspace.latest_repo_conversation(managed_repo.id, actor: Actor.operator_actor())

    assert latest_conversation.id == conversation.id

    assert {:ok, updated_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation boundary."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase44-turn"})
             )

    assert updated_snapshot.conversation_id == conversation.id
    assert is_binary(updated_snapshot.active_turn_id)
    assert is_binary(updated_snapshot.work_item_id)
    assert updated_snapshot.scope == :work_item_scoped

    projection_after_turn =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert projection_after_turn.conversation.id == conversation.id
    assert projection_after_turn.snapshot.conversation_id == conversation.id
    assert projection_after_turn.conversation.intake_handoff["handoff_kind"] == "repo_intake_to_work_item"
    assert projection_after_turn.action_label == "Open repo conversation"

    assert Enum.any?(
             projection_after_turn.recent_events,
             &(&1.name == "conversation.message_added")
           )

    assert {:ok, %{conversation: reopened_conversation, snapshot: reopened_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase44-reopen"})
             )

    refute reopened_conversation.id == conversation.id
    assert reopened_snapshot.conversation_id == reopened_conversation.id
    assert reopened_snapshot.work_item_id == nil
    assert reopened_snapshot.scope == :repo_scoped

    assert {:ok, %{conversation: resumed_work_item_conversation, resumed?: true}} =
             AgentWorkspace.open_work_item_conversation(
               updated_snapshot.work_item_id,
               %{},
               actor: Actor.operator_actor(%{"id" => "operator-phase44-work-item"})
             )

    assert resumed_work_item_conversation.id == conversation.id

    assert :ok = AgentWorkspace.stop_conversation(conversation.id)
    assert :ok = AgentWorkspace.stop_conversation(reopened_conversation.id)
    assert :ok = AgentWorkspace.shutdown_kernel(managed_repo.id)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-four-#{suffix}",
        github_full_name: "owner/phase-forty-four-#{suffix}",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path!(suffix),
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-forty-four-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
