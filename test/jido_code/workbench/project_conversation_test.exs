defmodule JidoCode.Workbench.ProjectConversationTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Operations.Ingress
  alias JidoCode.Workbench.ProjectConversation

  setup do
    setup_product_store()
  end

  test "managed-repo projection keeps repo intake separate from productive work-item conversations" do
    managed_repo = managed_repo_fixture!("repo-intake-separation")

    on_exit(fn ->
      case AgentWorkspace.active_repo_intake_conversation(managed_repo.id, actor: Actor.operator_actor()) do
        {:ok, %{id: conversation_id}} -> _ = AgentWorkspace.stop_conversation(conversation_id)
        _other -> :ok
      end

      case AgentWorkspace.active_work_item_conversations(managed_repo.id, actor: Actor.operator_actor()) do
        {:ok, conversations} ->
          Enum.each(conversations, fn conversation ->
            _ = AgentWorkspace.stop_conversation(conversation.id)
          end)

        _other ->
          :ok
      end
    end)

    assert {:ok, %{conversation: intake_conversation}} =
             ProjectConversation.open_repo_detail(
               %{managed_repo_id: managed_repo.id},
               actor: Actor.operator_actor(%{"id" => "operator-project-conversation-intake"})
             )

    work_item = work_item_fixture!(managed_repo, "operator-project-conversation-work-item")

    assert {:ok, %{conversation: productive_conversation}} =
             AgentWorkspace.open_work_item_conversation(
               work_item.id,
               %{
                 source: "project_conversation_test",
                 objective: "Continue governed work through the work-item conversation path."
               },
               actor: Actor.operator_actor(%{"id" => "operator-project-conversation-productive"})
             )

    projection = ProjectConversation.load_managed_repo(managed_repo.id, actor: Actor.operator_actor())

    assert projection.conversation.id == intake_conversation.id
    assert projection.conversation.scope == :repo_scoped
    assert projection.conversation.attachment_mode == :pre_work
    refute projection.conversation.id == productive_conversation.id
    assert projection.work_item == nil
  end

  test "active work-item roster projects governed conversations without folding them back into repo intake" do
    managed_repo = managed_repo_fixture!("governed-roster")

    on_exit(fn ->
      case AgentWorkspace.active_repo_intake_conversation(managed_repo.id, actor: Actor.operator_actor()) do
        {:ok, %{id: conversation_id}} -> _ = AgentWorkspace.stop_conversation(conversation_id)
        _other -> :ok
      end

      case AgentWorkspace.active_work_item_conversations(managed_repo.id, actor: Actor.operator_actor()) do
        {:ok, conversations} ->
          Enum.each(conversations, fn conversation ->
            _ = AgentWorkspace.stop_conversation(conversation.id)
          end)

        _other ->
          :ok
      end
    end)

    assert {:ok, %{conversation: intake_conversation}} =
             ProjectConversation.open_repo_detail(
               %{managed_repo_id: managed_repo.id},
               actor: Actor.operator_actor(%{"id" => "operator-project-conversation-roster-intake"})
             )

    first_work_item = work_item_fixture!(managed_repo, "operator-project-conversation-roster-first")
    second_work_item = work_item_fixture!(managed_repo, "operator-project-conversation-roster-second")

    assert {:ok, %{conversation: first_conversation}} =
             AgentWorkspace.open_work_item_conversation(
               first_work_item.id,
               %{
                 source: "project_conversation_test",
                 objective: "Continue the first governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-project-conversation-roster-first"})
             )

    assert {:ok, %{conversation: second_conversation}} =
             AgentWorkspace.open_work_item_conversation(
               second_work_item.id,
               %{
                 source: "project_conversation_test",
                 objective: "Continue the second governed work item."
               },
               actor: Actor.operator_actor(%{"id" => "operator-project-conversation-roster-second"})
             )

    roster = ProjectConversation.load_active_work_item_roster(managed_repo.id, actor: Actor.operator_actor())

    assert roster.notice == nil
    assert roster.managed_repo_id == managed_repo.id
    assert length(roster.entries) == 2

    active_ids =
      roster.entries
      |> Enum.map(& &1.conversation.id)
      |> Enum.sort()

    assert active_ids == Enum.sort([first_conversation.id, second_conversation.id])
    refute Enum.member?(active_ids, intake_conversation.id)

    assert Enum.any?(roster.entries, fn entry ->
             entry.work_item.id == first_work_item.id and
               entry.conversation.scope == :work_item_scoped and
               entry.action_label == "Resume governed conversation"
           end)

    assert Enum.any?(roster.entries, fn entry ->
             entry.work_item.id == second_work_item.id and
               entry.conversation.scope == :work_item_scoped and
               entry.action_label == "Resume governed conversation"
           end)
  end

  defp managed_repo_fixture!(suffix) do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "project-conversation-#{suffix}",
        full_name: "owner/project-conversation-#{suffix}",
        default_branch: "main",
        settings: %{}
      })

    managed_repo
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

  defp setup_product_store do
    store_name = :"project_conversation_test_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_project_conversation_test_store/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
