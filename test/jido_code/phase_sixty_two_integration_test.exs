defmodule JidoCode.PhaseSixtyTwoIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: setup.runtime_environment_defaults.import_uses_persisted_runtime_defaults
  # covers: setup.runtime_environment_defaults.repo_scoped_workspace_binding_is_canonical
  # covers: setup.onboarding.runtime_defaults_seed_repo_scoped_workspace_binding
  # covers: architecture.factory_control_plane.managed_repos_own_repo_scoped_workspace_binding
  # covers: architecture.conversation_orchestration.runtime_readiness_uses_managed_repo_workspace_binding
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo, SourceRepo}
  alias JidoCode.Conversations.RuntimeReadiness
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Workbench.ProjectDetail

  @managed_env_keys [
    :system_config,
    :setup_project_importer,
    :setup_project_clone_provisioner,
    :setup_project_baseline_syncer
  ]

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

    Application.delete_env(:jido_code, :setup_project_importer)
    Application.delete_env(:jido_code, :setup_project_clone_provisioner)
    Application.delete_env(:jido_code, :setup_project_baseline_syncer)
    Application.put_env(:jido_code, :system_config, system_config(:sprite, nil))

    :ok
  end

  test "62.3.1 import persists explicit repo-scoped workspace binding and repo detail keeps using it after defaults change" do
    install_default_root = tmp_workspace_path!("phase-sixty-two-install-default")
    repo_parent = tmp_workspace_path!("phase-sixty-two-explicit-repo-parent")
    explicit_workspace_path = Path.join(repo_parent, "owner__repo-one")
    changed_default_root = tmp_workspace_path!("phase-sixty-two-changed-default")

    Application.put_env(:jido_code, :system_config, system_config(:local, install_default_root))

    report =
      ProjectImport.run(
        nil,
        "owner/repo-one",
        github_onboarding_state("owner/repo-one",
          default_branch: "main",
          workspace_path: explicit_workspace_path
        )
      )

    refute ProjectImport.blocked?(report)
    assert report.status == :ready
    assert report.baseline_metadata.workspace_environment == :local
    assert report.baseline_metadata.workspace_path == Path.expand(explicit_workspace_path)

    {:ok, source_repo} =
      SourceRepo.get_by_provider_and_full_name(:github, "owner/repo-one", actor: Actor.operator_actor())

    {:ok, managed_repo} =
      ManagedRepo.get_by_source_repo_id(source_repo.id, actor: Actor.operator_actor())

    assert managed_repo.workspace_settings["workspace_path"] == Path.expand(explicit_workspace_path)

    assert managed_repo.workspace_settings["workspace_root"] ==
             Path.dirname(Path.expand(explicit_workspace_path))

    Application.put_env(:jido_code, :system_config, system_config(:local, changed_default_root))

    {:ok, detail} = ProjectDetail.load(managed_repo.id)

    assert ProjectDetail.ready_for_execution?(detail)
    assert detail.execution_readiness.error_type == nil
    assert ProjectDetail.workspace_path(detail) == Path.expand(explicit_workspace_path)

    assert detail.settings["workspace"]["workspace_root"] ==
             Path.dirname(Path.expand(explicit_workspace_path))

    refute String.starts_with?(ProjectDetail.workspace_path(detail), changed_default_root)
  end

  test "62.3.2 repos without repo-scoped local binding stay blocked even after defaults later point at a shared root" do
    report =
      ProjectImport.run(
        nil,
        "owner/repo-two",
        github_onboarding_state("owner/repo-two", default_branch: "main")
      )

    refute ProjectImport.blocked?(report)
    assert report.status == :ready
    assert report.baseline_metadata.workspace_environment == :sprite
    assert report.baseline_metadata.workspace_path == nil

    Application.put_env(
      :jido_code,
      :system_config,
      system_config(:local, tmp_workspace_path!("phase-sixty-two-late-shared-root"))
    )

    {:ok, detail} = ProjectDetail.load(report.project_record.id)

    refute ProjectDetail.ready_for_execution?(detail)
    assert ProjectDetail.workspace_path(detail) == nil
    assert detail.execution_readiness.status == :blocked
    assert detail.execution_readiness.error_type == "managed_repo_workspace_binding_unavailable"

    assert {:error, notice} = RuntimeReadiness.resolve(report.project_record.id)
    assert notice["error_type"] == "conversation_runtime_workspace_binding_unavailable"
    assert notice["detail"] =~ "no repo-scoped local workspace path"
  end

  @tag skip: "repo-local .spec workspace was removed"
  test "62.3.3 phase 62 plan and specs remain aligned to repo-scoped workspace binding cutover" do
    phase_plan =
      repo_file!(".planning/phase-62-managed-repo-workspace-binding-canonicalization.md")

    runtime_spec = repo_file!(".spec/specs/runtime_environment_defaults.spec.md")
    setup_spec = repo_file!(".spec/specs/setup_onboarding.spec.md")
    factory_spec = repo_file!(".spec/specs/factory_control_plane.spec.md")
    conversation_spec = repo_file!(".spec/specs/conversation_orchestration.spec.md")
    package_spec = repo_file!(".spec/specs/package.spec.md")
    adr = repo_file!(".spec/decisions/jido_code.managed_repo_workspace_binding_is_repo_scoped.md")

    assert phase_plan =~ "[x] 62 Phase 62 - Managed Repo Workspace Binding Canonicalization"
    assert phase_plan =~ "[x] 62.1 Section - Canonical Workspace Binding Model"
    assert phase_plan =~ "[x] 62.2 Section - Import And Provisioning Cutover"
    assert phase_plan =~ "[x] 62.3 Section - Phase Integration Tests"

    assert runtime_spec =~ "test/jido_code/phase_sixty_two_integration_test.exs"
    assert setup_spec =~ "test/jido_code/phase_sixty_two_integration_test.exs"
    assert factory_spec =~ "test/jido_code/phase_sixty_two_integration_test.exs"
    assert conversation_spec =~ "test/jido_code/phase_sixty_two_integration_test.exs"
    assert package_spec =~ "test/jido_code/phase_sixty_two_integration_test.exs"

    assert adr =~ "repository-specific local `workspace_path`"
    assert adr =~ "without requiring one shared install-wide parent root"
  end

  defp github_onboarding_state(full_name, opts) do
    repository =
      %{
        "full_name" => full_name,
        "default_branch" => Keyword.get(opts, :default_branch, "main")
      }
      |> put_optional("workspace_path", Keyword.get(opts, :workspace_path))
      |> put_optional("workspace_root", Keyword.get(opts, :workspace_root))
      |> put_optional("workspace_environment", Keyword.get(opts, :workspace_environment))

    %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [repository]
            }
          ]
        }
      },
      "7" => %{
        "repository_listing" => %{
          "repositories" => [repository]
        }
      }
    }
  end

  defp system_config(default_environment, workspace_root) do
    %{
      onboarding_completed: false,
      onboarding_step: 3,
      onboarding_state: %{},
      default_environment: default_environment,
      workspace_root: workspace_root
    }
  end

  defp put_optional(map, _key, nil), do: map
  defp put_optional(map, key, value), do: Map.put(map, key, value)

  defp tmp_workspace_path!(prefix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../..", __DIR__)
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
