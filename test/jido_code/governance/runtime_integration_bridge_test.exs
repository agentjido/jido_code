defmodule JidoCode.Governance.RuntimeIntegrationBridgeTest do
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.integration_service_is_canonical_external_runtime_boundary
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RuntimeIntegrationBridge
  alias JidoCode.Operations.{Event, Observation}
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeIntegration

  setup do
    instance_id = "jido-code-runtime-integration-bridge-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "binding health is materialized as a governed observation with an operator summary" do
    workspace_path = create_workspace_path!("runtime-integration-bridge-health")
    actor_id = "runtime-integration-bridge-health"
    {project, managed_repo} = create_repo!(workspace_path)

    assert {:ok, install_session} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               binding_alias: "primary-github"
             })

    assert {:ok, _binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               install_id: install_session.install_id,
               provider: "github"
             })

    assert {:ok, %{observation: observation, binding_health: binding_health}} =
             RuntimeIntegrationBridge.sync_managed_repo(managed_repo)

    assert observation.source == RuntimeIntegrationBridge.source()
    assert observation.category == RuntimeIntegrationBridge.binding_health_category()
    assert binding_health["status"] == "ready"
    assert binding_health["binding_count"] == 1
    assert binding_health["connected_binding_count"] == 1
    assert binding_health["runtime_capability"]["service_key"] == "integration_service"

    assert RuntimeIntegrationBridge.operator_summary(binding_health) ==
             "Integration runtime is available. Provider github has 1 connected binding(s)."

    assert {:ok, latest_snapshot} = RuntimeIntegrationBridge.latest_signal_snapshot(managed_repo.id)
    assert latest_snapshot["summary"] == binding_health["summary"]

    assert {:ok, [persisted_observation]} =
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

    assert persisted_observation.id == observation.id
    assert persisted_observation.payload["legacy_project_id"] == project.id
  end

  test "install and invocation outcomes are normalized into product observations and events" do
    workspace_path = create_workspace_path!("runtime-integration-bridge-outcomes")
    actor_id = "runtime-integration-bridge-outcomes"
    {_project, managed_repo} = create_repo!(workspace_path)

    assert {:ok, install_session} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               binding_alias: "phase-ten-install"
             })

    assert {:ok, install_observation} =
             RuntimeIntegrationBridge.record_install_outcome(managed_repo, install_session)

    assert install_observation.category == RuntimeIntegrationBridge.install_category()
    assert install_observation.summary =~ "github binding phase-ten-install"
    assert install_observation.payload["context"]["actor_id"] == actor_id
    refute Jason.encode!(install_observation.payload) =~ "connection_id"

    assert {:ok, _binding} =
             RuntimeIntegration.complete_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               install_id: install_session.install_id,
               provider: "github"
             })

    assert {:ok, invocation} =
             RuntimeIntegration.invoke_operation(actor_id, %{
               managed_repo_id: managed_repo.id,
               operation: %{
                 provider: "github",
                 operation_id: "github.repositories.list"
               },
               input: %{"owner" => "epic-creative"}
             })

    assert {:ok, invocation_event} =
             RuntimeIntegrationBridge.record_invocation_outcome(managed_repo, invocation)

    assert invocation_event.category == RuntimeIntegrationBridge.invocation_category()
    assert invocation_event.summary =~ "github:github.repositories.list"
    assert invocation_event.correlation_key == invocation.context.correlation_id
    assert invocation_event.payload["project_binding"]["binding_alias"] == "phase-ten-install"
    assert invocation_event.source_metadata["provider"] == "github"
    assert invocation_event.source_metadata["actor_id"] == actor_id
    refute Jason.encode!(invocation_event.payload) =~ "connection_id"

    assert {:ok, [persisted_event]} =
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

    assert persisted_event.id == invocation_event.id
  end

  defp create_repo!(workspace_path) do
    {:ok, project} =
      Project.create(%{
        name: "runtime-integration-bridge-repo",
        github_full_name: "owner/runtime-integration-bridge-repo",
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
