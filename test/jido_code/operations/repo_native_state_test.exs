defmodule JidoCode.Operations.RepoNativeStateTest do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.factory_control_plane.repo_native_state_layers_inform_control_plane
  # covers: architecture.event_assessment_synthesis.assessment_space_for_future_inputs
  # covers: architecture.event_assessment_synthesis.repo_native_state_informs_assessment_inputs
  # covers: architecture.repo_posture.repo_native_observations_capture_current_truth_signals
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.RepoBridge
  alias JidoCode.ControlPlane.StoreServer
  alias JidoCode.Operations.{Ingress, RecordStore, RepoNativeState}
  alias JidoCode.Projects.Project

  setup do
    setup_product_store()
  end

  test "repo-native .spec and optional beadwork state are observed and fed back into assessment inputs" do
    workspace_path = create_workspace_path!()
    seed_spec_state!(workspace_path)

    {:ok, project} =
      Project.create(%{
        name: "repo-native-signals",
        github_full_name: "owner/repo-native-signals",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    managed_repo = seed_managed_repo!(project)

    assert {:ok, %{signals: snapshot}} = RepoNativeState.sync_managed_repo(managed_repo)
    assert snapshot["spec_led"]["present"] == true
    assert snapshot["spec_led"]["status"] == "verified"
    assert snapshot["spec_led"]["verification_confidence"] == "high"
    assert snapshot["beadwork"]["present"] == false

    assert {:ok, [spec_observation]} =
             RecordStore.list(:observation, %{
               managed_repo_id: managed_repo.id,
               source: "repo_native",
               category: "spec_led_state"
             })

    assert spec_observation.payload["spec_count"] == 2
    assert spec_observation.payload["threshold_failures"] == 0

    assert {:ok, %{work_item: work_item}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-repo-native", email: "signals@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    seed_beadwork_state!(workspace_path, work_item.id)

    assert {:ok, %{signals: refreshed_snapshot}} = RepoNativeState.sync_managed_repo(managed_repo)
    assert refreshed_snapshot["beadwork"]["present"] == true
    assert refreshed_snapshot["beadwork"]["status"] == "aligned"
    assert refreshed_snapshot["beadwork"]["aligned_open_work_item_ids"] == [work_item.id]

    assert {:ok, %{assessment: assessment}} =
             Ingress.record_operator_intake(%{
               project_id: project.id,
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               actor: %{id: "operator-repo-native", email: "signals@example.com"},
               payload: %{"workflow_name" => "fix_failing_tests", "failure_signal" => "mix test"}
             })

    assert assessment.inputs["repo_native_state"]["spec_led"]["status"] == "verified"
    assert assessment.inputs["repo_native_state"]["spec_led"]["verification_confidence"] == "high"
    assert assessment.inputs["repo_native_state"]["beadwork"]["status"] == "aligned"
    assert assessment.inputs["repo_native_state"]["beadwork"]["aligned_open_work_item_ids"] == [work_item.id]
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-phase-five-workspace-#{System.unique_integer([:positive])}"
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
    File.write!(Path.join(decisions_dir, "README.md"), "# Decisions\n")
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
        "strength_summary" => %{"linked" => 6, "claimed" => 1, "executed" => 0},
        "claims" => [%{"subject_id" => "architecture.factory_control_plane"}]
      }
    }

    File.write!(Path.join(spec_dir, "state.json"), Jason.encode!(state))
  end

  defp seed_beadwork_state!(workspace_path, work_item_id) do
    beadwork_dir = Path.join(workspace_path, ".beadwork")
    File.mkdir_p!(Path.join(beadwork_dir, "work"))

    File.write!(
      Path.join(workspace_path, "memory.md"),
      """
      # Memory

      work_item_id: #{work_item_id}
      """
    )

    File.write!(
      Path.join([beadwork_dir, "work", "runtime-posture.md"]),
      """
      # Runtime posture follow-up

      work_item_id: #{work_item_id}
      """
    )
  end

  defp seed_managed_repo!(project) do
    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: project.name,
        full_name: project.github_full_name,
        default_branch: project.default_branch,
        legacy_project_id: project.id,
        settings: project.settings || %{}
      })

    managed_repo
  end

  defp setup_product_store do
    store_name = :"operations_repo_native_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_operations_repo_native/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
