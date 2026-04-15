defmodule JidoCode.PhaseFiftyOneIntegrationTest do
  # covers: architecture.conversation_orchestration.active_conversation_uniqueness_is_per_work_item
  # covers: architecture.conversation_orchestration.work_item_conversation_lifecycle_tracks_governed_work_status
  # covers: architecture.conversation_orchestration.workbench_and_governed_run_surfaces_project_conversation_linkage
  # covers: architecture.work_synthesis.active_conversation_identity_rejoins_work_item
  # covers: architecture.work_synthesis.historical_conversation_lineage_stays_attached_to_work_item
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations
  alias JidoCode.Operations.{Ingress, WorkItem}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.ProjectConversation

  test "completed work-item conversations settle into historical lineage and reopening yields a fresh active thread" do
    {_project, managed_repo} = managed_repo_fixture!("runtime-lifecycle")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    first_work_item = work_item_fixture!(managed_repo, "phase51-first")
    second_work_item = work_item_fixture!(managed_repo, "phase51-second")

    assert {:ok, %{conversation: first_conversation, resumed?: false}} =
             AgentWorkspace.open_work_item_conversation(
               first_work_item.id,
               %{
                 source: "phase_fifty_one_integration_test",
                 objective: "Coordinate the first governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase51-first-open"})
             )

    track_conversation!(tracked_conversations, first_conversation.id)

    assert {:ok, %{conversation: second_conversation, resumed?: false}} =
             AgentWorkspace.open_work_item_conversation(
               second_work_item.id,
               %{
                 source: "phase_fifty_one_integration_test",
                 objective: "Coordinate the second governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase51-second-open"})
             )

    track_conversation!(tracked_conversations, second_conversation.id)

    assert {:ok, active_conversations} =
             AgentWorkspace.active_work_item_conversations(managed_repo.id,
               actor: Actor.operator_actor()
             )

    active_by_work_item =
      Map.new(active_conversations, fn conversation ->
        {conversation.work_item_id, conversation.id}
      end)

    assert active_by_work_item[first_work_item.id] == first_conversation.id
    assert active_by_work_item[second_work_item.id] == second_conversation.id

    assert {:ok, completed_work_item} =
             WorkItem.update(first_work_item, %{status: :completed}, actor: Actor.operator_actor())

    assert {:ok, %{work_item: settled_work_item, active_conversation: nil, settled_conversation: settled_conversation}} =
             Conversations.reconcile_work_item_conversation_lifecycle(
               completed_work_item.id,
               actor: Actor.operator_actor()
             )

    assert settled_work_item.status == :completed
    assert settled_conversation.id == first_conversation.id
    assert settled_conversation.status == :completed

    historical_projection =
      ProjectConversation.load_work_item_linkage(completed_work_item.id, actor: Actor.operator_actor())

    assert historical_projection.work_item.id == completed_work_item.id
    assert historical_projection.conversation.id == first_conversation.id
    assert historical_projection.conversation.status == :completed
    assert historical_projection.historical_conversation == nil
    assert historical_projection.notice.error_type == "work_item_conversation_historical_only"
    assert historical_projection.action_label == "Open governed conversation"

    assert {:ok, reopened_work_item} =
             WorkItem.update(completed_work_item, %{status: :open}, actor: Actor.operator_actor())

    assert {:ok, %{conversation: reopened_conversation, resumed?: false}} =
             AgentWorkspace.open_work_item_conversation(
               reopened_work_item.id,
               %{
                 source: "phase_fifty_one_integration_test",
                 objective: "Continue the reopened governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase51-first-reopen"})
             )

    track_conversation!(tracked_conversations, reopened_conversation.id)

    refute reopened_conversation.id == first_conversation.id

    reopened_projection =
      ProjectConversation.load_work_item_linkage(reopened_work_item.id, actor: Actor.operator_actor())

    assert reopened_projection.work_item.id == reopened_work_item.id
    assert reopened_projection.conversation.id == reopened_conversation.id
    assert reopened_projection.conversation.status == :active
    assert reopened_projection.historical_conversation.id == first_conversation.id
    assert reopened_projection.notice.error_type == "work_item_conversation_historical_lineage"
    assert reopened_projection.action_label == "Resume governed conversation"

    assert {:ok, final_active_conversations} =
             AgentWorkspace.active_work_item_conversations(managed_repo.id,
               actor: Actor.operator_actor()
             )

    final_active_by_work_item =
      Map.new(final_active_conversations, fn conversation ->
        {conversation.work_item_id, conversation.id}
      end)

    assert final_active_by_work_item[reopened_work_item.id] == reopened_conversation.id
    assert final_active_by_work_item[second_work_item.id] == second_conversation.id
    assert map_size(final_active_by_work_item) == 2

    project_route_projection =
      ProjectConversation.load_managed_repo(managed_repo.id, actor: Actor.operator_actor())

    assert project_route_projection.conversation == nil or
             project_route_projection.conversation.scope == :repo_scoped
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
        name: "phase-fifty-one-#{suffix}",
        github_full_name: "owner/phase-fifty-one-#{suffix}",
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
        "jido-code-phase-fifty-one-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
