defmodule JidoCodeWeb.PhaseFiftyFiveIntegrationTest do
  # covers: architecture.memory_graph_workflow_and_operator_expansion.governed_surfaces_host_memory_context
  # covers: architecture.memory_graph_workflow_and_operator_expansion.operator_memory_actions_use_product_owned_boundaries
  # covers: architecture.memory_graph_workflow_and_operator_expansion.cross_graph_navigation_connects_memory_code_and_governed_history
  # covers: architecture.memory_graph_workflow_and_operator_expansion.memory_promotions_create_governed_follow_up
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.operator_memory_actions_are_available_from_canonical_surfaces
  # covers: architecture.memory_graph_surface_rollout_and_governance_actions.canonical_routes_remain_product_and_governed
  # covers: package.jido_code.spec_led_workspace
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.Actor
  alias JidoCode.Governance.{Decision, Evidence}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.Operations.{Assessment, Event, WorkItem}

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
    end)

    :ok
  end

  test "55.6.2.1 canonical work-item surfaces host bounded memory context and shared actions", %{
    conn: _conn
  } do
    {authed_conn, _session_token} = authenticate_phase_owner!("work-item")
    fixture = seed_governed_memory_surface_fixture!("work-item")

    {:ok, view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{fixture.route_id}/work-items/#{fixture.work_item.id}",
        on_error: :warn
      )

    assert has_element?(view, "#work-item-detail-title", fixture.work_item.summary)

    assert has_element?(
             view,
             "#work-item-detail-run-route-1[href=\"/repos/#{fixture.route_id}/runs/#{fixture.run.run_id}\"]",
             "Open run"
           )

    assert has_element?(view, "#work-item-detail-memory-context-state", "ready")

    assert has_element?(
             view,
             "#work-item-detail-memory-follow-up-preview-route[href=\"/repos/#{fixture.route_id}/work-items/#{fixture.work_item.id}#work-item-detail-memory-context\"]"
           )

    assert has_element?(
             view,
             "#work-item-detail-memory-supersede-#{fixture.decision.id}",
             "Supersede with latest decision"
           )

    render_click(element(view, "#work-item-detail-memory-validate-1"))

    assert has_element?(
             view,
             "#work-item-detail-memory-action-feedback",
             "Recorded durable memory validation"
           )
  end

  test "55.6.2.2 canonical evidence and decision surfaces keep navigation and actions product-owned", %{
    conn: _conn
  } do
    {authed_conn, _session_token} = authenticate_phase_owner!("evidence-decision")
    fixture = seed_governed_memory_surface_fixture!("evidence-decision")

    {:ok, evidence_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{fixture.route_id}/evidence/#{fixture.evidence.id}",
        on_error: :warn
      )

    assert has_element?(evidence_view, "#evidence-detail-title", fixture.evidence.summary)

    assert has_element?(
             evidence_view,
             "#evidence-detail-run-route[href=\"/repos/#{fixture.route_id}/runs/#{fixture.run.run_id}\"]",
             "Open run"
           )

    assert has_element?(
             evidence_view,
             "#evidence-detail-work-item-route[href=\"/repos/#{fixture.route_id}/work-items/#{fixture.work_item.id}\"]",
             "Open work item"
           )

    assert has_element?(
             evidence_view,
             "#evidence-detail-related-decision-route-1[href=\"/repos/#{fixture.route_id}/decisions/#{fixture.decision.id}\"]",
             "Open decision"
           )

    render_click(element(evidence_view, "#evidence-detail-memory-promote-1"))

    assert has_element?(
             evidence_view,
             "#evidence-detail-memory-action-feedback",
             "Created governed follow-up work item"
           )

    {:ok, decision_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{fixture.route_id}/decisions/#{fixture.decision.id}",
        on_error: :warn
      )

    assert has_element?(decision_view, "#decision-detail-title", fixture.decision.decision_key)

    assert has_element?(
             decision_view,
             "#decision-detail-run-route[href=\"/repos/#{fixture.route_id}/runs/#{fixture.run.run_id}\"]",
             "Open run"
           )

    assert has_element?(
             decision_view,
             "#decision-detail-work-item-route[href=\"/repos/#{fixture.route_id}/work-items/#{fixture.work_item.id}\"]",
             "Open work item"
           )

    assert has_element?(
             decision_view,
             "#decision-detail-related-evidence-route-1[href=\"/repos/#{fixture.route_id}/evidence/#{fixture.evidence.id}\"]",
             "Open evidence"
           )

    render_click(element(decision_view, "#decision-detail-memory-supersede"))

    assert has_element?(
             decision_view,
             "#decision-detail-memory-action-feedback",
             "Superseded durable decision memory with the latest governed decision"
           )
  end

  test "55.6.2.3 canonical governed memory routes and current-truth docs stay aligned", %{
    conn: _conn
  } do
    {authed_conn, _session_token} = authenticate_phase_owner!("missing")
    %{route_id: route_id} = seed_governed_memory_surface_fixture!("missing")

    {:ok, work_item_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{route_id}/work-items/#{Ecto.UUID.generate()}",
        on_error: :warn
      )

    {:ok, evidence_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{route_id}/evidence/#{Ecto.UUID.generate()}",
        on_error: :warn
      )

    {:ok, decision_view, _html} =
      live(
        recycle(authed_conn),
        ~p"/repos/#{route_id}/decisions/#{Ecto.UUID.generate()}",
        on_error: :warn
      )

    assert has_element?(work_item_view, "#work-item-detail-missing-title", "Work item not found")
    assert has_element?(evidence_view, "#evidence-detail-missing-title", "Evidence not found")
    assert has_element?(decision_view, "#decision-detail-missing-title", "Decision not found")

    phase_plan = repo_file!(".spec/planning/phase-55-memory-rollout-and-governed-surfaces.md")
    phase_fifty_four = repo_file!("test/jido_code_web/live/phase_fifty_four_integration_test.exs")
    router = repo_file!("lib/jido_code_web/router.ex")

    assert phase_plan =~ "[x] 55.6 Section - Phase 55 Integration Tests"
    assert phase_plan =~ "[x] 55.6.2 Task - Add governed-surface LiveView and integration coverage"

    assert repo_file!(".spec/specs/memory_graph_workflow_and_operator_expansion.spec.md") =~
             "status: active"

    assert repo_file!(".spec/specs/memory_graph_surface_rollout_and_governance_actions.spec.md") =~
             "status: active"

    assert phase_fifty_four =~ "assert proposed_specs() == []"
    assert router =~ "live \"/repos/:id/work-items/:work_item_id\", WorkItemDetailLive"
    assert router =~ "live \"/repos/:id/evidence/:evidence_id\", EvidenceDetailLive"
    assert router =~ "live \"/repos/:id/decisions/:decision_id\", DecisionDetailLive"

    assert proposed_specs() == []
  end

  defp authenticate_phase_owner!(suffix) do
    email = "phase55-#{suffix}-#{System.unique_integer([:positive])}@example.com"
    password = "owner-password-123"

    register_owner(email, password)
    authenticate_owner_conn(email, password)
  end

  defp seed_governed_memory_surface_fixture!(suffix) do
    workspace_path = create_memory_workspace_path!(suffix)
    unique = System.unique_integer([:positive])

    %{managed_repo: managed_repo, route_id: route_id} =
      provision_managed_repo!(%{
        name: "repo-phase55-#{suffix}-#{unique}",
        github_full_name: "owner/repo-phase55-#{suffix}-#{unique}",
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

    {:ok, event} =
      Event.create(
        %{
          managed_repo_id: managed_repo.id,
          category: "memory_surface_review",
          summary: "Phase 55 needs governed memory surface coverage.",
          correlation_key: "phase55-memory-surface-#{unique}",
          payload: %{},
          source_metadata: %{"source" => "phase_fifty_five_live_test"},
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    {:ok, assessment} =
      Assessment.create(
        %{
          managed_repo_id: managed_repo.id,
          event_id: event.id,
          category: "memory_surface_review",
          summary: "Assess canonical governed memory route readiness.",
          priority: :medium,
          urgency: :medium,
          recommended_action: "review_memory_context",
          rationale: "Phase 55 should finish the governed memory route family.",
          inputs: %{},
          assessment_metadata: %{"source" => "phase_fifty_five_live_test"},
          assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    {:ok, work_item} =
      WorkItem.create(
        %{
          managed_repo_id: managed_repo.id,
          assessment_id: assessment.id,
          event_id: event.id,
          category: "memory_review",
          status: :open,
          priority: :medium,
          recommended_action: "review_memory_context",
          summary: "Review bounded memory context on canonical governed routes.",
          dedup_key: "phase55-work-item-#{unique}",
          initiating_actor: %{"id" => "owner-55", "email" => "phase55@example.com"},
          work_metadata: %{},
          audit_log: [],
          opened_at: DateTime.utc_now() |> DateTime.truncate(:microsecond),
          last_assessed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
        },
        actor: Actor.operator_actor()
      )

    run =
      create_governed_run!(route_id, %{
        run_id: "run-phase55-#{suffix}-#{unique}",
        workflow_name: "implement_task",
        workflow_version: 2,
        status: :awaiting_approval,
        current_step: "approval_gate",
        current_stage: "approval_gate",
        work_item_id: work_item.id,
        started_at: ~U[2026-04-19 14:00:00Z]
      })

    {:ok, evidence} =
      Evidence.create(
        %{
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          work_item_id: work_item.id,
          key: "phase55_memory_context",
          evidence_type: "memory_graph_finding",
          summary: "Evidence memory context should stay on canonical governed routes.",
          evidence_details: %{"source" => "phase_fifty_five_live_test"},
          source: "memory_graph",
          recorded_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    {:ok, decision} =
      Decision.create(
        %{
          decision_key: "phase55-decision-#{unique}",
          run_id: run.id,
          managed_repo_id: managed_repo.id,
          work_item_id: work_item.id,
          evidence_ids: [evidence.id],
          decision: :approve,
          actor: %{"id" => "owner-55", "email" => "phase55@example.com"},
          rationale: "Canonical governed memory routes are ready for rollout.",
          decision_metadata: %{"source" => "phase_fifty_five_live_test"},
          decided_at: DateTime.utc_now()
        },
        actor: Actor.operator_actor()
      )

    revision = "phase55-live-#{unique}"

    seed_governed_surface_memory!(
      managed_repo.id,
      workspace_path,
      revision,
      run.run_id,
      work_item.id,
      evidence.id,
      decision.id
    )

    %{
      managed_repo: managed_repo,
      route_id: route_id,
      workspace_path: workspace_path,
      run: run,
      work_item: work_item,
      evidence: evidence,
      decision: decision
    }
  end

  defp create_memory_workspace_path!(suffix) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_fifty_five_live_#{suffix}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseFiftyFiveLive.MixProject do
        use Mix.Project

        def project do
          [app: :phase_fifty_five_live, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_phase_fifty_five_live.ex"),
      """
      defmodule ExamplePhaseFiftyFiveLive do
        def review(name) when is_binary(name), do: "review " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp seed_governed_surface_memory!(
         managed_repo_id,
         workspace_path,
         revision,
         run_id,
         work_item_id,
         evidence_id,
         decision_id
       ) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "phase55-memory-surface-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:phase-fifty-five-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 goal: "Seed canonical governed memory route coverage"
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
                 actor_id: "system:phase-fifty-five-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Canonical governed surfaces share bounded memory context.",
                 anchors: %{module_name: "ExamplePhaseFiftyFiveLive"},
                 governed_context: %{
                   run_id: run_id,
                   work_item_id: work_item_id,
                   evidence_id: evidence_id,
                   decision_id: decision_id
                 }
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
                 actor_id: "system:phase-fifty-five-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Canonical governed routes should keep durable memory explainable.",
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseFiftyFiveLive"},
                 governed_context: %{
                   run_id: run_id,
                   work_item_id: work_item_id,
                   evidence_id: evidence_id,
                   decision_id: decision_id
                 },
                 classification: %{
                   source: "phase_fifty_five_live_test",
                   reason: "Phase 55 needs bounded memory on work-item, evidence, and decision routes."
                 }
               ),
               revision: revision
             )

    assert {:ok, _decision_memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:phase-fifty-five-live",
                 workflow: :review,
                 work_item_id: work_item_id,
                 content: "Earlier governed decisions should remain reviewable on canonical routes.",
                 rationale: "Shared memory actions need durable decision memory for supersession coverage.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExamplePhaseFiftyFiveLive"},
                 governed_context: %{
                   run_id: run_id,
                   work_item_id: work_item_id,
                   evidence_id: evidence_id,
                   decision_id: decision_id
                 },
                 classification: %{
                   source: "phase_fifty_five_live_test",
                   reason: "Phase 55 supersession coverage needs durable decision memory."
                 }
               ),
               revision: revision
             )
  end

  defp proposed_specs do
    repo_root()
    |> Path.join(".spec/specs/*.spec.md")
    |> Path.wildcard()
    |> Enum.filter(&(File.read!(&1) =~ "status: proposed"))
    |> Enum.map(&Path.basename/1)
    |> Enum.sort()
  end

  defp repo_file!(path) do
    Path.expand(path, repo_root()) |> File.read!()
  end

  defp repo_root do
    Path.expand("../../..", __DIR__)
  end
end
