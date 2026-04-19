defmodule JidoCodeWeb.PhaseFiftyFourIntegrationTest do
  # covers: architecture.factory_control_plane.internal_repo_loaders_use_canonical_repo_graph
  # covers: architecture.factory_control_plane.operator_surfaces_prefer_control_plane_records
  # covers: architecture.run_governance.greenfield_tests_and_fixtures_create_canonical_run_graph
  # covers: package.jido_code.spec_led_workspace
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.Actor
  alias JidoCode.Orchestration.WorkflowRun

  test "54.5.1 canonical repo and governed-run helpers drive run detail without legacy setup", %{
    conn: _conn
  } do
    register_owner("phase54-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase54-owner@example.com", "owner-password-123")

    %{managed_repo: managed_repo, route_id: route_id} =
      provision_managed_repo!(%{
        name: "repo-phase54-canonical",
        github_full_name: "owner/repo-phase54-canonical",
        default_branch: "main",
        settings: %{}
      })

    run_id = "run-phase54-#{System.unique_integer([:positive])}"

    run =
      create_governed_run!(route_id, %{
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        status: :completed,
        current_step: "publish_pr",
        current_stage: "publish_pr",
        started_at: ~U[2026-04-19 12:00:00Z],
        completed_at: ~U[2026-04-19 12:03:00Z]
      })

    assert run.managed_repo_id == managed_repo.id
    assert run.legacy_project_id == route_id

    assert {:ok, []} =
             WorkflowRun.read(
               query: [filter: [run_id: run_id], limit: 1],
               actor: Actor.operator_actor()
             )

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{route_id}/runs/#{run_id}", on_error: :warn)

    assert has_element?(view, "#run-detail-title", "Run detail")
    assert has_element?(view, "#run-detail-run-id", run_id)
    assert has_element?(view, "#run-detail-status", "completed")
    assert has_element?(view, "#run-detail-current-step", "publish_pr")
    assert has_element?(view, "#run-detail-current-stage", "publish_pr")
  end

  test "54.5.2 specs, planning, and contributor docs stay aligned after drift closure" do
    phase_plan = repo_file!(".spec/planning/phase-54-drift-closure-and-current-truth-convergence.md")
    planning_readme = repo_file!(".spec/planning/README.md")
    readme = repo_file!("README.md")
    contributing = repo_file!("CONTRIBUTING.md")

    assert phase_plan =~ "[x] 54 Phase 54 - Drift Closure And Current-Truth Convergence"
    assert phase_plan =~ "[x] 54.5 Section - Phase 54 Integration Tests"
    assert phase_plan =~ "[x] 54.5.2 Task - Verify current-truth convergence across specs, planning, and docs"

    assert planning_readme =~ "Phase 54 - Drift Closure And Current-Truth Convergence"
    assert planning_readme =~ "Chronology note: repo integration coverage already includes Phase 55-style"

    assert readme =~ "canonical repository or managed-repository language"
    assert readme =~ "explicit compatibility, migration, or audit seams"

    assert contributing =~ "provision_managed_repo!/1"
    assert contributing =~ "create_governed_run!/2"
    assert contributing =~ "compatibility, migration, or audit coverage"

    assert repo_file!(".spec/specs/agent_os_integration.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/source_code_graph_pod.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/source_code_graph_product_adoption.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/memory_capture_plane.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/memory_graph.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/memory_graph_product_adoption.spec.md") =~ "status: active"
    assert repo_file!(".spec/specs/memory_ontology.spec.md") =~ "status: active"

    assert proposed_specs() == [
             "memory_graph_surface_rollout_and_governance_actions.spec.md",
             "memory_graph_workflow_and_operator_expansion.spec.md"
           ]
  end

  defp proposed_specs do
    repo_root()
    |> Path.join(".spec/specs/*.spec.md")
    |> Path.wildcard()
    |> Enum.filter(&(File.read!(&1) =~ "status: proposed"))
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
