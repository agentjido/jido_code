defmodule JidoCode.Conversations.DriverTest do
  # covers: architecture.conversation_driver.code_server_routes_through_boundary
  # covers: architecture.conversation_driver.conversation_identity_maps_to_session
  # covers: architecture.conversation_driver.actor_context_propagated
  # covers: architecture.conversation_driver.subscriber_event_contract_preserved
  # covers: architecture.conversation_driver.public_jido_os_turn_event_bridge
  use JidoCode.DataCase, async: false

  alias JidoCode.CodingAssistance
  alias JidoCode.Conversations.Driver
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project

  setup do
    instance_id = "jido-code-conversation-driver-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
    end)

    :ok
  end

  test "prepare_conversation and handle_turn use conversation identity as coding-assistance session identity" do
    {:ok, project} = create_project("repo-conversation-driver")

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, context} =
             Driver.prepare_conversation(%{
               project_id: project.id,
               conversation_id: "conversation-driver-1",
               actor_id: "operator-driver",
               actor_email: "driver@example.com",
               workspace_id: "/tmp/repo-conversation-driver"
             })

    assert context.session_id == "conversation-driver-1"
    assert context.managed_repo_id == managed_repo.id

    assert {:ok, session} =
             CodingAssistance.lookup_session(context.session_id, context.actor_id, %{
               project_id: managed_repo.id,
               workspace_id: context.workspace_id
             })

    assert session.session_id == "conversation-driver-1"
    assert session.project_id == managed_repo.id

    assert {:ok, result} =
             Driver.handle_turn(%{
               project_id: project.id,
               conversation_id: "conversation-driver-1",
               actor_id: "operator-driver",
               actor_email: "driver@example.com",
               workspace_id: "/tmp/repo-conversation-driver",
               content: "Plan a safe refactor of the conversation runtime bridge."
             })

    assert result.context.session_id == "conversation-driver-1"
    assert result.ingress.turn_mode == :new_demand
    assert result.ingress.work_item.managed_repo_id == managed_repo.id
    assert result.envelope.context.session_id == "conversation-driver-1"
    assert result.envelope.context.project_id == managed_repo.id
    assert Enum.map(result.events, & &1["type"]) == ["assistant.delta", "assistant.message"]
    assert get_in(List.last(result.events), ["data", "content"]) =~ result.ingress.work_item.id
    assert get_in(List.last(result.events), ["meta", "conversation_id"]) == "conversation-driver-1"
  end

  defp create_project(name) do
    Project.create(%{
      name: name,
      github_full_name: "owner/#{name}",
      default_branch: "main",
      settings: %{}
    })
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
