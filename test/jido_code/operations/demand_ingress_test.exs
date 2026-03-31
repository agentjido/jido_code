defmodule JidoCode.Operations.DemandIngressTest do
  # covers: architecture.demand_ingress.external_object_tracks_repo_external_entities
  # covers: architecture.demand_ingress.observation_captures_repo_and_system_facts
  # covers: architecture.demand_ingress.intake_captures_operator_and_trusted_requests
  # covers: architecture.demand_ingress.normalized_ingress_preserves_attribution_and_correlation
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Operations.{ExternalObject, Ingress, Intake, Observation}
  alias JidoCode.Projects.Project
  alias JidoCode.Setup.ProjectImport
  alias JidoCode.Workbench.FixWorkflowKickoff

  @managed_env_keys [
    :setup_project_importer,
    :setup_project_clone_provisioner,
    :setup_project_baseline_syncer,
    :workbench_fix_workflow_launcher
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

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      {:ok, %{run_id: "fix-workflow-run-#{System.unique_integer([:positive])}"}}
    end)

    :ok
  end

  test "github webhook demand creates a tracked external object and observation linked to the managed repo" do
    {:ok, project} =
      Project.create(%{
        name: "repo-one",
        github_full_name: "owner/repo-one",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    delivery = %{
      delivery_id: "delivery-123",
      event: "issues",
      payload: %{
        "action" => "opened",
        "repository" => %{
          "id" => 44,
          "name" => "repo-one",
          "full_name" => "owner/repo-one",
          "html_url" => "https://github.com/owner/repo-one",
          "visibility" => "public"
        },
        "issue" => %{
          "id" => 9001,
          "number" => 12,
          "title" => "Fix the failing build",
          "html_url" => "https://github.com/owner/repo-one/issues/12",
          "state" => "open"
        }
      }
    }

    assert {:ok,
            %{
              external_object: external_object,
              observation: observation,
              event: _event,
              assessment: _assessment
            }} =
             Ingress.record_github_webhook_delivery(delivery)

    assert external_object.managed_repo_id == managed_repo.id
    assert external_object.provider == :github
    assert external_object.object_type == :github_issue
    assert external_object.external_id == "9001"
    assert external_object.canonical_reference == "owner/repo-one#12"
    assert external_object.title == "Fix the failing build"

    assert observation.managed_repo_id == managed_repo.id
    assert observation.external_object_id == external_object.id
    assert observation.source == "github_webhook"
    assert observation.category == "external_event"
    assert observation.summary == "Observed issues opened owner/repo-one#12."
    assert observation.source_metadata["delivery_id"] == "delivery-123"
    assert observation.source_metadata["repo_full_name"] == "owner/repo-one"
    assert observation.source_metadata["project_id"] == project.id
    assert observation.source_metadata["managed_repo_id"] == managed_repo.id
    assert observation.captured_by["actor_class"] == "external_ingress"
    assert observation.captured_by["delivery_id"] == "delivery-123"

    assert {:ok, persisted_external_object} =
             ExternalObject.get_by_canonical_key(
               "github:github_issue:owner/repo-one:9001",
               actor: Actor.operator_actor()
             )

    assert persisted_external_object.id == external_object.id

    assert {:ok, [persisted_observation]} =
             Observation.read(
               query: [filter: [external_object_id: external_object.id]],
               actor: Actor.operator_actor()
             )

    assert persisted_observation.id == observation.id
  end

  test "operator intake resolves managed repo context from the transitional project identifier" do
    {:ok, project} =
      Project.create(%{
        name: "repo-two",
        github_full_name: "owner/repo-two",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, %{intake: intake, event: _event, assessment: _assessment}} =
             Ingress.record_operator_intake(%{
               channel: "workbench",
               intent: "fix_workflow_kickoff",
               project_id: project.id,
               actor: %{id: "operator-1", email: "operator@example.com"},
               payload: %{"context_item_type" => "issue"},
               source_metadata: %{"trigger" => %{"source" => "workbench"}}
             })

    assert intake.managed_repo_id == managed_repo.id
    assert intake.channel == "workbench"
    assert intake.intent == "fix_workflow_kickoff"
    assert intake.requested_by["id"] == "operator-1"
    assert intake.requested_by["email"] == "operator@example.com"
    assert intake.requested_by["actor_class"] == "operator"
    assert intake.source_metadata["trigger"]["source"] == "workbench"
  end

  test "project import records setup intake against the managed repo before import completes" do
    onboarding_state = %{
      "4" => %{
        "github_credentials" => %{
          "paths" => [
            %{
              "status" => "ready",
              "repositories" => [
                %{"full_name" => "owner/repo-import", "default_branch" => "develop"}
              ]
            }
          ]
        }
      }
    }

    report = ProjectImport.run(nil, "owner/repo-import", onboarding_state)

    refute ProjectImport.blocked?(report)

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(report.project_record.id, actor: Actor.operator_actor())

    assert {:ok, [intake]} =
             Intake.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   channel: "setup",
                   intent: "project_import"
                 ],
                 sort: [inserted_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert intake.payload["selected_repository"] == "owner/repo-import"
    assert intake.payload["project_name"] == "repo-import"
    assert intake.payload["default_branch"] == "develop"
    assert intake.source_metadata["source_step"] == "setup.project_import"
    assert "owner/repo-import" in intake.source_metadata["available_repositories"]
    assert intake.requested_by["actor_class"] == "operator"
  end

  test "workbench fix kickoff records a durable intake before launcher completion" do
    {:ok, project} =
      Project.create(%{
        name: "repo-fix",
        github_full_name: "owner/repo-fix",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    assert {:ok, kickoff_run} =
             FixWorkflowKickoff.kickoff(
               project,
               :issue,
               %{id: "operator-22", email: "operator22@example.com"}
             )

    assert kickoff_run.project_id == project.id
    assert kickoff_run.context_item_type == :issue

    assert {:ok, [intake]} =
             Intake.read(
               query: [
                 filter: [
                   managed_repo_id: managed_repo.id,
                   channel: "workbench",
                   intent: "fix_workflow_kickoff"
                 ],
                 sort: [inserted_at: :desc],
                 limit: 1
               ],
               actor: Actor.operator_actor()
             )

    assert intake.payload["workflow_name"] == "fix_failing_tests"
    assert intake.payload["project_name"] == "owner/repo-fix"
    assert intake.payload["context_item"]["type"] == "issue"
    assert intake.source_metadata["trigger"]["source"] == "workbench"
    assert intake.source_metadata["trigger"]["mode"] == "manual"
    assert intake.requested_by["id"] == "operator-22"
    assert intake.requested_by["email"] == "operator22@example.com"
    assert intake.requested_by["actor_class"] == "operator"
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
