defmodule JidoCodeWeb.PhaseTwentySevenIntegrationTest do
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project

  setup do
    original_source_code_graph_enabled =
      Application.get_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, original_source_code_graph_enabled)
    end)

    :ok
  end

  test "27.3.1.1 semantic operator surfaces stay legible under mixed stale and ready repository states", %{
    conn: _conn
  } do
    register_owner("phase27-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase27-owner@example.com", "owner-password-123")

    stale_workspace = create_semantic_workspace_path!("PhaseTwentySeven.Stale")
    ready_workspace = create_semantic_workspace_path!("PhaseTwentySeven.Ready")

    {:ok, stale_project} =
      Project.create(%{
        name: "phase-27-stale-repo",
        github_full_name: "owner/phase-27-stale-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => stale_workspace,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, ready_project} =
      Project.create(%{
        name: "phase-27-ready-repo",
        github_full_name: "owner/phase-27-ready-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => ready_workspace,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    stale_repo_id = managed_repo_route_id!(stale_project.id)
    ready_repo_id = managed_repo_route_id!(ready_project.id)

    assert {:ok, _load_stale} =
             AgentWorkspace.load_source_code_graph(stale_repo_id, stale_workspace)

    assert {:ok, _load_ready} =
             AgentWorkspace.load_source_code_graph(ready_repo_id, ready_workspace)

    rewrite_semantic_workspace_module!(stale_workspace, "PhaseTwentySeven.StaleRenamed")

    {:ok, stale_view, _stale_html} =
      live(recycle(authed_conn), ~p"/repos/#{stale_repo_id}", on_error: :warn)

    assert has_element?(stale_view, "#project-detail-semantic-notice")
    assert has_element?(stale_view, "#project-detail-semantic-notice-type", "source_code_graph_stale")
    assert has_element?(stale_view, "#project-detail-semantic-recover", "Refresh semantic graph")

    {:ok, ready_view, _ready_html} =
      live(recycle(authed_conn), ~p"/repos/#{ready_repo_id}", on_error: :warn)

    refute has_element?(ready_view, "#project-detail-semantic-notice")

    ready_semantic_vue =
      assert_vue_component(
        ready_view,
        "ProjectDetailSemanticExplorerWidget",
        id: "project-detail-semantic-explorer-widget"
      )

    assert ready_semantic_vue.props["graph"]["state"] == "ready"

    {:ok, workbench_view, _workbench_html} =
      live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(
             workbench_view,
             "#workbench-project-semantic-hint-badge-#{stale_repo_id}",
             "Semantic graph stale"
           )

    assert has_element?(
             workbench_view,
             "#workbench-project-semantic-hint-badge-#{ready_repo_id}",
             "Semantic graph ready"
           )
  end

  defp create_semantic_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_seven_live_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentySeven.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_seven, version: "0.1.0", elixir: "~> 1.18", deps: []]
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
end
