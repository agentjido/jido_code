defmodule JidoCodeWeb.PhaseTwentyFiveIntegrationTest do
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.factory_control_plane.semantic_repository_insights_rejoin_control_plane
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  # covers: architecture.frontend_stack.product_owned_mounting_boundary
  # covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: setup.onboarding.post_bootstrap_surfaces_adopt_control_plane_language
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project

  setup do
    original_source_code_graph_enabled =
      Application.get_env(:jido_code, :source_code_graph_enabled, false)

    original_frontend_override =
      Application.get_env(:jido_code, :frontend_assets_override, :__missing__)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, original_source_code_graph_enabled)
      restore_env(:frontend_assets_override, original_frontend_override)
    end)

    :ok
  end

  test "25.3.1 managed-repository semantic inspection stays repo-scoped across repo detail and workbench", %{
    conn: _conn
  } do
    register_owner("phase25-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase25-owner@example.com", "owner-password-123")

    workspace_path = create_semantic_workspace_path!("PhaseTwentyFive.Semantic")

    {:ok, project} =
      Project.create(%{
        name: "phase-25-semantic-repo",
        github_full_name: "owner/phase-25-semantic-repo",
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

    managed_repo_id = managed_repo_route_id!(project.id)

    assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

    rewrite_semantic_workspace_module!(workspace_path, "PhaseTwentyFive.SemanticRefreshed")

    {:ok, repo_view, repo_html} =
      live(recycle(authed_conn), ~p"/repos/#{managed_repo_id}", on_error: :warn)

    assert has_element?(repo_view, "#project-detail-semantic-notice")
    assert has_element?(repo_view, "#project-detail-semantic-notice-type", "source_code_graph_stale")
    assert has_element?(repo_view, "#project-detail-semantic-recover", "Refresh semantic graph")
    assert has_element?(repo_view, "#project-detail-managed-repo-id", managed_repo_id)
    refute repo_html =~ "SELECT ?"
    refute repo_html =~ "TripleStore"
    refute repo_html =~ "pod_id"

    semantic_vue =
      assert_vue_component(
        repo_view,
        "ProjectDetailSemanticExplorerWidget",
        id: "project-detail-semantic-explorer-widget"
      )

    assert semantic_vue.props["managedRepoId"] == managed_repo_id
    assert semantic_vue.props["graph"]["state"] == "stale"

    {:ok, workbench_view, _workbench_html} =
      live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             workbench_view,
             "#workbench-project-semantic-hint-badge-#{managed_repo_id}",
             "Semantic graph stale"
           )

    assert has_element?(
             workbench_view,
             "#workbench-project-semantic-hint-recovery-#{managed_repo_id}[href='/repos/#{managed_repo_id}']",
             "Open repo detail to refresh semantic graph data."
           )
  end

  test "25.3.2 hybrid semantic explorer regions fall back safely when richer delivery degrades", %{
    conn: _conn
  } do
    register_owner("phase25-fallback-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase25-fallback-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    workspace_path = create_semantic_workspace_path!("PhaseTwentyFive.Fallback")

    {:ok, project} =
      Project.create(%{
        name: "phase-25-fallback-repo",
        github_full_name: "owner/phase-25-fallback-repo",
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

    managed_repo_id = managed_repo_route_id!(project.id)

    assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

    {:ok, view, html} = live(recycle(authed_conn), ~p"/repos/#{managed_repo_id}", on_error: :warn)

    assert has_element?(
             view,
             "#project-detail-semantic-explorer-widget-fallback",
             "Interactive semantic explorer temporarily unavailable"
           )

    assert has_element?(
             view,
             "#project-detail-semantic-explorer-widget-fallback",
             "server-rendered semantic summary"
           )

    assert has_element?(view, "#project-detail-semantic-fallback")
    assert has_element?(view, "#project-detail-semantic-fallback-modules")
    refute html =~ "SELECT ?module"
    refute html =~ "TripleStore"
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "25.3.2 docs and specs remain aligned with semantic operator adoption" do
    phase_plan = repo_file!(".planning/phase-25-semantic-operator-surface-adoption.md")
    source_graph_spec = repo_file!(".spec/specs/source_code_graph_product_adoption.spec.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")

    assert phase_plan =~ "[x] 25 Phase 25 - Semantic Operator Surface Adoption"
    assert phase_plan =~ "[x] 25.3 Section - Phase 25 Integration Tests"
    assert source_graph_spec =~ "lib/jido_code/workbench/project_semantic_inspection.ex"
    assert source_graph_spec =~ "test/jido_code_web/live/phase_twenty_five_integration_test.exs"
    assert frontend_spec =~ "architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions"
    assert frontend_spec =~ "test/jido_code_web/live/phase_twenty_five_integration_test.exs"
  end

  defp create_semantic_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_five_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyFive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_five, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_semantic_workspace_module!(workspace_path, module_name)

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_semantic_workspace_module!(workspace_path, module_name) do
    module_basename =
      module_name
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    File.write!(
      Path.join(workspace_path, "lib/#{module_basename}.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
    |> Path.join("lib/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "#{module_basename}.ex"))
    |> Enum.each(&File.rm!/1)
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
