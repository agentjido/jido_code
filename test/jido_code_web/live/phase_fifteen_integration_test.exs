defmodule JidoCodeWeb.PhaseFifteenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  setup do
    original_override = Application.get_env(:jido_code, :frontend_assets_override, :__missing__)

    on_exit(fn ->
      restore_env(:frontend_assets_override, original_override)
    end)

    :ok
  end

  test "dashboard falls back to bounded liveview fallback when richer delivery degrades", %{
    conn: _conn
  } do
    register_owner("phase15-dashboard-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase15-dashboard-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    {:ok, view, html} = live(recycle(authed_conn), ~p"/dashboard", on_error: :warn)

    assert has_element?(
             view,
             "#dashboard-run-summary-widget-fallback",
             "Interactive summary temporarily unavailable"
           )

    assert has_element?(
             view,
             "#dashboard-run-summary-widget-fallback",
             "server-rendered fallback mode"
           )

    assert has_element?(
             view,
             "#dashboard-run-summary-widget-fallback",
             "Fallback mode reason: Asset manifest unavailable"
           )

    assert has_element?(view, "#dashboard-run-summary-fallback", "LiveView detail fallback")

    assert has_element?(
             view,
             "#dashboard-runtime-posture-widget-fallback",
             "Interactive summary temporarily unavailable"
           )

    assert has_element?(view, "#dashboard-runtime-evidence-fallback", "LiveView posture details")
    refute html =~ "actions/setup-node"
    refute html =~ "NodeJS.Supervisor"
    refute html =~ "vite build"
  end

  test "plain liveview routes stay unaffected by frontend fallback delivery", %{conn: conn} do
    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    {:ok, _view, html} = live(conn, ~p"/welcome")

    assert html =~ "Create your admin account"
    assert html =~ "Checking your system"
    refute html =~ "Interactive summary temporarily unavailable"
    refute html =~ "Fallback mode reason:"
  end

  test "repo docs and ci converge on the live vue verification path" do
    readme = repo_file!("README.md")
    contributing = repo_file!("CONTRIBUTING.md")
    agents = repo_file!("AGENTS.md")
    ci_workflow = repo_file!(".github/workflows/ci.yml")
    mixfile = repo_file!("mix.exs")
    phase_plan = repo_file!(".planning/phase-15-frontend-rollout-hardening-and-contributor-convergence.md")

    assert readme =~ "mix frontend.verify"
    assert readme =~ "<.vue_surface"
    assert contributing =~ "mix frontend.verify"
    assert contributing =~ "LiveView-first"
    assert agents =~ "mix frontend.verify"
    assert agents =~ "<.vue_surface ...>"
    assert mixfile =~ "\"frontend.verify\": [\"assets.setup\", \"assets.build\"]"
    assert ci_workflow =~ "Verify frontend asset pipeline"
    assert ci_workflow =~ "actions/setup-node@v4"
    assert phase_plan =~ "[x] 15 Phase 15 - Frontend Rollout Hardening and Contributor Convergence"
    assert phase_plan =~ "[x] 15.3 Section - Phase 15 Integration Tests"
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
