defmodule JidoCode.Governance.PhaseTenIntegrationTest do
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.policy_layers.runtime_integration_gateways_preserve_actor_bound_policy
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RuntimeIntegrationBridge
  alias JidoCode.Operations.{Event, Observation}
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeIntegration

  setup do
    instance_id = "jido-code-phase-ten-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "runtime integration flows through the product gateway and back into governed repo records" do
    workspace_path = create_workspace_path!("phase-ten")
    actor_id = "phase-ten-operator"
    {project, managed_repo} = create_repo!(workspace_path)

    assert {:ok, github_install} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               binding_alias: "phase-ten-github",
               metadata: %{"connection_id" => "hidden-connector"}
             })

    assert {:ok, install_observation} =
             RuntimeIntegrationBridge.record_install_outcome(managed_repo, github_install)

    assert install_observation.payload["provider"] == "github"
    assert install_observation.payload["context"]["actor_id"] == actor_id
    refute Jason.encode!(install_observation.payload) =~ "connection_id"

    assert {:ok, github_binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               install_id: github_install.install_id
             })

    assert github_binding.binding_alias == "phase-ten-github"
    assert github_binding.is_default == true

    assert {:ok, notion_install} =
             RuntimeIntegration.begin_install(actor_id, %{
               project_id: project.id,
               provider: "notion",
               binding_alias: "phase-ten-notion"
             })

    assert {:ok, _notion_binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               project_id: project.id,
               provider: "notion",
               install_id: notion_install.install_id
             })

    assert {:ok, operations} =
             RuntimeIntegration.list_provider_operations(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github"
             })

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

    assert invocation.project_binding.binding_id == github_binding.binding_id
    assert invocation.context.actor_id == actor_id

    assert invocation.output["repositories"] == [
             %{
               "full_name" => "epic-creative/example-repo",
               "name" => "example-repo",
               "owner" => "epic-creative"
             }
           ]

    assert {:ok, invocation_event} =
             RuntimeIntegrationBridge.record_invocation_outcome(managed_repo, invocation)

    assert invocation_event.correlation_key == invocation.context.correlation_id
    assert invocation_event.source_metadata["provider"] == "github"
    refute Jason.encode!(invocation_event.payload) =~ "connection_id"

    assert {:ok, %{observation: binding_health_observation, binding_health: binding_health}} =
             RuntimeIntegrationBridge.sync_managed_repo(managed_repo)

    assert binding_health_observation.category == RuntimeIntegrationBridge.binding_health_category()
    assert binding_health["status"] == "ready"
    assert binding_health["binding_count"] == 2
    assert binding_health["connected_binding_count"] == 2
    assert Enum.map(binding_health["providers"], & &1["provider"]) == ["github", "notion"]

    assert {:error, :ambiguous_binding} =
             RuntimeIntegration.get_project_binding(actor_id, %{
               project_id: project.id
             })

    assert {:ok, [install_record]} =
             Observation.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   source: RuntimeIntegrationBridge.source(),
                   category: RuntimeIntegrationBridge.install_category()
                 ],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert install_record.id == install_observation.id

    assert {:ok, [health_record]} =
             Observation.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   source: RuntimeIntegrationBridge.source(),
                   category: RuntimeIntegrationBridge.binding_health_category()
                 ],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert health_record.id == binding_health_observation.id

    assert {:ok, [event_record]} =
             Event.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   category: RuntimeIntegrationBridge.invocation_category()
                 ],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert event_record.id == invocation_event.id
  end

  defp create_repo!(workspace_path) do
    {:ok, project} =
      Project.create(%{
        name: "phase-ten-runtime-integration-repo",
        github_full_name: "owner/phase-ten-runtime-integration-repo",
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
            "required_services" => ["integration_service"]
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {project, managed_repo}
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
