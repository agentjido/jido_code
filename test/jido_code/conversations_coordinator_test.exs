defmodule JidoCode.ConversationsCoordinatorTest do
  # covers: architecture.conversation_orchestration.coordinator_owns_turn_admission_and_state
  # covers: architecture.conversation_orchestration.control_and_work_commands_are_distinct
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Conversations.{ChildWork, Command, Conversation, Coordinator, PubSub, Turn}
  alias JidoCode.Projects.Project

  setup do
    original_persistence = Application.get_env(:jido_code, JidoCode.Conversations.Persistence)
    Application.put_env(:jido_code, JidoCode.Conversations.Persistence, enabled: false)

    on_exit(fn ->
      if original_persistence do
        Application.put_env(:jido_code, JidoCode.Conversations.Persistence, original_persistence)
      else
        Application.delete_env(:jido_code, JidoCode.Conversations.Persistence)
      end
    end)

    :ok
  end

  test "command normalization separates work and control commands" do
    actor = %{"id" => "operator-1", "actor_class" => "operator"}

    assert {:ok, work_command} =
             Command.normalize(
               %{type: "turn.submit", payload: %{instruction: "Plan the next step."}},
               actor
             )

    assert work_command.class == :work
    assert work_command.type == :turn_submit
    assert work_command.payload["instruction"] == "Plan the next step."

    assert {:ok, control_command} =
             Command.normalize(
               %{type: "session.pause", payload: %{reason: "Operator paused."}},
               actor
             )

    assert control_command.class == :control
    assert control_command.type == :session_pause
    assert control_command.payload["reason"] == "Operator paused."
  end

  test "coordinator admits work turns, pauses the session, and resumes queued work" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-2", "actor_class" => "operator"}

    assert {:ok, first_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Review the current plan."}},
               actor
             )

    assert first_snapshot.status == :active
    assert first_snapshot.active_turn.command_type == "turn.submit"
    assert first_snapshot.active_turn.state == :running
    assert first_snapshot.active_child_work.turn_id == first_snapshot.active_turn.id
    assert first_snapshot.active_child_work.state == :running
    refute Map.has_key?(first_snapshot, :pod_id)
    refute Map.has_key?(first_snapshot, :kernel_name)

    assert {:ok, second_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Prepare the next step."}},
               actor
             )

    assert second_snapshot.active_turn.id == first_snapshot.active_turn.id
    assert length(second_snapshot.queued_turn_ids) == 1

    assert {:ok, paused_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "session.pause", payload: %{reason: "Operator pause"}},
               actor
             )

    assert paused_snapshot.status == :paused
    assert paused_snapshot.admission_paused
    refute paused_snapshot.child_execution_paused
    assert Enum.any?(paused_snapshot.control_history, &(&1.type == "session.pause"))

    assert {:ok, completed_snapshot} =
             Coordinator.transition_turn(
               conversation.id,
               first_snapshot.active_turn.id,
               :completed
             )

    assert completed_snapshot.active_turn == nil
    assert completed_snapshot.queued_turn_ids == [List.first(second_snapshot.queued_turn_ids)]

    assert {:ok, resumed_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "session.resume", payload: %{}},
               actor
             )

    assert resumed_snapshot.status == :active
    refute resumed_snapshot.admission_paused
    refute resumed_snapshot.child_execution_paused
    assert resumed_snapshot.active_turn.id == List.first(second_snapshot.queued_turn_ids)
    assert resumed_snapshot.active_turn.state == :running
    assert resumed_snapshot.active_child_work.turn_id == resumed_snapshot.active_turn.id
    assert resumed_snapshot.queued_turn_ids == []
  end

  test "coordinator records sequenced events and broadcasts typed conversation events" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-events", "actor_class" => "operator"}

    assert :ok = PubSub.subscribe_conversation(conversation.id)

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the current event stream."}
               },
               actor
             )

    assert running_snapshot.last_event_sequence == 5
    assert running_snapshot.event_count == 5
    assert Enum.map(running_snapshot.events, & &1.sequence) == [1, 2, 3, 4, 5]

    assert Enum.map(running_snapshot.events, & &1.name) == [
             "conversation.message_added",
             "turn.queued",
             "turn.intent_announced",
             "turn.started",
             "tool.started"
           ]

    assert Enum.all?(running_snapshot.events, &(&1.conversation_id == conversation.id))
    assert Enum.all?(running_snapshot.events, &(is_binary(&1.id) and &1.id != ""))
    assert running_snapshot.active_turn.actor["id"] == "operator-events"
    assert running_snapshot.active_child_work.actor["id"] == "operator-events"

    assert_receive {:conversation_event, %{name: "conversation.message_added", sequence: 1}}
    assert_receive {:conversation_event, %{name: "turn.queued", sequence: 2}}
    assert_receive {:conversation_event, %{name: "turn.intent_announced", sequence: 3}}
    assert_receive {:conversation_event, %{name: "turn.started", sequence: 4}}
    assert_receive {:conversation_event, %{name: "tool.started", sequence: 5}}

    assert {:ok, replayed_events} = Coordinator.events_since(conversation.id, 3)
    assert Enum.map(replayed_events, & &1.name) == ["turn.started", "tool.started"]
  end

  test "coordinator routes tool-result updates and turn resumes through explicit runtime events" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-runtime", "actor_class" => "operator"}

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the clarification loop."}},
               actor
             )

    child_work_id = running_snapshot.active_child_work_id
    turn_id = running_snapshot.active_turn_id

    assert {:ok, progress_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "progress",
                   summary: "Scanning the conversation runtime.",
                   percent: 25
                 }
               },
               actor
             )

    assert progress_snapshot.active_child_work.result["latest_progress"]["summary"] ==
             "Scanning the conversation runtime."

    assert List.last(progress_snapshot.events).name == "tool.progress"

    assert {:ok, stdout_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "stdout",
                   text: "rg turn.resume lib/jido_code/conversations"
                 }
               },
               actor
             )

    assert stdout_snapshot.active_child_work.result["stdout"] == [
             "rg turn.resume lib/jido_code/conversations"
           ]

    assert List.last(stdout_snapshot.events).name == "tool.stdout"

    assert {:ok, awaiting_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "tool_result.submit",
                 payload: %{
                   child_work_id: child_work_id,
                   kind: "needs_input",
                   prompt: "Which file should the tool inspect first?"
                 }
               },
               actor
             )

    assert awaiting_snapshot.active_turn.state == :awaiting_input

    assert awaiting_snapshot.shared_context["pending_clarification"]["prompt"]["prompt"] ==
             "Which file should the tool inspect first?"

    assert Enum.map(Enum.take(awaiting_snapshot.events, -2), & &1.name) == [
             "tool.needs_input",
             "turn.awaiting_input"
           ]

    assert {:ok, resumed_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "turn.resume",
                 payload: %{
                   turn_id: turn_id,
                   response: "Start with the coordinator module."
                 }
               },
               actor
             )

    assert resumed_snapshot.active_turn.id == turn_id
    assert resumed_snapshot.active_turn.state == :running
    assert resumed_snapshot.shared_context["pending_clarification"] == nil
    refute Map.has_key?(resumed_snapshot.active_child_work.result || %{}, "needs_input")

    assert Enum.map(Enum.take(resumed_snapshot.events, -2), & &1.name) == [
             "conversation.message_added",
             "turn.started"
           ]
  end

  test "coordinator admits tool.cancel as a control command against the active child work" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-tool-cancel", "actor_class" => "operator"}

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the active child work."}},
               actor
             )

    child_work_id = running_snapshot.active_child_work_id
    turn_id = running_snapshot.active_turn_id

    assert {:ok, cancellation_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "tool.cancel", payload: %{}},
               actor
             )

    assert cancellation_snapshot.active_turn.id == turn_id
    assert cancellation_snapshot.active_turn.state == :cancelling
    assert cancellation_snapshot.active_child_work.id == child_work_id
    assert cancellation_snapshot.active_child_work.state == :cancel_acknowledged
    assert Enum.any?(cancellation_snapshot.control_history, &(&1.type == "tool.cancel"))

    assert Enum.map(Enum.take(cancellation_snapshot.events, -4), & &1.name) == [
             "conversation.message_added",
             "turn.cancelling",
             "tool.cancel_requested",
             "tool.cancel_acknowledged"
           ]

    assert {:ok, settled_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               child_work_id,
               :cancelled,
               %{result: %{reason: "Operator cancelled the active tool."}},
               actor
             )

    cancelled_turn = Enum.find(settled_snapshot.turns, &(&1.id == turn_id))
    cancelled_child_work = Enum.find(settled_snapshot.child_works, &(&1.id == child_work_id))

    assert settled_snapshot.active_turn == nil
    assert settled_snapshot.active_child_work == nil
    assert cancelled_turn.state == :cancelled
    assert cancelled_child_work.state == :cancelled
  end

  test "coordinator tracks child work ownership, cancellation, and settled outcomes explicitly" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-3", "actor_class" => "operator"}

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Inspect the failing test.", tool_call_id: "tool-call-1"}
               },
               actor
             )

    child_work = running_snapshot.active_child_work

    assert child_work.conversation_id == conversation.id
    assert child_work.managed_repo_id == conversation.managed_repo_id
    assert child_work.work_item_id == conversation.work_item_id
    assert child_work.turn_id == running_snapshot.active_turn.id
    assert child_work.tool_call_id == "tool-call-1"
    assert child_work.kind == "tool_call"

    assert {:ok, cancellation_snapshot} =
             Coordinator.cancel_child_work(conversation.id, child_work.id)

    assert cancellation_snapshot.active_child_work.state == :cancel_acknowledged

    assert Enum.map(cancellation_snapshot.active_child_work.lifecycle, & &1["state"]) == [
             "queued",
             "running",
             "cancel_requested",
             "cancel_acknowledged"
           ]

    assert {:ok, settled_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               child_work.id,
               :cancelled,
               %{"result" => %{"reason" => "Operator stopped the tool call."}}
             )

    settled_turn = Enum.find(settled_snapshot.turns, &(&1.id == child_work.turn_id))
    settled_child_work = Enum.find(settled_snapshot.child_works, &(&1.id == child_work.id))

    assert settled_snapshot.active_turn == nil
    assert settled_snapshot.active_child_work == nil
    assert settled_turn.state == :cancelled
    assert settled_child_work.state == :cancelled
    assert settled_child_work.result["reason"] == "Operator stopped the tool call."
  end

  test "child work settles completion before a later cancel can land" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-4", "actor_class" => "operator"}

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Run the analysis."}},
               actor
             )

    child_work_id = running_snapshot.active_child_work_id

    assert {:ok, completed_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               child_work_id,
               :completed,
               %{result: %{summary: "Analysis finished before cancellation landed."}}
             )

    completed_child_work = Enum.find(completed_snapshot.child_works, &(&1.id == child_work_id))
    completed_turn = Enum.find(completed_snapshot.turns, &(&1.child_work_id == child_work_id))

    assert completed_child_work.state == :completed
    assert completed_turn.state == :completed

    assert {:error, :child_work_already_settled} =
             Coordinator.cancel_child_work(conversation.id, child_work_id)
  end

  test "turn stop marks the active turn as cancelling before it settles cancelled" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-5", "actor_class" => "operator"}

    assert {:ok, running_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Run the current plan."}},
               actor
             )

    child_work_id = running_snapshot.active_child_work_id

    assert {:ok, stopping_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.stop", payload: %{reason: "Stop the current turn."}},
               actor
             )

    assert stopping_snapshot.active_turn.state == :cancelling
    assert stopping_snapshot.active_child_work.state == :cancel_acknowledged

    assert {:ok, cancelled_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               child_work_id,
               :cancelled,
               %{result: %{reason: "Stop completed."}}
             )

    cancelled_turn = Enum.find(cancelled_snapshot.turns, &(&1.child_work_id == child_work_id))

    assert cancelled_snapshot.active_turn == nil
    assert cancelled_turn.state == :cancelled
  end

  test "turn steer overtakes queued work and preserves supersession links" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-6", "actor_class" => "operator"}

    assert {:ok, first_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the failing workflow."}},
               actor
             )

    assert {:ok, second_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Prepare the old follow-up plan."}},
               actor
             )

    queued_turn_id = List.first(second_snapshot.queued_turn_ids)

    assert {:ok, steering_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "turn.steer",
                 payload: %{instruction: "Narrow the scope to the failing test only."}
               },
               actor
             )

    replacement_turn = List.last(steering_snapshot.turns)

    assert steering_snapshot.active_turn.id == first_snapshot.active_turn.id
    assert steering_snapshot.active_turn.state == :superseding
    assert steering_snapshot.active_child_work.state == :cancel_acknowledged
    assert steering_snapshot.queued_turn_ids == [replacement_turn.id, queued_turn_id]
    assert replacement_turn.command_type == "turn.steer"
    assert replacement_turn.supersedes_turn_id == first_snapshot.active_turn.id

    assert {:ok, superseded_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               first_snapshot.active_child_work_id,
               :cancelled,
               %{result: %{reason: "Steering replaced the previous turn."}}
             )

    superseded_turn =
      Enum.find(superseded_snapshot.turns, &(&1.id == first_snapshot.active_turn.id))

    replacement_turn = Enum.find(superseded_snapshot.turns, &(&1.id == replacement_turn.id))

    assert superseded_turn.state == :superseded
    assert superseded_turn.superseded_by_turn_id == replacement_turn.id
    assert superseded_snapshot.active_turn.id == replacement_turn.id
    assert superseded_snapshot.active_turn.state == :running
    assert superseded_snapshot.queued_turn_ids == [queued_turn_id]
  end

  test "child worker start uses child supervisor when available" do
    conversation = conversation_fixture()
    assert_child_supervisor_accepts_child!(conversation)
  end

  test "queued child work starts during normal activation" do
    conversation = conversation_fixture()
    assert_child_supervisor_accepts_child!(conversation)
    start_coordinator!(conversation)

    actor = %{"id" => "operator-supervised-child-work", "actor_class" => "operator"}

    assert {:ok, first_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the current branch."}},
               actor
             )

    assert {:ok, queued_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Prepare the follow-up work."}},
               actor
             )

    queued_turn_id = List.first(queued_snapshot.queued_turn_ids)

    assert {:ok, activated_snapshot} =
             Coordinator.settle_child_work(
               conversation.id,
               first_snapshot.active_child_work_id,
               :completed,
               %{result: %{summary: "First child work completed."}},
               actor
             )

    assert activated_snapshot.active_turn.id == queued_turn_id
    assert activated_snapshot.active_child_work.state == :running
    refute Enum.any?(activated_snapshot.events, &(&1.name == "turn.activation_failed"))

    pid = coordinator_child_worker_pid(conversation.id, activated_snapshot.active_child_work_id)
    assert Process.alive?(pid)
  end

  test "queued replacement turn activates while child supervisor name is temporarily unavailable" do
    conversation = conversation_fixture()
    start_coordinator!(conversation)

    actor = %{"id" => "operator-child-supervisor-unavailable", "actor_class" => "operator"}

    assert {:ok, first_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Inspect the failing workflow."}},
               actor
             )

    assert {:ok, second_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{type: "turn.submit", payload: %{instruction: "Prepare the old follow-up plan."}},
               actor
             )

    queued_turn_id = List.first(second_snapshot.queued_turn_ids)

    assert {:ok, steering_snapshot} =
             Coordinator.admit_command(
               conversation.id,
               %{
                 type: "turn.steer",
                 payload: %{instruction: "Narrow the scope to the failing test only."}
               },
               actor
             )

    replacement_turn = List.last(steering_snapshot.turns)

    assert {:ok, superseded_snapshot} =
             with_unregistered_child_supervisor(fn ->
               Coordinator.settle_child_work(
                 conversation.id,
                 first_snapshot.active_child_work_id,
                 :cancelled,
                 %{result: %{reason: "Steering replaced the previous turn."}},
                 actor
               )
             end)

    superseded_turn =
      Enum.find(superseded_snapshot.turns, &(&1.id == first_snapshot.active_turn.id))

    replacement_turn = Enum.find(superseded_snapshot.turns, &(&1.id == replacement_turn.id))

    assert superseded_turn.state == :superseded
    assert superseded_turn.superseded_by_turn_id == replacement_turn.id
    assert superseded_snapshot.active_turn.id == replacement_turn.id
    assert superseded_snapshot.active_turn.state == :running
    assert superseded_snapshot.active_child_work.state == :running
    assert superseded_snapshot.queued_turn_ids == [queued_turn_id]

    pid = coordinator_child_worker_pid(conversation.id, superseded_snapshot.active_child_work_id)
    assert Process.alive?(pid)
  end

  test "turn transition keeps lifecycle history explicit" do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    turn =
      Turn.new("conversation-1", %{
        id: Ecto.UUID.generate(),
        raw_type: "turn.submit",
        payload: %{},
        admitted_at: now
      })

    assert {:ok, running_turn} = Turn.transition(turn, :running)
    assert {:ok, awaiting_input_turn} = Turn.transition(running_turn, :awaiting_input)
    assert {:ok, completed_turn} = Turn.transition(awaiting_input_turn, :completed)

    assert Enum.map(completed_turn.lifecycle, & &1["state"]) == [
             "queued",
             "running",
             "awaiting_input",
             "completed"
           ]

    assert completed_turn.completed_at != nil
  end

  test "child work lifecycle keeps cancellation outcomes explicit" do
    conversation = conversation_fixture()
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    turn =
      Turn.new(conversation.id, %{
        id: Ecto.UUID.generate(),
        raw_type: "turn.submit",
        payload: %{},
        admitted_at: now
      })

    child_work = ChildWork.new(conversation, turn)

    assert {:ok, running_child_work} = ChildWork.start(child_work)
    assert {:ok, requested_child_work} = ChildWork.request_cancel(running_child_work)
    assert {:ok, acknowledged_child_work} = ChildWork.acknowledge_cancel(requested_child_work)

    assert {:ok, cancelled_child_work} =
             ChildWork.settle(acknowledged_child_work, :cancelled, %{
               result: %{reason: "Operator stopped the tool."}
             })

    assert Enum.map(cancelled_child_work.lifecycle, & &1["state"]) == [
             "queued",
             "running",
             "cancel_requested",
             "cancel_acknowledged",
             "cancelled"
           ]

    assert cancelled_child_work.result["reason"] == "Operator stopped the tool."
  end

  defp conversation_fixture do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
    managed_repo = managed_repo_fixture!("coordinator")

    {:ok, conversation} =
      Conversation.create(
        %{
          managed_repo_id: managed_repo.id,
          work_item_id: nil,
          status: :active,
          scope: :repo_scoped,
          attachment_mode: :pre_work,
          source: "conversation",
          title: "Phase 39 Coordinator Test",
          objective: "Exercise coordinator behavior with governed conversation state.",
          initiating_actor: %{"id" => "operator-test", "actor_class" => "operator"},
          source_metadata: %{},
          conversation_metadata: %{},
          started_at: now,
          last_activity_at: now
        },
        actor: Actor.operator_actor(%{"id" => "operator-test"})
      )

    conversation
  end

  defp start_coordinator!(conversation) do
    start_supervised!(
      {Coordinator, {conversation, starter_pid: self(), sandbox_owner: Process.get({JidoCode.Repo, :sandbox_owner})}}
    )
  end

  defp coordinator_child_worker_pid(conversation_id, child_work_id) do
    Coordinator.via_tuple(conversation_id)
    |> :sys.get_state()
    |> Map.fetch!(:child_worker_pids)
    |> Map.fetch!(child_work_id)
  end

  defp supervised_child_worker?(pid) when is_pid(pid) do
    JidoCode.Conversations.ChildSupervisor
    |> DynamicSupervisor.which_children()
    |> Enum.any?(fn {_id, child_pid, _type, _modules} -> child_pid == pid end)
  end

  defp assert_child_supervisor_accepts_child!(conversation) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    turn =
      Turn.new(conversation.id, %{
        id: Ecto.UUID.generate(),
        raw_type: "turn.submit",
        payload: %{},
        admitted_at: now
      })

    child_work = ChildWork.new(conversation, turn)

    assert {:ok, pid} =
             DynamicSupervisor.start_child(
               JidoCode.Conversations.ChildSupervisor,
               {JidoCode.Conversations.ChildWorker, child_work}
             )

    assert supervised_child_worker?(pid)
    assert :ok = DynamicSupervisor.terminate_child(JidoCode.Conversations.ChildSupervisor, pid)
  end

  defp with_unregistered_child_supervisor(fun) when is_function(fun, 0) do
    supervisor_name = JidoCode.Conversations.ChildSupervisor
    supervisor_pid = Process.whereis(supervisor_name)

    assert is_pid(supervisor_pid)
    assert Process.unregister(supervisor_name)

    try do
      assert Process.whereis(supervisor_name) == nil
      fun.()
    after
      if Process.whereis(supervisor_name) == nil and Process.alive?(supervisor_pid) do
        Process.register(supervisor_pid, supervisor_name)
      end
    end
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, project} =
      Project.create(%{
        name: "coordinator-#{suffix}",
        github_full_name: "owner/coordinator-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end
end
