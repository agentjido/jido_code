defmodule JidoCode.PhaseSeventyFourIntegrationTest do
  # covers: architecture.conversation_orchestration.long_term_conversation_recall_is_provenance_first
  # covers: architecture.memory_capture_plane.conversation_history_is_captured_as_workflow_provenance
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.Driver
  alias JidoCode.MemoryGraph.ProductService
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.{ProjectConversation, ProjectDetail}

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
    end)

    :ok
  end

  test "productive repo conversations record bounded workflow provenance with governed linkage intact" do
    {project, managed_repo, workspace_path} = managed_repo_fixture!("phase74-lineage")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase74-lineage-open"})
             )

    on_exit(fn -> stop_conversation(conversation.id) end)

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase74-lineage-turn"})
             )

    completed_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and
          snapshot.scope == :work_item_scoped and
          snapshot.active_turn == nil and
          snapshot.active_child_work == nil
      end)

    provenance_projection =
      eventually_provenance!(
        managed_repo.id,
        workspace_path,
        fn projection ->
          events =
            projection.items
            |> Enum.map(&get_in(&1, [:conversation_context, :conversation_event]))
            |> Enum.reject(&is_nil/1)

          "work_attached" in events and "turn_started" in events and "turn_completed" in events
        end,
        conversation_origin?: true,
        conversation_id: conversation.id,
        allow_stale?: true
      )

    assert Enum.any?(provenance_projection.items, fn item ->
             get_in(item, [:conversation_context, :conversation_id]) == conversation.id and
               get_in(item, [:conversation_context, :turn_id]) == completed_snapshot.work_resolution["turn_id"] and
               get_in(item, [:conversation_context, :command_id]) == completed_snapshot.work_resolution["command_id"]
           end)

    assert Enum.any?(provenance_projection.items, fn item ->
             Enum.any?(item.governed_context, &(&1.kind == :work_item and &1.id == completed_snapshot.work_item_id))
           end)

    assert Enum.all?(provenance_projection.items, fn item ->
             is_binary(item.revision_iri)
           end)
  end

  test "clarification and work attachment stay queryable as provenance without becoming durable memory" do
    {project, managed_repo, workspace_path} = managed_repo_fixture!("phase74-clarification")

    assert {:ok, project_detail} = ProjectDetail.load(project.id)

    assert {:ok, %{conversation: conversation, resumed?: false}} =
             ProjectConversation.open_repo_detail(
               project_detail,
               actor: Actor.operator_actor(%{"id" => "operator-phase74-clarify-open"})
             )

    on_exit(fn -> stop_conversation(conversation.id) end)

    assert {:ok, _running_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the repo detail conversation flow."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase74-clarify-first-turn"})
             )

    _attached_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        is_binary(snapshot.work_item_id) and snapshot.active_turn == nil and snapshot.active_child_work == nil
      end)

    assert {:ok, _clarification_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Clarify which file needs input."}
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase74-clarify-second-turn"})
             )

    awaiting_snapshot =
      eventually_snapshot!(conversation.id, fn snapshot ->
        (snapshot.active_turn &&
           snapshot.active_turn.state == :awaiting_input) and
          get_in(snapshot, [:shared_context, "pending_clarification", "prompt", "prompt"]) ==
            "Which file or module should I inspect first?"
      end)

    clarification_projection =
      eventually_provenance!(
        managed_repo.id,
        workspace_path,
        fn projection ->
          Enum.any?(projection.items, fn item ->
            get_in(item, [:conversation_context, :conversation_event]) == "clarification_requested"
          end)
        end,
        conversation_origin?: true,
        conversation_id: conversation.id,
        conversation_event: "clarification_requested",
        allow_stale?: true
      )

    assert Enum.any?(clarification_projection.items, fn item ->
             get_in(item, [:conversation_context, :clarification_state]) == "awaiting_input" and
               String.contains?(item.content || "", "Which file or module should I inspect first?")
           end)

    work_attachment_projection =
      eventually_provenance!(
        managed_repo.id,
        workspace_path,
        fn projection ->
          projection.items != []
        end,
        conversation_origin?: true,
        conversation_id: conversation.id,
        conversation_event: "work_attached",
        allow_stale?: true
      )

    assert work_attachment_projection.items != []
    assert awaiting_snapshot.shared_context["work_item_id"]

    assert {:ok, memory_projection} =
             ProductService.memories(
               managed_repo.id,
               workspace_path,
               content_contains: "Which file or module should I inspect first?",
               allow_stale?: true
             )

    assert memory_projection.items == []
  end

  test "conversation snapshots still recover when provenance capture is unavailable" do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, false)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
    end)

    {_project, managed_repo, _workspace_path} = managed_repo_fixture!("phase74-no-provenance")

    assert {:ok, %{conversation: conversation}} =
             Driver.start_conversation(%{
               managed_repo_id: managed_repo.id,
               source: "conversation",
               objective: "Exercise snapshot recovery without semantic provenance."
             })

    on_exit(fn -> stop_conversation(conversation.id) end)

    assert {:ok, running_snapshot} =
             Driver.handle_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{
                   instruction: "Inspect persisted recovery without provenance capture.",
                   referenced_files: ["lib/jido_code/conversations/runtime.ex"]
                 }
               },
               actor: Actor.operator_actor(%{"id" => "operator-phase74-no-provenance"})
             )

    assert :ok = Driver.stop(conversation.id)

    assert {:ok, persisted_snapshot} = Driver.snapshot(conversation.id)

    assert persisted_snapshot.conversation_id == conversation.id
    assert persisted_snapshot.last_event_sequence == running_snapshot.last_event_sequence
    assert persisted_snapshot.active_turn_id == running_snapshot.active_turn_id
    assert persisted_snapshot.active_child_work_id == running_snapshot.active_child_work_id
    assert persisted_snapshot.shared_context["referenced_files"] == ["lib/jido_code/conversations/runtime.ex"]

    assert {:ok, replayed_events} =
             Driver.events_since(conversation.id, 0, actor: Actor.operator_actor())

    assert Enum.map(replayed_events, & &1.name) == [
             "conversation.message_added",
             "turn.queued",
             "turn.intent_announced",
             "turn.started",
             "tool.started"
           ]
  end

  defp eventually_provenance!(managed_repo_id, workspace_path, predicate, opts, attempts \\ 80)

  defp eventually_provenance!(managed_repo_id, workspace_path, predicate, opts, attempts)
       when is_function(predicate, 1) and attempts > 1 do
    assert {:ok, projection} = ProductService.provenance(managed_repo_id, workspace_path, opts)

    if predicate.(projection) do
      projection
    else
      receive do
      after
        50 -> eventually_provenance!(managed_repo_id, workspace_path, predicate, opts, attempts - 1)
      end
    end
  end

  defp eventually_provenance!(managed_repo_id, workspace_path, predicate, opts, _attempts)
       when is_function(predicate, 1) do
    assert {:ok, projection} = ProductService.provenance(managed_repo_id, workspace_path, opts)
    assert predicate.(projection)
    projection
  end

  defp eventually_snapshot!(conversation_id, predicate, attempts \\ 120)

  defp eventually_snapshot!(conversation_id, predicate, attempts)
       when is_binary(conversation_id) and is_function(predicate, 1) and attempts > 1 do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)

    if predicate.(snapshot) do
      snapshot
    else
      receive do
      after
        50 -> eventually_snapshot!(conversation_id, predicate, attempts - 1)
      end
    end
  end

  defp eventually_snapshot!(conversation_id, predicate, _attempts) do
    assert {:ok, snapshot} = AgentWorkspace.conversation_snapshot(conversation_id)
    assert predicate.(snapshot)
    snapshot
  end

  defp managed_repo_fixture!(suffix) do
    workspace_path = create_workspace_path!(suffix)

    {:ok, project} =
      Project.create(%{
        name: "phase-seventy-four-#{suffix}",
        github_full_name: "owner/phase-seventy-four-#{suffix}",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo, workspace_path}
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_seventy_four_#{suffix}_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [app: :example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule ExampleWorkspace do
        def greet(name), do: "hello \#{name}"
      end
      """
    )

    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp stop_conversation(conversation_id) do
    case AgentWorkspace.stop_conversation(conversation_id) do
      :ok -> :ok
      {:error, _reason} -> :ok
    end
  end
end
