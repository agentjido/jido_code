defmodule JidoCode.Conversations.PhaseSevenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.conversation_driver.public_jido_os_turn_event_bridge
  # covers: architecture.conversation_driver.public_turn_live_delivery_is_preferred_incremental_path
  # covers: architecture.conversation_driver.replay_bridge_drives_subscriber_updates
  # covers: architecture.conversation_driver.explicit_terminal_handoff_drives_completion_translation
  # covers: architecture.conversation_driver.subscriber_event_contract_preserved
  # covers: architecture.factory_control_plane.runtime_turns_feed_governed_control_records
  # covers: architecture.execution_pipeline.public_turn_materialization_preserves_execution_authority
  # covers: architecture.policy_layers.public_turn_materialization_preserves_layered_policy
  # covers: architecture.run_governance.coding_turn_runtime_outputs_materialize_as_evidence
  # covers: architecture.run_governance.evidence_records_capture_run_outputs
  # covers: architecture.run_governance.change_request_records_reviewable_run_state
  use JidoCode.DataCase, async: false

  alias JidoCode.CodeServer
  alias JidoCode.Control.Actor
  alias JidoCode.Governance.Evidence
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.{Run, WorkflowRun}
  alias JidoCode.Projects.Project
  alias JidoCode.TestSupport.CodeServer.EngineFake
  alias JidoCode.TestSupport.Conversations.TurnBridgeRuntimeFake

  @managed_env_keys [
    :code_server_runtime_module,
    :code_server_engine_module,
    :conversation_turn_bridge_poll_interval_ms,
    :conversation_turn_bridge_max_idle_polls,
    :conversation_turn_bridge_live_receive_timeout_ms,
    :conversation_turn_bridge_supervisor,
    :jido_os_instance_id
  ]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    supervisor_name = :"phase-seven-turn-bridge-#{System.unique_integer([:positive, :monotonic])}"
    start_supervised!({Task.Supervisor, name: supervisor_name})

    Application.put_env(:jido_code, :code_server_runtime_module, TurnBridgeRuntimeFake)
    Application.put_env(:jido_code, :code_server_engine_module, EngineFake)
    Application.put_env(:jido_code, :conversation_turn_bridge_poll_interval_ms, 1)
    Application.put_env(:jido_code, :conversation_turn_bridge_max_idle_polls, 2)
    Application.put_env(:jido_code, :conversation_turn_bridge_live_receive_timeout_ms, 5)
    Application.put_env(:jido_code, :conversation_turn_bridge_supervisor, supervisor_name)

    Application.put_env(
      :jido_code,
      :jido_os_instance_id,
      "phase-seven-integration-#{System.unique_integer([:positive, :monotonic])}"
    )

    EngineFake.clear()
    TurnBridgeRuntimeFake.clear()
    TurnBridgeRuntimeFake.set_owner(self())
    EngineFake.put_default_whereis_response({:ok, self()})

    on_exit(fn ->
      EngineFake.clear()
      TurnBridgeRuntimeFake.clear()

      Enum.each(original_env, fn {key, value} ->
        restore_env(:jido_code, key, value)
      end)
    end)

    :ok
  end

  test "conversation turns replay live updates and materialize governed run evidence" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-seven-events", workspace_path)

    configure_runtime_start(project.id)

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-phase-seven", email: "phase-seven@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Plan a replay bridge that also records governed evidence.",
               actor: %{id: "operator-phase-seven", email: "phase-seven@example.com"}
             )

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "user.message"}}

    assert_receive {:conversation_event, ^conversation_id, admitted_event}
    assert admitted_event["type"] == "assistant.delta"

    assert_receive {:conversation_delta, ^conversation_id, _admitted_delta}

    assert_receive {:conversation_event, ^conversation_id, progress_event}
    assert progress_event["type"] == "assistant.delta"

    assert_receive {:conversation_delta, ^conversation_id, _progress_delta}

    assert_receive {:conversation_event, ^conversation_id, final_event}
    assert final_event["type"] == "assistant.message"
    assert get_in(final_event, ["data", "content"]) =~ "Plan"

    turn_id = get_in(final_event, ["meta", "turn_id"])
    assert is_binary(turn_id)

    work_item = wait_for_latest_work_item_with_turn(turn_id)
    assert work_item.work_metadata["public_turn"]["turn_id"] == turn_id
    assert work_item.work_metadata["public_turn"]["conversation_id"] == conversation_id

    workflow_run =
      wait_for_workflow_run(project.id, "turn:#{turn_id}", fn workflow_run ->
        workflow_run.status == :completed
      end)

    assert workflow_run.status == :completed
    assert workflow_run.step_results["coding_turn_summary"]["turn_id"] == turn_id

    {:ok, run} = Run.get_by_workflow_run_id(workflow_run.id, actor: Actor.operator_actor())
    assert run.run_metadata["public_turn"]["turn_id"] == turn_id
    assert run.run_metadata["public_turn"]["conversation_id"] == conversation_id

    {:ok, evidence_records} =
      Evidence.read(query: [filter: [run_id: run.id], sort: [key: :asc]], actor: Actor.operator_actor())

    assert Enum.map(evidence_records, & &1.key) == [
             "coding_turn_review",
             "coding_turn_summary",
             "runtime_service_delivery"
           ]
  end

  defp configure_runtime_start(project_id) do
    EngineFake.clear()
    TurnBridgeRuntimeFake.clear()
    TurnBridgeRuntimeFake.set_owner(self())
    EngineFake.put_default_whereis_response({:ok, self()})

    EngineFake.put_whereis_responses(project_id, [
      {:error, {:project_not_found, project_id}},
      {:ok, self()}
    ])
  end

  defp create_ready_project(name, workspace_path) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
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
  end

  defp latest_work_item do
    {:ok, [work_item]} =
      WorkItem.read(
        query: [sort: [updated_at: :desc], limit: 1],
        actor: Actor.operator_actor()
      )

    work_item
  end

  defp wait_for_latest_work_item_with_turn(turn_id, attempts_left \\ 20)

  defp wait_for_latest_work_item_with_turn(_turn_id, 0), do: latest_work_item()

  defp wait_for_latest_work_item_with_turn(turn_id, attempts_left) do
    work_item = latest_work_item()

    if get_in(work_item.work_metadata, ["public_turn", "turn_id"]) == turn_id do
      work_item
    else
      Process.sleep(25)
      wait_for_latest_work_item_with_turn(turn_id, attempts_left - 1)
    end
  end

  defp wait_for_workflow_run(project_id, run_id, fun, attempts_left \\ 20)

  defp wait_for_workflow_run(project_id, run_id, _fun, 0) do
    case WorkflowRun.get_by_project_and_run_id(
           %{project_id: project_id, run_id: run_id},
           actor: Actor.operator_actor()
         ) do
      {:ok, workflow_run} ->
        workflow_run

      {:error, reason} ->
        raise "expected workflow run #{run_id} for project #{project_id}, got: #{inspect(reason)}"
    end
  end

  defp wait_for_workflow_run(project_id, run_id, fun, attempts_left) do
    case WorkflowRun.get_by_project_and_run_id(
           %{project_id: project_id, run_id: run_id},
           actor: Actor.operator_actor()
         ) do
      {:ok, workflow_run} ->
        if fun.(workflow_run) do
          workflow_run
        else
          Process.sleep(25)
          wait_for_workflow_run(project_id, run_id, fun, attempts_left - 1)
        end

      {:error, _reason} ->
        Process.sleep(25)
        wait_for_workflow_run(project_id, run_id, fun, attempts_left - 1)
    end
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-seven-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp restore_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
