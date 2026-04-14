defmodule JidoCode.PhaseFortyNineIntegrationTest do
  # covers: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
  # covers: architecture.conversation_orchestration.repo_scoped_conversations_are_pre_work_intake
  # covers: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
  # covers: architecture.work_synthesis.active_conversation_identity_rejoins_work_item
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  # covers: architecture.factory_control_plane.operator_surfaces_distinguish_repo_intake_from_work_item_conversations
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "repo intake hands off to work-item-scoped productive identity and distinct work items keep separate active conversations" do
    {project, managed_repo} = managed_repo_fixture!("work-item-identity")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: intake_conversation, snapshot: intake_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase49-intake"})
             )

    track_conversation!(tracked_conversations, intake_conversation.id)

    assert intake_snapshot.scope == :repo_scoped
    assert intake_snapshot.work_item_id == nil

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               intake_conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase49-turn"})
             )

    attached_snapshot =
      eventually_snapshot!(intake_conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.scope == :work_item_scoped and
          snapshot.active_turn == nil and snapshot.active_child_work == nil
      end)

    first_work_item_id = attached_snapshot.work_item_id
    assert attached_snapshot.shared_context["intake_handoff"]["handoff_kind"] == "repo_intake_to_work_item"
    assert attached_snapshot.shared_context["intake_handoff"]["work_item_id"] == first_work_item_id

    repo_projection =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert repo_projection.conversation.id == intake_conversation.id
    assert repo_projection.conversation.intake_handoff["work_item_id"] == first_work_item_id
    assert repo_projection.action_label == "Open repo conversation"

    assert {:ok, %{conversation: fresh_intake_conversation, snapshot: fresh_intake_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase49-fresh-intake"})
             )

    track_conversation!(tracked_conversations, fresh_intake_conversation.id)

    refute fresh_intake_conversation.id == intake_conversation.id
    assert fresh_intake_snapshot.scope == :repo_scoped
    assert fresh_intake_snapshot.work_item_id == nil

    assert {:ok, %{conversation: resumed_first_conversation, resumed?: true}} =
             AgentWorkspace.open_work_item_conversation(
               first_work_item_id,
               %{},
               actor: Actor.operator_actor(%{"id" => "operator-phase49-resume-first"})
             )

    assert resumed_first_conversation.id == intake_conversation.id

    second_work_item = work_item_fixture!(managed_repo, "phase49-second")

    assert {:ok, %{conversation: second_conversation, snapshot: second_snapshot, resumed?: false}} =
             AgentWorkspace.open_work_item_conversation(
               second_work_item.id,
               %{
                 source: "phase_forty_nine_integration_test",
                 objective: "Continue the second governed work item through the canonical work-item boundary."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase49-second-open"})
             )

    track_conversation!(tracked_conversations, second_conversation.id)

    assert second_snapshot.scope == :work_item_scoped
    assert second_snapshot.work_item_id == second_work_item.id

    assert {:ok, active_conversations} =
             AgentWorkspace.active_work_item_conversations(managed_repo.id,
               actor: Actor.operator_actor()
             )

    active_by_work_item =
      Map.new(active_conversations, fn conversation ->
        {conversation.work_item_id, conversation.id}
      end)

    assert active_by_work_item[first_work_item_id] == intake_conversation.id
    assert active_by_work_item[second_work_item.id] == second_conversation.id
    assert map_size(active_by_work_item) == 2

    assert {:ok, %{conversation: resumed_second_conversation, resumed?: true}} =
             AgentWorkspace.open_work_item_conversation(
               second_work_item.id,
               %{},
               actor: Actor.operator_actor(%{"id" => "operator-phase49-second-resume"})
             )

    assert resumed_second_conversation.id == second_conversation.id
  end

  defp tracked_conversations!(managed_repo_id) do
    {:ok, tracker} = Agent.start(fn -> [] end)

    on_exit(fn ->
      tracker
      |> Agent.get(&Enum.uniq(&1))
      |> Enum.each(fn conversation_id ->
        case AgentWorkspace.stop_conversation(conversation_id) do
          :ok -> :ok
          {:error, _reason} -> :ok
        end
      end)

      case AgentWorkspace.shutdown_kernel(managed_repo_id) do
        :ok -> :ok
        {:error, _reason} -> :ok
      end

      Agent.stop(tracker)
    end)

    tracker
  end

  defp track_conversation!(tracker, conversation_id) do
    Agent.update(tracker, &[conversation_id | &1])
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "phase-forty-nine-#{suffix}",
        github_full_name: "owner/phase-forty-nine-#{suffix}",
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

  defp work_item_fixture!(managed_repo, actor_id) do
    {:ok, %{work_item: work_item}} =
      Ingress.record_operator_intake(%{
        managed_repo_id: managed_repo.id,
        channel: "workbench",
        intent: "fix_workflow_kickoff",
        actor: %{id: actor_id, email: "#{actor_id}@example.com"},
        payload: %{
          "workflow_name" => "fix_failing_tests_#{actor_id}",
          "context_item" => %{"type" => "issue", "id" => actor_id}
        },
        source_metadata: %{
          "trigger" => %{"source" => "workbench", "mode" => "manual"}
        }
      })

    work_item
  end

  defp workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-forty-nine-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp eventually_snapshot!(conversation_id, predicate, attempts \\ 40)

  defp eventually_snapshot!(conversation_id, predicate, attempts)
       when is_binary(conversation_id) and is_function(predicate, 1) and attempts > 1 do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)

    if predicate.(snapshot) do
      snapshot
    else
      Process.sleep(100)
      eventually_snapshot!(conversation_id, predicate, attempts - 1)
    end
  end

  defp eventually_snapshot!(conversation_id, predicate, 1) do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)
    assert predicate.(snapshot)
    snapshot
  end
end
