defmodule JidoCode.Conversations.PhaseFourIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.conversation_driver.code_server_routes_through_boundary
  # covers: architecture.conversation_driver.conversation_identity_maps_to_session
  # covers: architecture.conversation_driver.actor_context_propagated
  # covers: architecture.conversation_driver.subscriber_event_contract_preserved
  # covers: architecture.conversation_driver.public_jido_os_turn_event_bridge
  # covers: architecture.conversation_driver.conversation_is_ingress_and_steering_surface
  # covers: architecture.policy_layers.repository_governance_policy_is_repo_control_layer
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  use JidoCode.DataCase, async: false

  alias JidoCode.CodeServer
  alias JidoCode.CodingAssistance
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.PolicySet
  alias JidoCode.Operations.{Assessment, Event, Intake, WorkItem}
  alias JidoCode.Projects.Project
  alias JidoCode.TestSupport.CodeServer.EngineFake
  alias JidoCode.TestSupport.CodeServer.RuntimeFake

  @managed_env_keys [
    :code_server_runtime_module,
    :code_server_engine_module,
    :jido_os_instance_id
  ]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    Application.put_env(:jido_code, :code_server_runtime_module, RuntimeFake)
    Application.put_env(:jido_code, :code_server_engine_module, EngineFake)

    Application.put_env(
      :jido_code,
      :jido_os_instance_id,
      "phase-four-integration-#{System.unique_integer([:positive, :monotonic])}"
    )

    EngineFake.clear()
    RuntimeFake.clear()
    EngineFake.put_default_whereis_response({:ok, self()})

    on_exit(fn ->
      EngineFake.clear()
      RuntimeFake.clear()

      Enum.each(original_env, fn {key, value} ->
        restore_env(:jido_code, key, value)
      end)
    end)

    :ok
  end

  test "conversation turns create durable work records and preserve subscriber event compatibility" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-four-events", workspace_path)

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    configure_runtime_start(project.id)

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-phase-four", email: "phase-four@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Plan a safe fix for the governed conversation runtime bridge.",
               actor: %{id: "operator-phase-four", email: "phase-four@example.com"}
             )

    assert_receive {:conversation_event, ^conversation_id,
                    %{"type" => "user.message", "data" => %{"content" => content}}}

    assert content =~ "Plan a safe fix"

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "assistant.delta"}}

    assert_receive {:conversation_event, ^conversation_id,
                    %{"type" => "assistant.message", "data" => %{"content" => assistant_content}}}

    assert assistant_content =~ "Captured request for work item"

    assert {:ok, [intake]} =
             Intake.read(
               query: [
                 filter: [managed_repo_id: managed_repo.id, channel: "conversation"],
                 sort: [inserted_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert {:ok, [event]} =
             Event.read(
               query: [filter: [intake_id: intake.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [assessment]} =
             Assessment.read(
               query: [filter: [event_id: event.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert {:ok, [work_item]} =
             WorkItem.read(
               query: [filter: [assessment_id: assessment.id], limit: 1],
               actor: Actor.operator_actor()
             )

    assert intake.source_metadata["conversation_id"] == conversation_id
    assert event.category == "operator.conversation.coding_turn_request.requested"
    assert assessment.category == "conversation_work_request"
    assert work_item.managed_repo_id == managed_repo.id
    assert work_item.work_metadata["conversation_context"]["conversation_id"] == conversation_id

    assert {:ok, session} =
             CodingAssistance.lookup_session(conversation_id, "operator-phase-four", %{
               project_id: managed_repo.id,
               workspace_id: workspace_path
             })

    assert session.project_id == managed_repo.id
    refute Map.has_key?(session, :work_item_id)
    refute Map.has_key?(session, :evidence_ids)
  end

  test "repo governance can steer existing work while runtime session stays separate from product truth" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-four-steering", workspace_path)

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, _policy_set} =
             PolicySet.upsert_default_for_managed_repo(
               %{
                 managed_repo_id: managed_repo.id,
                 review_policy: %{
                   mode: "auto_post",
                   requires_human_approval: false,
                   change_request_required: false,
                   review_threshold: "auto_post",
                   required_stage: "approval",
                   source: "phase_four_integration_override"
                 }
               },
               actor: Actor.admin_actor()
             )

    configure_runtime_start(project.id)

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-steering", email: "steering@example.com"}
             )

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Open new work for the repository.",
               actor: %{id: "operator-steering", email: "steering@example.com"}
             )

    first_work_item = latest_work_item(managed_repo.id)

    assert :ok =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Continue the existing work with more detail on runtime diagnostics.",
               actor: %{id: "operator-steering", email: "steering@example.com"}
             )

    second_work_item = latest_work_item(managed_repo.id)

    assert first_work_item.id == second_work_item.id

    assert {:ok, intakes} =
             Intake.read(
               query: [filter: [managed_repo_id: managed_repo.id, channel: "conversation"], sort: [inserted_at: :asc]],
               actor: Actor.operator_actor()
             )

    assert length(intakes) == 2
    assert Enum.at(intakes, 1).source_metadata["policy_action"] == "steer_existing_work"
    assert Enum.at(intakes, 1).payload["work_item_id"] == first_work_item.id

    assert {:ok, session} =
             CodingAssistance.lookup_session(conversation_id, "operator-steering", %{
               project_id: managed_repo.id,
               workspace_id: workspace_path
             })

    assert session.project_id == managed_repo.id
    refute Map.has_key?(session, :intake_id)
    refute Map.has_key?(session, :work_metadata)
  end

  test "policy halts targeted turns before new durable ingress is created and emits failure compatibility events" do
    workspace_path = create_workspace_path!()
    {:ok, project} = create_ready_project("repo-phase-four-halt", workspace_path)

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    configure_runtime_start(project.id)

    assert {:ok, conversation_id} =
             CodeServer.start_conversation(project.id,
               actor: %{id: "operator-halt", email: "halt@example.com"}
             )

    before_count = count_conversation_intakes(managed_repo.id)

    assert {:error, typed_error} =
             CodeServer.send_user_message(
               project.id,
               conversation_id,
               "Continue the missing work item.",
               actor: %{id: "operator-halt", email: "halt@example.com"},
               work_item_id: Ecto.UUID.generate()
             )

    assert typed_error.error_type == "code_server_message_send_failed"
    assert typed_error.detail =~ "target_work_item_not_found"

    assert_receive {:conversation_event, ^conversation_id, %{"type" => "user.message"}}
    assert_receive {:conversation_event, ^conversation_id, %{"type" => "llm.failed", "data" => %{"detail" => detail}}}
    assert detail =~ "target_work_item_not_found"

    assert count_conversation_intakes(managed_repo.id) == before_count
  end

  defp configure_runtime_start(project_id) do
    EngineFake.clear()
    RuntimeFake.clear()
    EngineFake.put_default_whereis_response({:ok, self()})

    EngineFake.put_whereis_responses(project_id, [
      {:error, {:project_not_found, project_id}},
      {:ok, self()}
    ])

    RuntimeFake.put_result(:start_conversation, fn [_project_id, opts] ->
      {:ok, Keyword.fetch!(opts, :conversation_id)}
    end)
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

  defp latest_work_item(managed_repo_id) do
    {:ok, [work_item]} =
      WorkItem.read(
        query: [filter: [managed_repo_id: managed_repo_id], sort: [updated_at: :desc], limit: 1],
        actor: Actor.operator_actor()
      )

    work_item
  end

  defp count_conversation_intakes(managed_repo_id) do
    {:ok, intakes} =
      Intake.read(
        query: [filter: [managed_repo_id: managed_repo_id, channel: "conversation"]],
        actor: Actor.operator_actor()
      )

    length(intakes)
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-four-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp restore_env(app, key, :__missing__), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
