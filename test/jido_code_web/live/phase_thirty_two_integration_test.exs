defmodule JidoCodeWeb.PhaseThirtyTwoIntegrationTest do
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.frontend_stack.semantic_operator_surfaces_can_use_bounded_hybrid_regions
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.Projects.Project

  setup do
    original_memory_graph_enabled =
      Application.get_env(:jido_code, :memory_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, original_memory_graph_enabled)
    end)

    :ok
  end

  test "32.4.1.2 repo detail memory surfaces stay legible under ready and invalidated states", %{
    conn: _conn
  } do
    register_owner("phase32-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase32-owner@example.com", "owner-password-123")

    ready_workspace = create_workspace_path!("ExamplePhaseThirtyTwo.Ready")
    invalidated_workspace = create_workspace_path!("ExamplePhaseThirtyTwo.Invalidated")

    {:ok, ready_project} =
      Project.create(%{
        name: "phase-32-ready-repo",
        github_full_name: "owner/phase-32-ready-repo",
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

    {:ok, invalidated_project} =
      Project.create(%{
        name: "phase-32-invalidated-repo",
        github_full_name: "owner/phase-32-invalidated-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => invalidated_workspace,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    ready_repo_id = managed_repo_route_id!(ready_project.id)
    invalidated_repo_id = managed_repo_route_id!(invalidated_project.id)

    seed_memory_graph!(ready_repo_id, ready_workspace, "rev-32-ready-ui")
    seed_memory_graph!(invalidated_repo_id, invalidated_workspace, "rev-32-invalidated-ui")

    assert {:ok, _invalidate_result} =
             AgentWorkspace.invalidate_memory_graph(
               invalidated_repo_id,
               invalidated_workspace,
               reason: :manual_invalidation
             )

    {:ok, ready_view, _ready_html} =
      live(recycle(authed_conn), ~p"/repos/#{ready_project.id}", on_error: :warn)

    assert has_element?(ready_view, "#project-detail-memory-inspection")
    assert has_element?(ready_view, "#project-detail-memory-summary-memories")
    assert has_element?(ready_view, "#project-detail-memory-summary-provenance")
    assert has_element?(ready_view, "#project-detail-memory-list")

    {:ok, invalidated_view, _invalidated_html} =
      live(recycle(authed_conn), ~p"/repos/#{invalidated_project.id}", on_error: :warn)

    assert has_element?(invalidated_view, "#project-detail-memory-notice")
    assert has_element?(invalidated_view, "#project-detail-memory-recover", "Validate memory graph")

    invalidated_view
    |> element("#project-detail-memory-recover")
    |> render_click()

    assert has_element?(invalidated_view, "#project-detail-memory-feedback-type", "memory_graph_recovered")
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_thirty_two_live_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyTwoLive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_two_live, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_two_live.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase-32-live-#{System.unique_integer([:positive])}"

    assert {:ok, _provenance_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-two-live",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Generated a review artifact for phase thirty-two live tests.",
                 anchors: %{module_name: "ExamplePhaseThirtyTwoLive"}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 id: "known-issue-run",
                 session_id: session_id,
                 actor_id: "system:phase-thirty-two-live",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Greeting contract changes require governed review.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyTwoLive"},
                 governed_context: %{run_id: "run-32", work_item_id: "work-32"},
                 classification: %{
                   source: "phase_thirty_two_live",
                   reason: "Phase 32 live integration needs durable repository memory."
                 }
               ),
               revision: revision
             )
  end

  defp managed_repo_route_id!(legacy_project_id) do
    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    managed_repo.id
  end
end
