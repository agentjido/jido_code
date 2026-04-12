defmodule JidoCodeWeb.PhaseThirtyEightIntegrationTest do
  # covers: architecture.memory_graph_product_adoption.managed_repo_routes_host_memory_and_provenance_inspection
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.run_governance.run_detail_can_host_bounded_memory_context
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.Operations.WorkItem
  alias JidoCode.Orchestration.WorkflowRun
  alias JidoCode.Projects.Project

  setup do
    previous_memory = Application.get_env(:jido_code, :memory_graph_enabled, false)
    previous_source = Application.get_env(:jido_code, :source_code_graph_enabled, false)

    Application.put_env(:jido_code, :memory_graph_enabled, true)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous_memory)
      Application.put_env(:jido_code, :source_code_graph_enabled, previous_source)
    end)

    :ok
  end

  test "38.3.1.1 repo detail, run detail, and workbench render governed memory context without generic artifact contracts",
       %{conn: _conn} do
    register_owner("phase38-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase38-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!("ExamplePhaseThirtyEightLive")

    {:ok, project} =
      Project.create(%{
        name: "phase-38-memory-surfaces",
        github_full_name: "owner/phase-38-memory-surfaces",
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

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    {:ok, work_item} =
      WorkItem.create(
        %{
          managed_repo_id: managed_repo.id,
          summary: "Review governed memory context",
          status: :open,
          category: "review_follow_up"
        },
        actor: Actor.operator_actor()
      )

    run_id = "run-phase-38-#{System.unique_integer([:positive])}"

    {:ok, workflow_run} =
      WorkflowRun.create(%{
        project_id: project.id,
        run_id: run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Render Phase 38 surfaces"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_eight_live"}},
        initiating_actor: %{id: "owner-38", email: "phase38-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-12 15:00:00Z]
      })

    {:ok, workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :running,
        current_step: "review_memory",
        transitioned_at: ~U[2026-04-12 15:01:00Z]
      })

    {:ok, _workflow_run} =
      WorkflowRun.transition_status(workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-12 15:02:00Z]
      })

    {:ok, run} =
      JidoCode.Orchestration.Run.get_by_managed_repo_and_run_id(
        managed_repo.id,
        run_id,
        actor: Actor.operator_actor()
      )

    {:ok, evidence} =
      Evidence.create(
        %{
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          work_item_id: work_item.id,
          key: "phase_38_memory",
          evidence_type: "memory_graph_finding",
          summary: "Phase 38 should keep governed memory context visible.",
          evidence_details: %{"source" => "phase_thirty_eight_live"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase-38-run-#{run.id}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          work_item_id: work_item.id,
          decision: :defer,
          actor: %{"id" => "owner-38", "email" => "phase38-owner@example.com"},
          rationale: "Governed memory context should stay reviewable on current product surfaces.",
          decision_metadata: %{"source" => "phase_thirty_eight_live"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, revision_metadata} = MemoryGraph.current_revision_metadata(workspace_path)
    revision = revision_metadata.current_revision

    seed_repo_detail_memory!(
      managed_repo.id,
      workspace_path,
      revision,
      run_id,
      work_item.id
    )

    seed_run_memory_context!(
      managed_repo.id,
      workspace_path,
      revision,
      run_id,
      evidence.id,
      decision.id,
      work_item_id: work_item.id
    )

    {:ok, repo_view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)
    repo_rendered = render(repo_view)

    assert has_element?(repo_view, "#project-detail-memory-inspection")
    assert repo_rendered =~ "Governed context"
    assert repo_rendered =~ "Run #{run_id}"
    assert repo_rendered =~ "Work item #{work_item.id}"
    refute repo_rendered =~ "/artifact/"
    refute repo_rendered =~ "Evidence Artifact"

    {:ok, run_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{project.id}/runs/#{run_id}", on_error: :warn)

    run_rendered = render(run_view)

    assert has_element?(run_view, "#run-detail-memory-context")
    assert has_element?(run_view, "#run-detail-memory-1-governed-label", "Governed context")

    assert has_element?(
             run_view,
             "#run-detail-evidence-memory-#{evidence.id}-memory-1-governed-label",
             "Governed context"
           )

    assert run_rendered =~ "Open governed record"
    refute run_rendered =~ "/artifact/"
    refute run_rendered =~ "Evidence Artifact"

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)
    workbench_rendered = render(workbench_view)

    assert has_element?(workbench_view, "#workbench-project-memory-hint-#{managed_repo.id}")

    assert has_element?(
             workbench_view,
             "#workbench-project-memory-hint-badge-#{managed_repo.id}",
             "Memory graph ready"
           )

    assert workbench_rendered =~ "bounded recall and capture"
    refute workbench_rendered =~ "/artifact/"
  end

  test "38.3.1.2 invalidated and rebuild-required surfaces stay explainable through product-owned recovery",
       %{conn: _conn} do
    register_owner("phase38-recovery-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("phase38-recovery-owner@example.com", "owner-password-123")

    invalidated_workspace = create_workspace_path!("ExamplePhaseThirtyEightInvalidated")

    {:ok, invalidated_project} =
      Project.create(%{
        name: "phase-38-invalidated-run",
        github_full_name: "owner/phase-38-invalidated-run",
        default_branch: "main",
        settings: %{workspace: %{workspace_path: invalidated_workspace}}
      })

    {:ok, invalidated_repo} =
      ManagedRepo.get_by_legacy_project_id(invalidated_project.id, actor: Actor.operator_actor())

    {:ok, invalidated_work_item} =
      WorkItem.create(
        %{
          managed_repo_id: invalidated_repo.id,
          summary: "Recover invalidated run memory",
          status: :open,
          category: "review_follow_up"
        },
        actor: Actor.operator_actor()
      )

    invalidated_run_id = "run-phase-38-invalidated-#{System.unique_integer([:positive])}"

    {:ok, invalidated_workflow_run} =
      WorkflowRun.create(%{
        project_id: invalidated_project.id,
        run_id: invalidated_run_id,
        workflow_name: "implement_task",
        workflow_version: 2,
        trigger: %{source: "workflows", mode: "manual"},
        inputs: %{"task_summary" => "Recover invalidated memory context"},
        input_metadata: %{"task_summary" => %{required: true, source: "phase_thirty_eight_live"}},
        initiating_actor: %{id: "owner-38", email: "phase38-recovery-owner@example.com"},
        current_step: "queued",
        started_at: ~U[2026-04-12 16:00:00Z]
      })

    {:ok, invalidated_workflow_run} =
      WorkflowRun.transition_status(invalidated_workflow_run, %{
        to_status: :running,
        current_step: "review_memory",
        transitioned_at: ~U[2026-04-12 16:01:00Z]
      })

    {:ok, _invalidated_workflow_run} =
      WorkflowRun.transition_status(invalidated_workflow_run, %{
        to_status: :awaiting_approval,
        current_step: "approval_gate",
        transitioned_at: ~U[2026-04-12 16:02:00Z]
      })

    {:ok, invalidated_run} =
      JidoCode.Orchestration.Run.get_by_managed_repo_and_run_id(
        invalidated_repo.id,
        invalidated_run_id,
        actor: Actor.operator_actor()
      )

    {:ok, invalidated_evidence} =
      Evidence.create(
        %{
          run_id: invalidated_run.id,
          managed_repo_id: invalidated_repo.id,
          work_item_id: invalidated_work_item.id,
          key: "phase_38_invalidated_memory",
          evidence_type: "memory_graph_finding",
          summary: "Run memory recovery should stay product-owned.",
          evidence_details: %{"source" => "phase_thirty_eight_live"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, invalidated_decision} =
      Decision.create(
        %{
          decision_key: "phase-38-invalidated-run-#{invalidated_run.id}",
          run_id: invalidated_run.id,
          managed_repo_id: invalidated_repo.id,
          work_item_id: invalidated_work_item.id,
          decision: :approve,
          actor: %{"id" => "owner-38", "email" => "phase38-recovery-owner@example.com"},
          rationale: "Run detail should expose bounded recovery for invalidated memory state.",
          decision_metadata: %{"source" => "phase_thirty_eight_live"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, invalidated_revision_metadata} = MemoryGraph.current_revision_metadata(invalidated_workspace)

    seed_run_memory_context!(
      invalidated_repo.id,
      invalidated_workspace,
      invalidated_revision_metadata.current_revision,
      invalidated_run_id,
      invalidated_evidence.id,
      invalidated_decision.id,
      work_item_id: invalidated_work_item.id
    )

    assert {:ok, _invalidate_result} =
             AgentWorkspace.invalidate_memory_graph(
               invalidated_repo.id,
               invalidated_workspace,
               reason: :manual_invalidation
             )

    {:ok, invalidated_run_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{invalidated_project.id}/runs/#{invalidated_run_id}",
        on_error: :warn
      )

    assert has_element?(invalidated_run_view, "#run-detail-memory-context-notice")
    assert has_element?(invalidated_run_view, "#run-detail-memory-recover", "Validate memory graph")

    invalidated_run_view
    |> element("#run-detail-memory-recover")
    |> render_click()

    assert has_element?(
             invalidated_run_view,
             "#run-detail-memory-action-feedback-type",
             "memory_graph_recovered"
           )

    legacy_workspace = create_workspace_path!("ExamplePhaseThirtyEightLegacy")

    {:ok, legacy_project} =
      Project.create(%{
        name: "phase-38-legacy-repo",
        github_full_name: "owner/phase-38-legacy-repo",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => legacy_workspace,
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    {:ok, legacy_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project.id, actor: Actor.operator_actor())

    seed_legacy_rebuild_state!(legacy_repo.id, legacy_workspace, "phase-38-legacy-rebuild")

    {:ok, repo_view, _html} =
      live(recycle(authed_conn), ~p"/repos/#{legacy_project.id}", on_error: :warn)

    assert has_element?(repo_view, "#project-detail-memory-notice")
    assert render(repo_view) =~ "legacy governed artifact links"
    assert has_element?(repo_view, "#project-detail-memory-recover", "Recover memory graph")

    repo_view
    |> element("#project-detail-memory-recover")
    |> render_click()

    assert has_element?(repo_view, "#project-detail-memory-feedback-type", "memory_graph_recovered")

    {:ok, workbench_view, _html} = live(recycle(authed_conn), ~p"/workbench", on_error: :warn)

    assert has_element?(workbench_view, "#workbench-project-memory-hint-#{legacy_repo.id}")

    assert has_element?(
             workbench_view,
             "#workbench-project-memory-hint-badge-#{legacy_repo.id}",
             "Memory graph failed"
           )

    assert has_element?(
             workbench_view,
             "#workbench-project-memory-hint-detail-#{legacy_repo.id}",
             "legacy governed artifact links"
           )

    assert has_element?(
             workbench_view,
             "#workbench-project-memory-hint-recovery-#{legacy_repo.id}[href='/repos/#{legacy_repo.id}']",
             "Open repo detail to review governed memory context and recover memory graph."
           )
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_thirty_eight_live_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseThirtyEightLive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_thirty_eight_live, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_thirty_eight_live.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp seed_repo_detail_memory!(managed_repo_id, workspace_path, revision, run_id, work_item_id) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "repo-detail-phase-38-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight-live",
                 workflow: :plan,
                 work_item_id: work_item_id,
                 goal: "Seed repo detail memory context"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Repo detail should preserve governed memory labels.",
                 rationale: "Phase 38 should keep governed navigation legible without generic artifact contracts.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyEightLive"},
                 governed_context: %{run_id: run_id, work_item_id: work_item_id},
                 classification: %{
                   source: "phase_thirty_eight_live",
                   reason: "Repo detail coverage needs durable governed memory context."
                 }
               ),
               revision: revision
             )
  end

  defp seed_run_memory_context!(managed_repo_id, workspace_path, revision, run_id, evidence_id, decision_id, opts) do
    work_item_id = Keyword.fetch!(opts, :work_item_id)

    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "run-detail-phase-38-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 goal: "Seed run detail memory context"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _review_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.review(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Governed run memory context should stay reviewable.",
                 anchors: %{module_name: "ExamplePhaseThirtyEightLive"},
                 governed_context: %{run_id: run_id, work_item_id: work_item_id, decision_id: decision_id}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.known_issue(
                 session_id: session_id,
                 actor_id: "system:phase-thirty-eight-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Run detail should show governed memory context.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseThirtyEightLive"},
                 governed_context: %{
                   run_id: run_id,
                   work_item_id: work_item_id,
                   evidence_id: evidence_id,
                   decision_id: decision_id
                 },
                 classification: %{
                   source: "phase_thirty_eight_live",
                   reason: "Run detail coverage needs bounded governed memory context."
                 }
               ),
               revision: revision
             )
  end

  defp seed_legacy_rebuild_state!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    inject_legacy_governed_artifact!(managed_repo_id, workspace_path)

    assert {:ok, _validate_result} =
             AgentWorkspace.validate_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )
  end

  defp inject_legacy_governed_artifact!(managed_repo_id, workspace_path) do
    store_path = MemoryGraph.graph_store_path(workspace_path)
    legacy_memory_iri = RDF.iri("#{MemoryGraph.base_iri(managed_repo_id)}fact/legacy-governed-artifact")
    legacy_artifact_iri = MemoryGraph.artifact_iri(managed_repo_id, "run_id/run-legacy")

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      graph =
        RDF.Graph.new([
          {legacy_memory_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Fact")},
          {legacy_memory_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#Memory")},
          {legacy_artifact_iri, RDF.type(), RDF.iri("https://jido.run/ontology/memory#EvidenceArtifact")},
          {legacy_memory_iri, RDF.iri("https://jido.run/ontology/memory#supportedBy"), legacy_artifact_iri}
        ])

      {:ok, _triple_count} =
        TripleStore.load_graph(store, graph, graph: MemoryGraph.memory_named_graph_resource())
    after
      :ok = TripleStore.close(store)
    end
  end
end
