defmodule JidoCodeWeb.EmbeddedStoreCutoverSmokeTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.control_plane_embedded_triple_store.product_surface_cutover
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.ControlPlane.{ProductStore, StoreServer}
  alias JidoCode.Governance.Evidence
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.RunBridge

  setup do
    original_config = Application.get_env(:jido_code, :system_config, :__missing__)
    original_loader = Application.get_env(:jido_code, :system_config_loader, :__missing__)

    on_exit(fn ->
      restore_env(:system_config, original_config)
      restore_env(:system_config_loader, original_loader)
    end)

    Application.delete_env(:jido_code, :system_config_loader)

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 1,
      onboarding_state: %{},
      default_environment: :sprite,
      workspace_root: nil
    })

    :ok
  end

  test "embedded store supports bootstrap, governed work, run evidence, and conversation replay", %{conn: conn} do
    store_name = ProductStore.store()
    %{path: store_path} = StoreServer.health(store_name)

    auth_response = bootstrap_owner_through_web!(conn)

    {:ok, dashboard_view, _html} =
      live(recycle(auth_response), ~p"/dashboard?onboarding=completed", on_error: :warn)

    assert has_element?(dashboard_view, "#dashboard-entry-summary", "authenticated product home")

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: "owner/embedded-cutover-smoke",
        full_name: "owner/embedded-cutover-smoke",
        default_branch: "main",
        settings: %{}
      })

    {:ok, work_item} =
      WorkItem.create(%{
        managed_repo_id: managed_repo.id,
        category: :implementation,
        status: :open,
        priority: :medium,
        recommended_action: "launch_fix_workflow",
        summary: "Verify the embedded TripleStore product path.",
        dedup_key: "embedded-cutover-smoke",
        initiating_actor: %{"id" => "phase-7-smoke", "actor_class" => "system"}
      })

    assert work_item.managed_repo_id == managed_repo.id

    assert {:ok, %{workflow_run: workflow_run, run: run}} =
             RunBridge.launch_work_item(work_item, %{"workflow_name" => "implement_task"})

    assert run.managed_repo_id == managed_repo.id
    assert run.work_item_id == work_item.id
    assert workflow_run.managed_repo_id == managed_repo.id

    assert {:ok, evidence} =
             Evidence.create(%{
               managed_repo_id: managed_repo.id,
               run_id: run.id,
               work_item_id: work_item.id,
               key: "embedded-cutover-smoke",
               source_key: "embedded-cutover-smoke",
               evidence_type: "smoke_test",
               summary: "Embedded store smoke captured governed run evidence.",
               evidence_details: %{"workflow_run_id" => workflow_run.id}
             })

    assert evidence.run_id == run.id
    assert evidence.work_item_id == work_item.id

    assert {:ok, %{conversation: conversation, snapshot: opened_snapshot}} =
             AgentWorkspace.open_work_item_conversation(
               work_item.id,
               %{title: "Embedded store smoke conversation", objective: "Verify replay after restart."},
               actor: Actor.operator_actor()
             )

    assert conversation.work_item_id == work_item.id
    assert opened_snapshot.work_item_id == work_item.id

    assert {:ok, command_snapshot} =
             AgentWorkspace.handle_conversation_command(
               conversation.id,
               %{
                 type: "turn.submit",
                 payload: %{instruction: "Record one embedded-store replay event."}
               },
               actor: Actor.operator_actor()
             )

    assert Enum.any?(command_snapshot.events, &(&1.name == "conversation.message_added"))

    assert :ok = AgentWorkspace.stop_conversation(conversation.id)
    :ok = stop_supervised!(store_name)

    start_supervised!(
      {StoreServer, name: store_name, id: store_name, path: store_path, reset_policy: :bootstrap_if_empty}
    )

    assert {:ok, replayed_events} =
             AgentWorkspace.conversation_events_since(conversation.id, 0, actor: Actor.operator_actor())

    assert Enum.any?(replayed_events, &(&1.name == "conversation.message_added"))

    assert Enum.any?(
             replayed_events,
             &(get_in(&1.payload, ["payload", "instruction"]) == "Record one embedded-store replay event.")
           )
  end

  defp bootstrap_owner_through_web!(conn) do
    {:ok, welcome_view, _html} = live(conn, ~p"/welcome", on_error: :warn)

    welcome_view
    |> form("#welcome-owner-form", %{
      "owner" => %{
        "email" => "embedded-cutover-owner@example.com",
        "password" => "owner-password-123",
        "password_confirmation" => "owner-password-123"
      }
    })
    |> render_submit()

    auth_redirect_path =
      welcome_view
      |> assert_redirect()
      |> redirect_path()

    auth_response = build_conn() |> get(auth_redirect_path)
    assert redirected_to(auth_response, 302) == "/setup"

    {:ok, setup_view, _html} = live(recycle(auth_response), ~p"/setup", on_error: :warn)

    setup_view
    |> element("#setup-complete-continue")
    |> render_click()

    assert_redirect(setup_view, "/dashboard?onboarding=completed")

    auth_response
  end

  defp redirect_path({path, _flash}) when is_binary(path), do: path
  defp redirect_path(path) when is_binary(path), do: path
end
