defmodule JidoCodeWeb.PhaseSixtyThreeIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding
  # covers: architecture.factory_control_plane.managed_repos_own_repo_scoped_workspace_binding
  # covers: architecture.conversation_orchestration.runtime_readiness_uses_managed_repo_workspace_binding
  # covers: architecture.frontend_stack.liveview_remains_product_host_shell
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.Workbench.ProjectDetail

  @managed_env_keys [:system_config]

  setup do
    original_env =
      Enum.map(@managed_env_keys, fn key ->
        {key, Application.get_env(:jido_code, key, :__missing__)}
      end)

    on_exit(fn ->
      Enum.each(original_env, fn {key, value} ->
        restore_env(key, value)
      end)
    end)

    :ok
  end

  test "63.3.1 repo detail repair rebinds only the selected managed repository", %{conn: _conn} do
    register_owner("phase63-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase63-owner@example.com", "owner-password-123")

    default_root = create_workspace_path!("phase63-default-root")
    repaired_workspace_path = create_workspace_path!("phase63-repaired-repo")
    sibling_workspace_path = create_workspace_path!("phase63-sibling-repo")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: true,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: :local,
      workspace_root: default_root
    })

    {:ok, repair_target} =
      Project.create(%{
        name: "phase-63-repair-target",
        github_full_name: "owner/phase-63-repair-target",
        default_branch: "main",
        settings: %{
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
      })

    {:ok, sibling_repo} =
      Project.create(%{
        name: "phase-63-sibling-repo",
        github_full_name: "owner/phase-63-sibling-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => sibling_workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          },
          "execution" => %{
            "llm" => %{"provider" => "openai", "model" => "gpt-5-mini"}
          }
        }
      })

    {:ok, view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{repair_target.id}?section=conversations", on_error: :warn)

    assert has_element?(view, "#project-detail-conversation-runtime-status", "Blocked")

    view
    |> element("#project-detail-conversation-runtime-repair")
    |> render_click()

    view
    |> form("#project-detail-workspace-binding-form", %{
      "workspace_binding" => %{
        "workspace_environment" => "local",
        "workspace_path" => repaired_workspace_path
      }
    })
    |> render_submit()

    view
    |> element("#project-detail-overview-open-conversations")
    |> render_click()

    assert has_element?(view, "#project-detail-conversation-runtime-status", "Ready")
    assert has_element?(view, "#project-detail-conversation-runtime-workspace", repaired_workspace_path)

    {:ok, repaired_detail} = ProjectDetail.load(managed_repo_route_id!(repair_target.id))
    {:ok, sibling_detail} = ProjectDetail.load(managed_repo_route_id!(sibling_repo.id))

    assert ProjectDetail.workspace_path(repaired_detail) == repaired_workspace_path
    assert repaired_detail.settings["workspace"]["workspace_root"] ==
             Path.dirname(repaired_workspace_path)

    assert ProjectDetail.workspace_path(sibling_detail) == sibling_workspace_path
    assert Application.get_env(:jido_code, :system_config).workspace_root == default_root
  end

  test "63.3.2 setup runtime defaults remain seed-only metadata after repo detail repair adoption", %{
    conn: conn
  } do
    register_owner("phase63-setup-owner@example.com", "owner-password-123")

    existing_repo_path = create_workspace_path!("phase63-existing-repo")
    new_default_root = create_workspace_path!("phase63-new-default-root")

    Application.put_env(:jido_code, :system_config, %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{
        "1" => %{"validated_note" => "System prerequisites verified (welcome flow)."},
        "2" => %{
          "owner_email" => "phase63-setup-owner@example.com",
          "owner_mode" => "created",
          "registration_actions_disabled" => true,
          "validated_note" => "Owner account bootstrapped."
        }
      },
      default_environment: :sprite,
      workspace_root: nil
    })

    {:ok, project} =
      Project.create(%{
        name: "phase-63-seed-only",
        github_full_name: "owner/phase-63-seed-only",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => existing_repo_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, setup_view, _html} =
      conn
      |> authenticate_owner_conn("phase63-setup-owner@example.com", "owner-password-123")
      |> live(~p"/setup", on_error: :warn)

    render_change(setup_view, "change_runtime_environment", %{
      "runtime_environment" => %{"mode" => "local"}
    })

    render_submit(setup_view, "save_runtime_environment", %{
      "runtime_environment" => %{
        "mode" => "local",
        "workspace_root" => new_default_root
      }
    })

    assert vue(setup_view, id: "setup-runtime-defaults-widget").props["savedRuntimeNote"] ==
             "New local imports will seed repo workspace paths from #{new_default_root} until each managed repository is rebound."

    {:ok, detail} = ProjectDetail.load(managed_repo_route_id!(project.id))
    assert ProjectDetail.workspace_path(detail) == existing_repo_path
    refute ProjectDetail.workspace_path(detail) == new_default_root
    assert Application.get_env(:jido_code, :system_config).workspace_root == new_default_root
  end

  test "63.3.3 phase 63 plan, ADR, specs, and integration coverage remain aligned" do
    phase_plan =
      repo_file!(".spec/planning/phase-63-repo-scoped-workspace-configuration-surfaces.md")

    adr = repo_file!(".spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md")
    frontend_spec = repo_file!(".spec/specs/frontend_architecture.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    baseline_spec = repo_file!(".spec/specs/baseline_surface.spec.md")
    setup_spec = repo_file!(".spec/specs/setup_onboarding.spec.md")
    user_admin_spec = repo_file!(".spec/specs/user_administration.spec.md")
    source_spec = repo_file!(".spec/specs/source_code_graph_product_adoption.spec.md")
    memory_spec = repo_file!(".spec/specs/memory_graph_product_adoption.spec.md")
    memory_rollout_spec =
      repo_file!(".spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md")

    memory_expansion_spec =
      repo_file!(".spec/specs/memory_graph_workflow_and_operator_expansion.spec.md")

    package_spec = repo_file!(".spec/specs/package.spec.md")

    assert phase_plan =~ "[x] 63 Phase 63 - Repo-Scoped Workspace Configuration Surfaces"
    assert phase_plan =~ "[x] 63.1 Section - Repo-Scoped Workspace Mutation Boundaries"
    assert phase_plan =~ "[x] 63.2 Section - Operator And Setup Surface Adoption"
    assert phase_plan =~ "[x] 63.3 Section - Phase Integration Tests"

    assert adr =~ "repo detail"
    assert adr =~ "seed metadata"

    assert frontend_spec =~ "repo-scoped workspace-binding readiness and repair"
    assert frontend_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert conversation_spec =~ "workspace-readiness repair"
    assert conversation_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert factory_spec =~ "workspace inspection and repair"
    assert factory_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert baseline_spec =~ "seed metadata"
    assert baseline_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert setup_spec =~ "seed context"
    assert setup_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert user_admin_spec =~ "runtime defaults as seed metadata"
    assert user_admin_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert source_spec =~ "blocked semantic states on repo detail"
    assert source_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert memory_spec =~ "blocked memory states on repo detail"
    assert memory_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert memory_rollout_spec =~ "reachable from blocked graph-backed surfaces"
    assert memory_rollout_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert memory_expansion_spec =~ "reachable from blocked graph-backed operator states"
    assert memory_expansion_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"

    assert package_spec =~ "repo-detail repair surface"
    assert package_spec =~ "test/jido_code_web/live/phase_sixty_three_integration_test.exs"
  end

  defp create_workspace_path!(prefix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.unique_integer([:positive])}"
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
