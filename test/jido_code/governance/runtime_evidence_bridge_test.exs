defmodule JidoCode.Governance.RuntimeEvidenceBridgeTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.repo_posture.governed_turn_evidence_can_inform_posture
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.run_governance.governed_turn_evidence_can_inform_posture
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}

  alias JidoCode.Governance.{
    RuntimeCapabilityBridge,
    RuntimeEvidenceBridge,
    RuntimeIntegrationBridge
  }

  alias JidoCode.Operations.Ingress
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeIntegration
  alias JidoCode.Orchestration.RunBridge

  setup do
    instance_id = "jido-code-runtime-evidence-#{System.unique_integer([:positive, :monotonic])}"
    previous_instance_id = Application.get_env(:jido_code, :jido_os_instance_id)
    previous_service_opts = Application.get_env(:jido_os, :managed_service_opts, %{})

    Application.put_env(:jido_code, :jido_os_instance_id, instance_id)

    on_exit(fn ->
      restore_env(:jido_code, :jido_os_instance_id, previous_instance_id)
      Application.put_env(:jido_os, :managed_service_opts, previous_service_opts)
    end)

    %{instance_id: instance_id}
  end

  test "runtime evidence converges bounded capability integration and coding delivery records" do
    workspace_path = create_workspace_path!("runtime-evidence")
    actor_id = "runtime-evidence-operator"
    {project, managed_repo} = create_repo!(workspace_path)

    assert {:ok, %{assessment: _assessment, work_item: work_item}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "conversation",
               intent: "coding_turn_request",
               actor: %{id: actor_id, email: "runtime-evidence@example.com"},
               payload: %{"objective" => "Converge runtime evidence into posture."}
             })

    turn_id = "turn-runtime-evidence-#{System.unique_integer([:positive, :monotonic])}"
    session_id = "conversation-runtime-evidence-#{System.unique_integer([:positive, :monotonic])}"

    assert {:ok, %{run: run}} =
             RunBridge.materialize_turn(%{
               project_id: project.id,
               managed_repo_id: managed_repo.id,
               work_item_id: work_item.id,
               actor_id: actor_id,
               actor_email: "runtime-evidence@example.com",
               conversation_id: session_id,
               turn: %{
                 turn_id: turn_id,
                 session_id: session_id,
                 conversation_id: session_id,
                 state: "completed",
                 operation: "plan",
                 objective: "Converge runtime evidence into posture.",
                 assistant_output: %{"message" => "Replay fallback preserved product truth."}
               },
               review: %{
                 turn_id: turn_id,
                 assistant_output: %{"message" => "Replay fallback preserved product truth."}
               },
               events: [
                 %{
                   "event_id" => "runtime-evidence-event-1",
                   "turn_id" => turn_id,
                   "family" => "progress",
                   "content" => "Repairing through replay fallback."
                 }
               ],
               runtime_delivery: %{
                 "delivery_mode" => "replay_fallback",
                 "live_delivery_status" => "withheld",
                 "reason_code" => "rollout_withheld",
                 "terminal_handoff_kind" => "replay_terminal_lookup",
                 "terminal_state" => "completed",
                 "turn_id" => turn_id,
                 "session_id" => session_id,
                 "conversation_id" => session_id,
                 "correlation_id" => "corr-runtime-evidence",
                 "summary" => "Coding turn delivery fell back to replay because live rollout was withheld."
               }
             })

    assert {:ok, %{observation: capability_observation, capability_posture: capability_posture}} =
             RuntimeCapabilityBridge.sync_managed_repo(managed_repo)

    assert {:ok, install_session} =
             RuntimeIntegration.begin_install(actor_id, %{
               managed_repo_id: managed_repo.id,
               provider: "github",
               binding_alias: "runtime-evidence-github"
             })

    assert {:ok, _install_observation} =
             RuntimeIntegrationBridge.record_install_outcome(managed_repo, install_session)

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

    assert {:ok, _invocation_event} =
             RuntimeIntegrationBridge.record_invocation_outcome(managed_repo, invocation)

    assert {:ok, _binding_health_signal} =
             RuntimeIntegrationBridge.sync_managed_repo(managed_repo)

    assert {:ok, %{observation: observation, runtime_evidence: runtime_evidence}} =
             RuntimeEvidenceBridge.sync_managed_repo(
               managed_repo,
               runtime_capability_observation: capability_observation,
               runtime_capability_state: capability_posture
             )

    assert observation.source == RuntimeEvidenceBridge.source()
    assert observation.category == RuntimeEvidenceBridge.category()
    assert runtime_evidence["status"] == "blocked"
    assert runtime_evidence["review_required"] == true

    assert runtime_evidence["runtime_delivery"] == %{
             "status" => "blocked",
             "delivery_mode" => "replay_fallback",
             "live_delivery_status" => "withheld",
             "reason_code" => "rollout_withheld",
             "terminal_handoff_kind" => "replay_terminal_lookup",
             "terminal_state" => "completed",
             "summary" => "Coding turn delivery fell back to replay because live rollout was withheld.",
             "turn_id" => turn_id,
             "session_id" => session_id,
             "conversation_id" => session_id,
             "correlation_id" => "corr-runtime-evidence",
             "run_id" => run.id,
             "work_item_id" => work_item.id,
             "evidence_id" => runtime_evidence["runtime_delivery"]["evidence_id"],
             "recorded_at" => runtime_evidence["runtime_delivery"]["recorded_at"]
           }

    assert runtime_evidence["integration_binding_health"]["connected_binding_count"] == 1
    assert runtime_evidence["integration_outcomes"]["latest_invocation"]["provider"] == "github"

    assert runtime_evidence["latest_refs"]["runtime_delivery_evidence_id"] ==
             runtime_evidence["runtime_delivery"]["evidence_id"]

    assert runtime_evidence["summary"] =~ "explicit operator review"
    assert runtime_evidence["summary"] =~ "rollout was withheld"

    refute Jason.encode!(runtime_evidence) =~ "subscription_id"
    refute Jason.encode!(runtime_evidence) =~ "connection_id"

    assert {:ok, latest_snapshot} = RuntimeEvidenceBridge.latest_signal_snapshot(managed_repo.id)
    assert latest_snapshot["summary"] == runtime_evidence["summary"]
  end

  defp create_repo!(workspace_path) do
    {:ok, project} =
      Project.create(%{
        name: "runtime-evidence-bridge-repo",
        github_full_name: "owner/runtime-evidence-bridge-repo",
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
