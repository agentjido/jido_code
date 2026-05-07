defmodule JidoCodeWeb.PhaseSixtyFourIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.conversation_orchestration.runtime_readiness_uses_managed_repo_workspace_binding
  # covers: architecture.factory_control_plane.managed_repos_own_repo_scoped_workspace_binding
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.ProjectDetail

  @managed_env_keys [:source_code_graph_enabled, :memory_graph_enabled]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    :ok
  end

  test "64.3.1 blocked repo-detail runtime families converge on one repo-scoped repair path", %{
    conn: _conn
  } do
    register_owner("phase64-blocked-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase64-blocked-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "phase-64-blocked-runtime-families",
        github_full_name: "owner/phase-64-blocked-runtime-families",
        default_branch: "main",
        settings: blocked_local_settings()
      })

    _managed_repo_id = managed_repo_route_id!(project.id)

    {:ok, conversation_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}?section=conversations", on_error: :warn)

    assert has_element?(conversation_view, "#project-detail-conversation-runtime-status", "Blocked")

    assert has_element?(
             conversation_view,
             "#project-detail-conversation-runtime-workspace",
             "No repo-scoped local workspace path saved"
           )

    assert has_element?(
             conversation_view,
             "#project-detail-conversation-runtime-repair",
             "Repair workspace binding"
           )

    conversation_view
    |> element("#project-detail-conversation-runtime-repair")
    |> render_click()

    assert has_element?(conversation_view, "#project-detail-overview-panel")
    assert has_element?(conversation_view, "#project-detail-workspace-binding-panel")

    {:ok, semantic_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}?section=semantic", on_error: :warn)

    assert has_element?(
             semantic_view,
             "#project-detail-semantic-notice-type",
             "semantic_workspace_binding_unavailable"
           )

    assert has_element?(
             semantic_view,
             "#project-detail-semantic-repair-workspace",
             "Repair workspace binding"
           )

    {:ok, memory_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}?section=memory", on_error: :warn)

    assert has_element?(
             memory_view,
             "#project-detail-memory-notice-type",
             "memory_workspace_binding_unavailable"
           )

    assert has_element?(
             memory_view,
             "#project-detail-memory-repair-workspace",
             "Repair workspace binding"
           )

    {:ok, workflow_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}?section=workflows", on_error: :warn)

    assert has_element?(workflow_view, "#project-detail-workflow-readiness-badge", "Blocked")

    assert has_element?(
             workflow_view,
             "#project-detail-launch-disabled-repair",
             "Repair workspace binding"
           )
  end

  test "64.3.2 unrelated repo paths stay legible and independently repairable across workbench and repo detail",
       %{conn: _conn} do
    register_owner("phase64-ready-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase64-ready-owner@example.com", "owner-password-123")

    ready_one_path = create_workspace_path!("phase64-ready-one")
    ready_two_path = create_workspace_path!("phase64-ready-two")
    repaired_path = create_workspace_path!("phase64-repaired-target")

    {:ok, ready_one} =
      Project.create(%{
        name: "phase-64-ready-one",
        github_full_name: "owner/phase-64-ready-one",
        default_branch: "main",
        settings: ready_local_settings(ready_one_path)
      })

    {:ok, ready_two} =
      Project.create(%{
        name: "phase-64-ready-two",
        github_full_name: "owner/phase-64-ready-two",
        default_branch: "main",
        settings: ready_local_settings(ready_two_path)
      })

    {:ok, repair_target} =
      Project.create(%{
        name: "phase-64-repair-target",
        github_full_name: "owner/phase-64-repair-target",
        default_branch: "main",
        settings: blocked_local_settings()
      })

    ready_one_route_id = managed_repo_route_id!(ready_one.id)
    ready_two_route_id = managed_repo_route_id!(ready_two.id)
    repair_target_route_id = managed_repo_route_id!(repair_target.id)

    {:ok, ready_one_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{ready_one.id}?section=conversations", on_error: :warn)

    assert has_element?(ready_one_view, "#project-detail-conversation-runtime-status", "Ready")

    assert has_element?(
             ready_one_view,
             "#project-detail-conversation-runtime-workspace",
             ready_one_path
           )

    {:ok, ready_two_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{ready_two.id}?section=conversations", on_error: :warn)

    assert has_element?(ready_two_view, "#project-detail-conversation-runtime-status", "Ready")

    assert has_element?(
             ready_two_view,
             "#project-detail-conversation-runtime-workspace",
             ready_two_path
           )

    {:ok, workbench_view, _html} =
      live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             workbench_view,
             "#workbench-project-semantic-hint-recovery-#{repair_target_route_id}[href='/repos/#{repair_target_route_id}#project-detail-workspace-binding-panel']",
             "Open repo detail to repair workspace binding."
           )

    assert has_element?(
             workbench_view,
             "#workbench-project-memory-hint-recovery-#{repair_target_route_id}[href='/repos/#{repair_target_route_id}#project-detail-workspace-binding-panel']",
             "Open repo detail to repair workspace binding."
           )

    {:ok, repair_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{repair_target.id}?section=conversations", on_error: :warn)

    repair_view
    |> element("#project-detail-conversation-runtime-repair")
    |> render_click()

    repair_view
    |> form("#project-detail-workspace-binding-form", %{
      "workspace_binding" => %{
        "workspace_environment" => "local",
        "workspace_path" => repaired_path
      }
    })
    |> render_submit()

    repair_view
    |> element("#project-detail-overview-open-conversations")
    |> render_click()

    assert has_element?(repair_view, "#project-detail-conversation-runtime-status", "Ready")
    assert has_element?(repair_view, "#project-detail-conversation-runtime-workspace", repaired_path)

    {:ok, ready_one_detail} = ProjectDetail.load(ready_one_route_id)
    {:ok, ready_two_detail} = ProjectDetail.load(ready_two_route_id)
    {:ok, repaired_detail} = ProjectDetail.load(repair_target_route_id)

    assert ProjectDetail.workspace_path(ready_one_detail) == ready_one_path
    assert ProjectDetail.workspace_path(ready_two_detail) == ready_two_path
    assert ProjectDetail.workspace_path(repaired_detail) == repaired_path
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "64.3.3 phase 64 plan, specs, decision, and integration coverage remain aligned" do
    phase_plan =
      repo_file!(".planning/phase-64-runtime-surface-workspace-convergence.md")

    decision =
      repo_file!(".spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md")

    runtime_defaults_spec = repo_file!(".spec/specs/runtime_environment_defaults.spec.md")
    setup_spec = repo_file!(".spec/specs/setup_onboarding.spec.md")
    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")
    source_spec = repo_file!(".spec/specs/source_code_graph_product_adoption.spec.md")
    memory_spec = repo_file!(".spec/specs/memory_graph_product_adoption.spec.md")

    memory_rollout_spec =
      repo_file!(".spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md")

    memory_expansion_spec =
      repo_file!(".spec/specs/memory_graph_workflow_and_operator_expansion.spec.md")

    package_spec = repo_file!(".spec/specs/package.spec.md")

    assert phase_plan =~ "[x] 64 Phase 64 - Runtime Surface Workspace Convergence"
    assert phase_plan =~ "[x] 64.1 Section - Repo-Scoped Runtime And Knowledge Surface Adoption"
    assert phase_plan =~ "[x] 64.2 Section - Current-Truth And Contributor Convergence"
    assert phase_plan =~ "[x] 64.3 Section - Phase Integration Tests"

    assert decision =~ "blocked conversation, semantic, memory, and workflow surfaces now share"

    assert runtime_defaults_spec =~ "conversation, semantic, memory, and workflow readiness plus repo-scoped repair"
    assert runtime_defaults_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert setup_spec =~ "post-import runtime surfaces now keep blocked repo-scoped workspace remediation"
    assert setup_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert factory_spec =~
             "conversation plus semantic plus memory plus workflow readiness now sharing one repo-scoped workspace-binding story"

    assert factory_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert conversation_spec =~
             "same repo-scoped workspace-binding vocabulary as semantic, memory, and workflow surfaces"

    assert conversation_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert frontend_spec =~
             "consistent repo-scoped runtime wording across conversations, semantic, memory, and workflows"

    assert frontend_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert source_spec =~ "blocked semantic states now using the same repo-scoped workspace-binding vocabulary"
    assert source_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert memory_spec =~ "blocked memory states now using the same repo-scoped workspace-binding vocabulary"
    assert memory_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert memory_rollout_spec =~ "same repo-scoped repair vocabulary and route-local repair path"
    assert memory_rollout_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert memory_expansion_spec =~ "same repo-scoped repair vocabulary and route-local repair path"
    assert memory_expansion_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"

    assert package_spec =~ "converged repo-detail runtime wording"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_four_integration_test.exs"
  end

  defp blocked_local_settings do
    %{
      "workspace" => %{
        "workspace_environment" => "local",
        "clone_status" => "ready",
        "workspace_initialized" => true,
        "baseline_synced" => true
      },
      "execution" => %{
        "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
      }
    }
  end

  defp ready_local_settings(workspace_path) when is_binary(workspace_path) do
    %{
      "workspace" => %{
        "workspace_environment" => "local",
        "workspace_path" => workspace_path,
        "clone_status" => "ready",
        "workspace_initialized" => true,
        "baseline_synced" => true
      },
      "execution" => %{
        "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
      }
    }
  end

  defp create_workspace_path!(label) when is_binary(label) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_#{label}_#{System.unique_integer([:positive])}"
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
