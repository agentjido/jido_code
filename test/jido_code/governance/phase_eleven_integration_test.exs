defmodule JidoCode.Governance.PhaseElevenIntegrationTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.runtime_overlay_preserves_product_truth
  # covers: architecture.repo_posture.runtime_capability_observations_can_inform_posture
  # covers: architecture.repo_posture.operator_surfaces_expose_explainable_governance_state
  # covers: architecture.runtime_service_overlay.runtime_capability_posture_feeds_product_governance
  # covers: architecture.runtime_service_overlay.operator_surfaces_keep_runtime_rollout_narratives_product_oriented
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}

  alias JidoCode.Governance.{
    PostureBridge,
    RuntimeCapabilityBridge,
    RuntimeEvidenceBridge,
    RuntimeEvidenceFeed,
    RuntimeIntegrationBridge
  }

  alias JidoCode.Operations.Ingress
  alias JidoCode.Orchestration.RunBridge
  alias JidoCode.Projects.Project
  alias JidoCode.RuntimeIntegration

  setup do
    instance_id = "jido-code-phase-eleven-#{System.unique_integer([:positive, :monotonic])}"
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

    :ok
  end

  test "coding and integration runtime evidence converge into posture and operator feed summaries" do
    workspace_path = create_workspace_path!("phase-eleven")
    seed_spec_state!(workspace_path)

    with_runtime_status_overrides(
      %{
        "coding_assistance_service" => runtime_status_override("denied", "policy_denied", true, false, false)
      },
      fn ->
        actor_id = "phase-eleven-operator"
        {project, managed_repo} = create_repo!(workspace_path)

        assert {:ok, %{assessment: _assessment, work_item: work_item}} =
                 Ingress.record_operator_intake(%{
                   project_id: project.id,
                   channel: "conversation",
                   intent: "coding_turn_request",
                   actor: %{id: actor_id, email: "phase-eleven@example.com"},
                   payload: %{"objective" => "Prove runtime evidence converges cleanly."}
                 })

        turn_id = "turn-phase-eleven-#{System.unique_integer([:positive, :monotonic])}"
        session_id = "conversation-phase-eleven-#{System.unique_integer([:positive, :monotonic])}"

        assert {:ok, %{run: run}} =
                 RunBridge.materialize_turn(%{
                   project_id: project.id,
                   managed_repo_id: managed_repo.id,
                   work_item_id: work_item.id,
                   actor_id: actor_id,
                   actor_email: "phase-eleven@example.com",
                   conversation_id: session_id,
                   turn: %{
                     turn_id: turn_id,
                     session_id: session_id,
                     conversation_id: session_id,
                     state: "completed",
                     operation: "plan",
                     objective: "Prove runtime evidence converges cleanly.",
                     assistant_output: %{"message" => "Replay fallback preserved review-safe delivery."}
                   },
                   review: %{
                     turn_id: turn_id,
                     assistant_output: %{"message" => "Replay fallback preserved review-safe delivery."}
                   },
                   events: [
                     %{
                       "event_id" => "phase-eleven-progress-1",
                       "turn_id" => turn_id,
                       "family" => "progress",
                       "content" => "Switching to replay fallback."
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
                     "correlation_id" => "corr-phase-eleven",
                     "summary" => "Coding turn delivery fell back to replay because rollout was withheld."
                   }
                 })

        assert is_binary(run.id)

        assert {:ok, %{observation: capability_observation, capability_posture: capability_posture}} =
                 RuntimeCapabilityBridge.sync_managed_repo(managed_repo)

        assert capability_posture["status"] == "blocked"

        assert {:ok, install_session} =
                 RuntimeIntegration.begin_install(actor_id, %{
                   managed_repo_id: managed_repo.id,
                   provider: "github",
                   binding_alias: "phase-eleven-github"
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

        assert {:ok, %{observation: runtime_observation, runtime_evidence: runtime_evidence}} =
                 RuntimeEvidenceBridge.sync_managed_repo(
                   managed_repo,
                   runtime_capability_observation: capability_observation,
                   runtime_capability_state: capability_posture
                 )

        assert runtime_evidence["status"] == "blocked"
        assert runtime_evidence["review_required"] == true
        assert runtime_evidence["runtime_delivery"]["delivery_mode"] == "replay_fallback"
        assert runtime_evidence["runtime_delivery"]["reason_code"] == "rollout_withheld"
        assert runtime_evidence["integration_outcomes"]["latest_invocation"]["provider"] == "github"

        assert {:ok, %{repo_posture: repo_posture, posture_checks: posture_checks}} =
                 PostureBridge.sync_managed_repo(managed_repo)

        assert repo_posture.execution_readiness == "low"
        assert repo_posture.review_burden == "high"
        assert repo_posture.supervision_mode == "guided"
        assert repo_posture.escalation_status == "review"
        assert repo_posture.posture_metadata["runtime_service_evidence_state"]["status"] == "blocked"

        assert repo_posture.posture_metadata["latest_observation_ids"]["runtime_service_evidence"] ==
                 runtime_observation.id

        recovery_check = posture_check(posture_checks, "recovery_resilience")
        review_check = posture_check(posture_checks, "review_burden")

        assert recovery_check.source == "governance.evidence+runtime_service"
        assert review_check.source == "governance.review_policy+runtime_capability"

        assert {:ok, summaries, nil} = RuntimeEvidenceFeed.load()

        summary =
          Enum.find(summaries, fn candidate ->
            candidate.managed_repo_id == managed_repo.id
          end)

        assert summary.status == "blocked"
        assert summary.delivery_mode == "replay_fallback"
        assert summary.reason_code == "rollout_withheld"
        assert summary.latest_provider == "github"
        assert summary.review_required == true

        encoded_summary = Jason.encode!(summary)

        refute encoded_summary =~ "subscription_id"
        refute encoded_summary =~ "subscriber_ref"
        refute encoded_summary =~ "connection_id"
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

  defp create_repo!(workspace_path) do
    {:ok, project} =
      Project.create(%{
        name: "phase-eleven-runtime-evidence-repo",
        github_full_name: "owner/phase-eleven-runtime-evidence-repo",
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

  defp seed_spec_state!(workspace_path) do
    spec_dir = Path.join(workspace_path, ".spec")
    specs_dir = Path.join(spec_dir, "specs")
    decisions_dir = Path.join(spec_dir, "decisions")

    File.mkdir_p!(specs_dir)
    File.mkdir_p!(decisions_dir)

    File.write!(Path.join(specs_dir, "factory_control_plane.spec.md"), "# Factory Control Plane\n")
    File.write!(Path.join(specs_dir, "repo_posture.spec.md"), "# Repo Posture\n")
    File.write!(Path.join(decisions_dir, "factory_control_plane.md"), "# ADR\n")

    state = %{
      "summary" => %{
        "subjects" => 2,
        "decisions" => 1,
        "requirements" => 8,
        "scenarios" => 4,
        "findings" => 0
      },
      "workspace" => %{
        "spec_count" => 2,
        "decision_count" => 1
      },
      "verification" => %{
        "threshold_failures" => 0,
        "strength_summary" => %{"linked" => 6, "claimed" => 0, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.factory_control_plane"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end

  defp restore_env(app, key, nil), do: Application.delete_env(app, key)
  defp restore_env(app, key, value), do: Application.put_env(app, key, value)
end
