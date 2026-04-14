defmodule JidoCode.PhaseFortySevenIntegrationTest do
  # covers: architecture.conversation_orchestration.productive_turns_attach_to_canonical_work_items
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.work_synthesis.productive_conversations_route_through_work_resolution
  # covers: architecture.work_synthesis.work_item_origin_can_preserve_conversation_context
  # covers: architecture.work_synthesis.work_item_reprioritization_and_duplicate_suppression
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  test "productive repo conversations attach governed work and preserve linkage through clarification and resume" do
    {project, managed_repo} = managed_repo_fixture!("work-attachment")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, snapshot: initial_snapshot, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase47-open"})
             )

    track_conversation!(tracked_conversations, conversation.id)

    assert initial_snapshot.work_item_id == nil
    assert initial_snapshot.scope == :repo_scoped

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase47-first-turn"})
             )

    attached_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.scope == :work_item_scoped and
          snapshot.attachment_mode == :synthesized_work_item and
          snapshot.active_turn == nil and snapshot.active_child_work == nil and
          Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
            get_in(result, ["result", "workflow"]) == "explain" and
              String.contains?(
                get_in(result, ["result", "summary"]) || "",
                "deterministic explainer response"
              )
          end)
      end)

    work_item_id = attached_snapshot.work_item_id

    assert attached_snapshot.work_resolution["work_item_id"] == work_item_id
    assert attached_snapshot.work_resolution["action"] == "created"
    assert attached_snapshot.shared_context["work_item_id"] == work_item_id
    assert attached_snapshot.shared_context["work_resolution"]["work_item_id"] == work_item_id

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: Actor.operator_actor())

    assert persisted_work_item.summary == "Queue review operator request work for the managed repository."

    origin = persisted_work_item.work_metadata["conversation_origin"]

    assert origin["conversation_id"] == conversation.id
    assert origin["turn_id"] == attached_snapshot.work_resolution["turn_id"]
    assert origin["command_id"] == attached_snapshot.work_resolution["command_id"]
    assert origin["workflow"] == "explain"

    assert origin["resolution_reason"] ==
             "Governed follow-up and explanation work should remain linked to canonical WorkItem scope."

    assert {:ok, events_after_attachment} =
             AgentWorkspace.conversation_events_since(
               conversation.id,
               initial_snapshot.last_event_sequence,
               actor: Actor.operator_actor()
             )

    assert Enum.any?(events_after_attachment, fn event ->
             event.name == "turn.started" and
               get_in(event, [:payload, "work_context", "work_item_id"]) == work_item_id and
               get_in(event, [:correlation, "work_item_id"]) == work_item_id
           end)

    projection_after_attachment =
      ProjectConversation.load_repo_detail(project_detail, actor: Actor.operator_actor())

    assert projection_after_attachment.conversation.work_item_id == work_item_id
    assert projection_after_attachment.conversation.work_resolution["action"] == "created"
    assert projection_after_attachment.work_item.id == work_item_id
    assert projection_after_attachment.work_item.summary == persisted_work_item.summary

    clarification_checkpoint = attached_snapshot.last_event_sequence

    assert {:ok, _clarification_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Clarify which file needs input."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase47-clarify"})
             )

    awaiting_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.work_item_id == work_item_id and
          snapshot.active_turn &&
          snapshot.active_turn.state == :awaiting_input and
          get_in(snapshot, [:shared_context, "pending_clarification", "prompt", "prompt"]) ==
            "Which file or module should I inspect first?"
      end)

    assert awaiting_snapshot.shared_context["work_item_id"] == work_item_id
    assert awaiting_snapshot.shared_context["work_resolution"]["work_item_id"] == work_item_id

    assert {:ok, clarification_events} =
             AgentWorkspace.conversation_events_since(
               conversation.id,
               clarification_checkpoint,
               actor: Actor.operator_actor()
             )

    assert Enum.any?(clarification_events, &(&1.name == "tool.needs_input"))
    assert Enum.any?(clarification_events, &(&1.name == "turn.awaiting_input"))

    assert clarification_events
           |> Enum.filter(&is_map(Map.get(&1.payload, "work_context")))
           |> Enum.all?(fn event ->
             get_in(event, [:payload, "work_context", "work_item_id"]) == work_item_id
           end)

    turn_id = awaiting_snapshot.active_turn_id

    assert {:ok, resumed_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: turn_id,
                   response: "lib/jido_code_web/live/project_detail_live.ex"
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase47-resume"})
             )

    assert resumed_snapshot.work_item_id == work_item_id
    assert resumed_snapshot.active_turn.state == :running

    resumed_completion_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        snapshot.work_item_id == work_item_id and
          snapshot.active_turn == nil and snapshot.active_child_work == nil and
          Enum.any?(snapshot.shared_context["accepted_tool_results"], fn result ->
            summary = get_in(result, ["result", "summary"]) || ""

            get_in(result, ["result", "workflow"]) == "explain" and
              String.contains?(summary, "deterministic explainer response") and
              String.contains?(summary, "lib/jido_code_web/live/project_detail_live.ex")
          end)
      end)

    assert resumed_completion_snapshot.shared_context["work_item_id"] == work_item_id
    assert resumed_completion_snapshot.shared_context["work_resolution"]["work_item_id"] == work_item_id
  end

  test "equivalent productive repo conversations reuse the same governed work item" do
    {project, managed_repo} = managed_repo_fixture!("work-dedup")
    tracked_conversations = tracked_conversations!(managed_repo.id)

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: first_conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase47-dedup-first"})
             )

    track_conversation!(tracked_conversations, first_conversation.id)

    assert {:ok, _first_running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               first_conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase47-dedup-first-turn"})
             )

    first_completed_snapshot =
      eventually_snapshot!(first_conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.active_turn == nil and snapshot.active_child_work == nil and
          snapshot.work_resolution["action"] == "created"
      end)

    first_work_item_id = first_completed_snapshot.work_item_id

    assert {:ok, %{conversation: second_conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase47-dedup-second"}),
               restart?: true
             )

    track_conversation!(tracked_conversations, second_conversation.id)
    refute second_conversation.id == first_conversation.id

    assert {:ok, _second_running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               second_conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase47-dedup-second-turn"})
             )

    second_completed_snapshot =
      eventually_snapshot!(second_conversation.id, fn snapshot ->
        snapshot.work_item_id == first_work_item_id and
          snapshot.scope == :work_item_scoped and
          snapshot.active_turn == nil and snapshot.active_child_work == nil and
          snapshot.work_resolution["action"] in ["suppressed_duplicate", "reprioritized"]
      end)

    assert second_completed_snapshot.work_item_id == first_work_item_id
    assert second_completed_snapshot.work_resolution["work_item_id"] == first_work_item_id
    assert second_completed_snapshot.shared_context["work_item_id"] == first_work_item_id

    assert {:ok, [persisted_work_item]} =
             WorkItem.read(
               query: [filter: [id: first_work_item_id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert List.last(persisted_work_item.audit_log)["action"] in ["suppressed_duplicate", "reprioritized"]
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
        name: "phase-forty-seven-#{suffix}",
        github_full_name: "owner/phase-forty-seven-#{suffix}",
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
        "jido-code-phase-forty-seven-#{suffix}-#{System.unique_integer([:positive])}"
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
