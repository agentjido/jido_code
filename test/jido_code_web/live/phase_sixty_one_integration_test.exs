defmodule JidoCodeWeb.PhaseSixtyOneIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.operator_surfaces_project_conversation_linkage_through_canonical_records
  # covers: architecture.factory_control_plane.operator_surfaces_distinguish_repo_intake_from_work_item_conversations
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.route_level_runtime_readiness_and_continuity_are_operator_readable
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.conversation_routes_keep_runtime_and_recovery_liveview_owned
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project

  test "61.6.1 repo detail keeps route-owned families on one canonical managed-repository route", %{
    conn: _conn
  } do
    register_owner("phase61-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase61-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "phase-61-repo-detail",
        github_full_name: "owner/phase-61-repo-detail",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          },
          "execution" => %{
            "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
          }
        }
      })

    managed_repo_id = managed_repo_route_id!(project.id)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-section-nav-overview[aria-current='page']")
    assert has_element?(view, "#project-detail-overview-panel")
    refute has_element?(view, "#project-detail-conversation-panel")

    view
    |> element("#project-detail-overview-open-conversations")
    |> render_click()

    assert_patch(view, ~p"/repos/#{managed_repo_id}?section=conversations")
    assert has_element?(view, "#project-detail-section-nav-conversations[aria-current='page']")
    assert has_element?(view, "#project-detail-conversation-panel")
    assert has_element?(view, "#project-detail-conversation-workspace-summary")
    assert has_element?(view, "#project-detail-conversation-runtime-status", "Ready")
    refute has_element?(view, "#project-detail-overview-panel")

    view
    |> element("#project-detail-section-nav-semantic")
    |> render_click()

    assert_patch(view, ~p"/repos/#{managed_repo_id}?section=semantic")
    assert has_element?(view, "#project-detail-semantic-inspection")
    refute has_element?(view, "#project-detail-conversation-panel")

    view
    |> element("#project-detail-semantic-open-memory")
    |> render_click()

    assert_patch(view, ~p"/repos/#{managed_repo_id}?section=memory")
    assert has_element?(view, "#project-detail-memory-inspection")
    refute has_element?(view, "#project-detail-semantic-inspection")

    view
    |> element("#project-detail-memory-open-semantic")
    |> render_click()

    assert_patch(view, ~p"/repos/#{managed_repo_id}?section=semantic")
    assert has_element?(view, "#project-detail-semantic-inspection")

    view
    |> element("#project-detail-section-nav-workflows")
    |> render_click()

    assert_patch(view, ~p"/repos/#{managed_repo_id}?section=workflows")
    assert has_element?(view, "#project-detail-workflows-panel")
    assert has_element?(view, "#project-detail-workflow-readiness-summary")
    refute has_element?(view, "#project-detail-memory-inspection")
  end

  test "61.6.2 phase 61 plan, specs, and browser coverage remain aligned" do
    phase_plan =
      repo_file!(".spec/planning/phase-61-managed-repo-detail-sidebar-information-architecture.md")

    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")
    memory_spec = repo_file!(".spec/specs/memory_graph_product_adoption.spec.md")
    source_spec = repo_file!(".spec/specs/source_code_graph_product_adoption.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    conversation_browser = repo_file!("test/e2e/conversation-ui.spec.ts")

    assert phase_plan =~ "[x] 61 Phase 61 - Managed Repo Detail Sidebar Information Architecture"
    assert phase_plan =~ "[x] 61.1 Section - Canonical Tab Families And Route Ownership"
    assert phase_plan =~ "[x] 61.2 Section - Sidebar Shell And Shared Navigation Language"
    assert phase_plan =~ "[x] 61.3 Section - Overview And Workflow Separation"
    assert phase_plan =~ "[x] 61.4 Section - Conversation And Knowledge Surface Compartmentalization"
    assert phase_plan =~ "[x] 61.5 Section - Current-Truth And Helper Convergence"
    assert phase_plan =~ "[x] 61.6 Section - Phase Integration Tests"

    assert factory_spec =~ "route-owned families"
    assert factory_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert conversation_spec =~ "route-owned `Conversations` family"
    assert conversation_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert frontend_spec =~ "route-selected overview, conversations, semantic, memory, and workflows families"
    assert frontend_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert memory_spec =~ "route-owned `Memory` family"
    assert memory_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert source_spec =~ "route-owned `Semantic` family"
    assert source_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert package_spec =~ ".spec/planning/phase-61-managed-repo-detail-sidebar-information-architecture.md"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_one_integration_test.exs"

    assert conversation_browser =~
             "repo detail keeps desktop sidebar family navigation on the left while panels switch in place"

    assert conversation_browser =~
             "repo detail keeps narrow-screen family navigation usable as a horizontal fallback rail"
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_sixty_one_live_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp managed_repo_route_id!(legacy_project_id) do
    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    managed_repo.id
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
