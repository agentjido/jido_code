defmodule JidoCode.PhaseFiftyIntegrationTest do
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  # covers: architecture.factory_control_plane.operator_surfaces_distinguish_repo_intake_from_work_item_conversations
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.DashboardSummaryFeed, as: ConversationDashboardSummaryFeed
  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{Inventory, ProjectConversation, ProjectDetail}

  test "repo detail, workbench, and dashboard distinguish repo intake from active work-item conversations" do
    {project, managed_repo} = managed_repo_fixture!("multi-surface-adoption")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: first_conversation, snapshot: first_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase50-intake"})
             )

    track_conversation!(tracked_conversations, first_conversation.id)
    assert first_snapshot.scope == :repo_scoped

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               first_conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase50-turn"})
             )

    attached_snapshot =
      eventually_snapshot!(first_conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.scope == :work_item_scoped and
          snapshot.active_turn == nil and snapshot.active_child_work == nil
      end)

    first_work_item_id = attached_snapshot.work_item_id

    assert {:ok, %{conversation: repo_intake, snapshot: repo_intake_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase50-fresh-intake"})
             )

    track_conversation!(tracked_conversations, repo_intake.id)

    assert repo_intake_snapshot.scope == :repo_scoped
    assert repo_intake_snapshot.work_item_id == nil

    second_work_item = work_item_fixture!(managed_repo, "phase50-second")

    assert {:ok, %{conversation: second_conversation, snapshot: second_snapshot, resumed?: false}} =
             AgentWorkspace.open_work_item_conversation(
               second_work_item.id,
               %{
                 source: "phase_fifty_integration_test",
                 objective: "Continue the second governed work item through repo-detail supervision."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase50-second-open"})
             )

    track_conversation!(tracked_conversations, second_conversation.id)

    assert second_snapshot.scope == :work_item_scoped
    assert second_snapshot.work_item_id == second_work_item.id

    repo_detail_projection =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert repo_detail_projection.repo_intake.conversation.id == repo_intake.id
    assert repo_detail_projection.conversation.id == repo_intake.id
    assert repo_detail_projection.action_label == "Continue repo intake"

    active_work_item_ids =
      repo_detail_projection.active_work_items
      |> Enum.map(& &1.work_item.id)
      |> Enum.sort()

    assert active_work_item_ids == Enum.sort([first_work_item_id, second_work_item.id])

    selected_work_item_projection =
      ProjectConversation.load_repo_detail(
        project_detail,
        actor: Actor.operator_actor(),
        selected_work_item_id: second_work_item.id
      )

    assert selected_work_item_projection.conversation.id == second_conversation.id
    assert selected_work_item_projection.work_item.id == second_work_item.id
    assert selected_work_item_projection.action_label == "Resume governed conversation"

    assert {:ok, rows, _warning} = Inventory.load()
    row = Enum.find(rows, &(&1.managed_repo_id == managed_repo.id))
    refute is_nil(row)

    assert row.repo_conversation.repo_intake.conversation.id == repo_intake.id
    assert length(row.repo_conversation.active_work_items) == 2
    assert row.repo_conversation.active_work_item_notice == nil

    assert {:ok, summaries, _warning} = ConversationDashboardSummaryFeed.load()

    summary =
      Enum.find(summaries, fn dashboard_summary ->
        dashboard_summary.managed_repo_id == managed_repo.id
      end)

    refute is_nil(summary)
    assert summary.repo_intake_active? == true
    assert summary.active_work_item_count == 2
    assert summary.multiple_active? == true
    assert summary.route == "/repos/#{managed_repo.id}#project-detail-conversation-panel"
    assert summary.primary_route =~ "/repos/#{managed_repo.id}?work_item_id="
    assert Enum.any?(summary.work_items, &(&1.id == first_work_item_id))
    assert Enum.any?(summary.work_items, &(&1.id == second_work_item.id))
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
        name: "phase-fifty-#{suffix}",
        github_full_name: "owner/phase-fifty-#{suffix}",
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
        "jido-code-phase-fifty-#{suffix}-#{System.unique_integer([:positive])}"
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
      receive do
      after
        25 -> eventually_snapshot!(conversation_id, predicate, attempts - 1)
      end
    end
  end

  defp eventually_snapshot!(conversation_id, predicate, _attempts) do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)
    assert predicate.(snapshot)
    snapshot
  end
end
