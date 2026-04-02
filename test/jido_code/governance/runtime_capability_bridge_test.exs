defmodule JidoCode.Governance.RuntimeCapabilityBridgeTest do
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.RuntimeCapabilityBridge
  alias JidoCode.Operations.Observation
  alias JidoCode.Projects.Project

  test "runtime capability posture is materialized as a governed observation" do
    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "runtime-capability-bridge",
        github_full_name: "owner/runtime-capability-bridge",
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
            "required_services" => ["coding_assistance_service", "missing_runtime_service"]
          }
        }
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{observation: observation, capability_posture: capability_posture}} =
             RuntimeCapabilityBridge.sync_managed_repo(managed_repo)

    assert observation.source == RuntimeCapabilityBridge.source()
    assert observation.category == RuntimeCapabilityBridge.category()
    assert capability_posture["status"] == "blocked"
    assert capability_posture["blocked_service_count"] == 1
    assert capability_posture["available_service_count"] == 1

    assert Enum.map(capability_posture["services"], & &1["service_key"]) == [
             "coding_assistance_service",
             "missing_runtime_service"
           ]

    assert {:ok, latest_snapshot} = RuntimeCapabilityBridge.latest_signal_snapshot(managed_repo.id)
    assert latest_snapshot["summary"] == capability_posture["summary"]

    assert {:ok, [persisted_observation]} =
             Observation.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   source: RuntimeCapabilityBridge.source(),
                   category: RuntimeCapabilityBridge.category()
                 ],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert persisted_observation.id == observation.id

    assert persisted_observation.source_metadata["rollout_source"] ==
             "repo_local_compatibility_surface"
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-runtime-capability-bridge-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
