defmodule JidoCode.Governance.PhaseEightIntegrationTest do
  # covers: coding_assistance.boundary.public_jido_os_service_boundary
  # covers: coding_assistance.boundary.runtime_bootstrap_defaults
  # covers: coding_assistance.boundary.product_local_driver_api
  # covers: architecture.runtime_service_overlay.public_service_facades_are_only_product_runtime_seam
  # covers: architecture.runtime_service_overlay.optional_runtime_capabilities_are_explicit_and_typed
  # covers: architecture.runtime_service_overlay.product_owned_gateways_preserve_contracts
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.policy_layers.policy_layers_interlock_without_collapsing
  # covers: architecture.policy_layers.repo_posture_can_shape_effective_review_policy
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.repo_posture.posture_checks_preserve_explainable_links
  # covers: architecture.repo_posture.supervision_modes_are_explicit_and_reversible
  use JidoCode.DataCase, async: false

  alias JidoCode.CodingAssistance
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{PolicyBridge, PostureBridge, RuntimeCapabilityBridge}
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeGateway

  setup do
    instance_id = "jido-code-phase-eight-#{System.unique_integer([:positive, :monotonic])}"
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

  test "runtime gateway preserves the product seam while typed capability posture remains explicit" do
    workspace_path = create_workspace_path!("gateway")
    actor_id = "phase-eight-gateway-operator"
    session_id = "phase-eight-session-#{System.unique_integer([:positive])}"

    context =
      RuntimeGateway.context_for(actor_id, %{
        session_id: session_id,
        project_id: "phase-eight-project",
        workspace_id: workspace_path
      })

    assert context.instance_id == RuntimeGateway.instance_id()
    assert context.actor_id == actor_id
    assert context.session_id == session_id
    assert context.project_id == "phase-eight-project"
    assert context.workspace_id == workspace_path
    assert is_binary(context.request_id)
    assert is_binary(context.correlation_id)

    assert {:ok, status} =
             CodingAssistance.runtime_service_status(actor_id, %{
               session_id: session_id,
               project_id: "phase-eight-project",
               workspace_id: workspace_path
             })

    assert status.service_key == "coding_assistance_service"
    assert status.status == "available"
    refute Map.has_key?(status, :pid)
    refute Map.has_key?(status, :topic)
    refute Map.has_key?(status, :subscriber_ref)

    assert {:ok, turn} =
             CodingAssistance.start_turn(actor_id, %{
               session_id: session_id,
               project_id: "phase-eight-project",
               workspace_id: workspace_path,
               objective: "Document the runtime gateway boundary",
               operation: "plan"
             })

    assert turn.session_id == session_id
    assert turn.conversation_id == session_id
    assert turn.state == "completed"
    assert turn.assistant_output.message =~ "Document"

    assert {:ok, unavailable} =
             RuntimeGateway.capability_posture("missing_runtime_service", actor_id, %{
               workspace_id: workspace_path
             })

    assert unavailable.status == "unavailable"
    assert unavailable.governance_effect == "blocked"
    assert unavailable.denial_reason == "runtime_service_unknown"

    Enum.each(
      [
        {"withheld", runtime_status_override("withheld", "rollout_withheld", false, false, false)},
        {"denied", runtime_status_override("denied", "policy_denied", true, false, false)},
        {"degraded", runtime_status_override("degraded", "degraded_path", true, true, true)}
      ],
      fn {expected_status, override} ->
        with_runtime_status_overrides(%{"coding_assistance_service" => override}, fn ->
          assert {:ok, posture} =
                   RuntimeGateway.capability_posture(CodingAssistance, actor_id, %{
                     workspace_id: workspace_path
                   })

          assert posture.status == expected_status

          case expected_status do
            "degraded" ->
              assert posture.governance_effect == "review_required"
              assert posture.denial_reason == nil
              assert posture.degraded_path_evidence.reason_code == "degraded_path"

            "withheld" ->
              assert posture.governance_effect == "blocked"
              assert posture.denial_reason == "rollout_withheld"

            "denied" ->
              assert posture.governance_effect == "blocked"
              assert posture.denial_reason == "policy_denied"
          end
        end)
      end
    )
  end

  test "runtime capability posture can force guided review even when configured repo policy stays auto-post" do
    workspace_path = create_workspace_path!("governance")
    seed_spec_state!(workspace_path)

    with_runtime_status_overrides(
      %{
        "coding_assistance_service" => runtime_status_override("denied", "policy_denied", true, false, false)
      },
      fn ->
        {:ok, project} =
          Project.create(%{
            name: "repo-phase-eight-governance",
            github_full_name: "owner/repo-phase-eight-governance",
            default_branch: "main",
            settings: %{
              "support_agent_config" => %{
                "github_issue_bot" => %{"approval_mode" => "auto_post"}
              },
              "workspace" => %{
                "workspace_environment" => "local",
                "workspace_path" => workspace_path,
                "clone_status" => "ready",
                "workspace_initialized" => true,
                "baseline_synced" => true
              },
              "runtime_capabilities" => %{
                "required_services" => ["coding_assistance_service"]
              }
            }
          })

        {:ok, managed_repo} =
          ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

        assert {:ok, configured_review_policy} =
                 PolicyBridge.configured_review_policy_for_managed_repo(managed_repo.id)

        assert configured_review_policy["mode"] == "auto_post"
        assert configured_review_policy["requires_human_approval"] == false
        assert configured_review_policy["change_request_required"] == false

        assert {:ok, %{observation: observation, capability_posture: capability_posture}} =
                 RuntimeCapabilityBridge.sync_managed_repo(managed_repo)

        assert capability_posture["status"] == "blocked"
        assert capability_posture["blocked_service_count"] == 1

        assert capability_posture["services"] == [
                 %{
                   "service_key" => "coding_assistance_service",
                   "status" => "denied",
                   "governance_effect" => "blocked",
                   "denial_reason" => "policy_denied",
                   "available?" => false,
                   "ready?" => false,
                   "admitted?" => true,
                   "rollout_source" => "repo_local_compatibility_surface",
                   "degraded_path_evidence" => %{
                     "runtime_status" => "running",
                     "dependency_status" => "satisfied",
                     "child_spec_ready" => true,
                     "reason_code" => "policy_denied"
                   },
                   "summary" => "Runtime service coding_assistance_service is denied for the current runtime context."
                 }
               ]

        assert {:ok, %{repo_posture: repo_posture, posture_checks: posture_checks}} =
                 PostureBridge.sync_managed_repo(managed_repo)

        assert repo_posture.execution_readiness == "low"
        assert repo_posture.review_burden == "high"
        assert repo_posture.supervision_mode == "guided"
        assert repo_posture.escalation_status == "review"
        assert repo_posture.posture_metadata["runtime_capability_state"]["status"] == "blocked"
        assert repo_posture.posture_metadata["runtime_capability_state"]["services"] == capability_posture["services"]
        assert repo_posture.posture_metadata["latest_observation_ids"]["runtime_capability"] == observation.id

        execution_check = posture_check(posture_checks, "execution_readiness")
        review_check = posture_check(posture_checks, "review_burden")

        assert execution_check.source == "runtime_capability.execution"
        assert review_check.source == "governance.review_policy+runtime_capability"
        assert execution_check.observation_id == observation.id
        assert review_check.observation_id == observation.id
        assert execution_check.details["runtime_capability_state"]["services"] == capability_posture["services"]

        assert {:ok, effective_review_policy} =
                 PolicyBridge.review_policy_for_managed_repo(managed_repo.id)

        assert effective_review_policy["mode"] == "approval_required"
        assert effective_review_policy["requires_human_approval"] == true
        assert effective_review_policy["change_request_required"] == true
        assert effective_review_policy["supervision_mode"] == "guided"
        assert effective_review_policy["posture_override"] == true
        assert effective_review_policy["configured_source"] == "support_agent_config.github_issue_bot.approval_mode"
      end
    )
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

  defp posture_check(posture_checks, dimension) do
    Enum.find(posture_checks, &(&1.dimension == dimension))
  end

  defp create_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-eight-integration-#{suffix}-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp seed_spec_state!(workspace_path) do
    spec_dir = Path.join(workspace_path, ".spec")
    specs_dir = Path.join(spec_dir, "specs")
    decisions_dir = Path.join(spec_dir, "decisions")

    File.mkdir_p!(specs_dir)
    File.mkdir_p!(decisions_dir)

    File.write!(Path.join(specs_dir, "factory_control_plane.spec.md"), "# Factory Control Plane\n")
    File.write!(Path.join(specs_dir, "repo_posture.spec.md"), "# Repo Posture\n")
    File.write!(Path.join(specs_dir, "runtime_service_overlay.spec.md"), "# Runtime Service Overlay\n")
    File.write!(Path.join(decisions_dir, "factory_control_plane.md"), "# ADR\n")

    state = %{
      "summary" => %{
        "subjects" => 3,
        "decisions" => 1,
        "requirements" => 12,
        "scenarios" => 6,
        "findings" => 0
      },
      "workspace" => %{
        "spec_count" => 3,
        "decision_count" => 1
      },
      "verification" => %{
        "threshold_failures" => 0,
        "strength_summary" => %{"linked" => 10, "claimed" => 0, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.runtime_service_overlay"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
