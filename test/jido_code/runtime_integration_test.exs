defmodule JidoCode.RuntimeIntegrationTest do
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  # covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  # covers: architecture.policy_layers.runtime_integration_gateways_preserve_actor_bound_policy
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeIntegration

  setup do
    instance_id = "jido-code-runtime-integration-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})
    previous_overrides = Application.get_env(:jido_code, :runtime_service_status_overrides, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)
    Application.put_env(:jido_code, :runtime_service_status_overrides, %{})

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      restore_env(:jido_code, :runtime_service_status_overrides, previous_overrides)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "runtime integration gateway resolves repo scope and keeps provider details product-safe" do
    workspace_path = create_workspace_path!("runtime-integration")
    actor_id = "runtime-integration-operator"
    {project, managed_repo} = create_repo!(workspace_path)

    assert RuntimeIntegration.runtime_service_module() == Jido.Os.Integration.Service
    assert RuntimeIntegration.runtime_service_key() == "integration_service"
    assert RuntimeIntegration.supported_providers() == ["github", "notion"]

    assert {:ok, status} =
             RuntimeIntegration.runtime_service_status(actor_id, %{
               project_id: project.id,
               workspace_id: workspace_path
             })

    assert status.service_key == "integration_service"
    assert status.status == "available"
    assert status.available? == true

    assert {:ok, install_session} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               binding_alias: "primary-github",
               redirect_uri: "https://example.test/callback",
               metadata: %{"connection_id" => "connector-secret", "rollout_source" => "phase-ten"}
             })

    assert install_session.managed_repo_id == managed_repo.id
    assert install_session.legacy_project_id == project.id
    assert install_session.runtime_project_id == project.id
    assert install_session.route_id == managed_repo.id
    assert install_session.provider == "github"
    assert install_session.binding_alias == "primary-github"
    assert install_session.context.actor_id == actor_id
    assert install_session.context.workspace_id == workspace_path
    refute Map.has_key?(install_session, :project_id)
    refute inspect(install_session) =~ "connection_id"

    assert {:ok, binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               install_id: install_session.install_id,
               authorization_code: "auth-code-123"
             })

    assert binding.managed_repo_id == managed_repo.id
    assert binding.legacy_project_id == project.id
    assert binding.provider == "github"
    assert binding.binding_alias == "primary-github"
    assert binding.status == "connected"
    assert binding.is_default == true
    refute Map.has_key?(binding, :project_id)

    assert {:ok, listed_bindings} =
             RuntimeIntegration.list_project_bindings(actor_id, %{
               project_id: project.id,
               provider: "github"
             })

    assert Enum.map(listed_bindings, & &1.binding_id) == [binding.binding_id]

    assert {:ok, fetched_binding} =
             RuntimeIntegration.get_project_binding(actor_id, %{
               project_id: project.id,
               provider: "github"
             })

    assert fetched_binding.binding_id == binding.binding_id

    assert {:ok, operations} =
             RuntimeIntegration.list_provider_operations(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github"
             })

    assert operations.managed_repo_id == managed_repo.id
    assert operations.legacy_project_id == project.id
    assert Enum.any?(operations.operations, &(&1.operation_id == "github.repositories.list"))

    assert {:ok, invocation} =
             RuntimeIntegration.invoke_operation(actor_id, %{
               managed_repo_id: managed_repo.id,
               operation: %{
                 provider: "github",
                 operation_id: "github.repositories.list"
               },
               input: %{"owner" => "epic-creative"}
             })

    assert invocation.managed_repo_id == managed_repo.id
    assert invocation.legacy_project_id == project.id
    assert invocation.project_binding.binding_id == binding.binding_id
    assert invocation.project_binding.binding_alias == "primary-github"
    assert invocation.operation.operation_id == "github.repositories.list"

    assert invocation.output["repositories"] == [
             %{
               "full_name" => "epic-creative/example-repo",
               "name" => "example-repo",
               "owner" => "epic-creative"
             }
           ]

    assert invocation.auth_state.status == "ok"
    assert invocation.evidence_ref.correlation_id == invocation.context.correlation_id
    refute inspect(invocation) =~ "connection_id"

    assert {:ok, binding_health} =
             RuntimeIntegration.binding_health_snapshot(actor_id, %{
               managed_repo_id: managed_repo.id
             })

    assert binding_health.status == "ready"
    assert binding_health.binding_count == 1
    assert binding_health.connected_binding_count == 1
    assert binding_health.runtime_capability.service_key == "integration_service"

    assert binding_health.providers == [
             %{
               provider: "github",
               binding_count: 1,
               connected_binding_count: 1,
               default_binding_aliases: ["primary-github"],
               statuses: ["connected"],
               summary: "Provider github has 1 connected binding(s)."
             }
           ]
  end

  test "runtime integration preserves typed ambiguity, missing binding, and unavailable-service outcomes" do
    workspace_path = create_workspace_path!("runtime-integration-errors")
    actor_id = "runtime-integration-errors"
    {project, managed_repo} = create_repo!(workspace_path)

    assert {:ok, github_install} =
             RuntimeIntegration.begin_install(actor_id, %{
               project_id: project.id,
               provider: "github",
               binding_alias: "github-primary"
             })

    assert {:ok, _github_binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               project_id: project.id,
               install_id: github_install.install_id,
               provider: "github"
             })

    assert {:ok, notion_install} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "notion",
               binding_alias: "notion-primary"
             })

    assert {:ok, _notion_binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               install_id: notion_install.install_id,
               provider: "notion"
             })

    assert {:error, :ambiguous_binding} =
             RuntimeIntegration.get_project_binding(actor_id, %{project_id: project.id})

    assert {:error, :binding_not_found} =
             RuntimeIntegration.invoke_operation(actor_id, %{
               project_id: project.id,
               operation: %{
                 provider: "github",
                 operation_id: "github.repositories.list",
                 binding: %{binding_alias: "missing"}
               },
               input: %{"owner" => "epic-creative"}
             })

    with_runtime_status_overrides(
      %{
        "integration_service" => runtime_status_override("withheld", "rollout_withheld", false, false, false)
      },
      fn ->
        assert {:error, {:runtime_service_unavailable, status}} =
                 RuntimeIntegration.begin_install(actor_id, %{
                   project_id: project.id,
                   provider: "github",
                   binding_alias: "blocked"
                 })

        assert status.service_key == "integration_service"
        assert status.status == "withheld"
        assert status.reason_code == "rollout_withheld"
      end
    )
  end

  defp create_repo!(workspace_path) do
    {:ok, project} =
      Project.create(%{
        name: "runtime-integration-repo",
        github_full_name: "owner/runtime-integration-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          },
          "runtime_capabilities" => %{
            "required_services" => ["coding_assistance_service", "integration_service"]
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
  end

  defp with_runtime_status_overrides(overrides, fun) when is_map(overrides) and is_function(fun, 0) do
    previous = Application.get_env(:jido_code, :runtime_service_status_overrides, %{})
    Application.put_env(:jido_code, :runtime_service_status_overrides, overrides)

    try do
      fun.()
    after
      restore_env(:jido_code, :runtime_service_status_overrides, previous)
    end
  end

  defp runtime_status_override(status, reason_code, admitted?, available?, ready?) do
    %{
      "status" => status,
      "admitted?" => admitted?,
      "available?" => available?,
      "ready?" => ready?,
      "child_spec_ready" => true,
      "runtime_status" => "running",
      "dependency_status" => "satisfied",
      "reason_code" => reason_code,
      "extension_admission" => %{
        "enabled" => admitted?,
        "reason_code" => reason_code
      }
    }
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-#{suffix}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
