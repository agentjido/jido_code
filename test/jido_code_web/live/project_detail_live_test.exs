defmodule JidoCodeWeb.ProjectDetailLiveTest do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  use JidoCodeWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias JidoCode.AgentWorkspace
  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope}
  alias JidoCode.Projects.Project

  setup do
    original_fix_workflow_launcher =
      Application.get_env(:jido_code, :workbench_fix_workflow_launcher, :__missing__)

    original_issue_triage_workflow_launcher =
      Application.get_env(:jido_code, :workbench_issue_triage_workflow_launcher, :__missing__)

    original_frontend_override =
      Application.get_env(:jido_code, :frontend_assets_override, :__missing__)

    original_source_code_graph_enabled =
      Application.get_env(:jido_code, :source_code_graph_enabled, false)

    original_memory_graph_enabled =
      Application.get_env(:jido_code, :memory_graph_enabled, false)

    on_exit(fn ->
      restore_env(:workbench_fix_workflow_launcher, original_fix_workflow_launcher)

      restore_env(
        :workbench_issue_triage_workflow_launcher,
        original_issue_triage_workflow_launcher
      )

      restore_env(:frontend_assets_override, original_frontend_override)
      Application.put_env(:jido_code, :source_code_graph_enabled, original_source_code_graph_enabled)
      Application.put_env(:jido_code, :memory_graph_enabled, original_memory_graph_enabled)
    end)

    :ok
  end

  test "launches supported builtin workflows from /repos/:id with defaults and repo-detail traceability",
       %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-ready",
        github_full_name: "owner/repo-ready",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    project_id = project.id
    managed_repo_id = managed_repo_route_id!(project_id)
    launch_requests = start_supervised!({Agent, fn -> [] end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn kickoff_request ->
      Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
      {:ok, %{run_id: "run-fix-123"}}
    end)

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn kickoff_request ->
        Agent.update(launch_requests, fn requests -> [kickoff_request | requests] end)
        {:ok, %{run_id: "run-triage-456"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project_id}", on_error: :warn)

    assert has_element?(view, "#project-detail-workflow-controls")

    assert has_element?(
             view,
             "#project-detail-workflow-name-fix-failing-tests",
             "fix_failing_tests"
           )

    assert has_element?(view, "#project-detail-workflow-name-issue-triage", "issue_triage")
    assert has_element?(view, "#project-detail-launch-fix-failing-tests")
    assert has_element?(view, "#project-detail-launch-issue-triage")
    refute has_element?(view, "#project-detail-launch-disabled-guidance")

    view
    |> element("#project-detail-launch-fix-failing-tests")
    |> render_click()

    assert has_element?(view, "#project-detail-launch-fix-failing-tests-run-id", "run-fix-123")

    assert has_element?(
             view,
             "#project-detail-launch-fix-failing-tests-run-link[href='/repos/#{managed_repo_id}/runs/run-fix-123']"
           )

    view
    |> element("#project-detail-launch-issue-triage")
    |> render_click()

    assert has_element?(view, "#project-detail-launch-issue-triage-run-id", "run-triage-456")

    assert has_element?(
             view,
             "#project-detail-launch-issue-triage-run-link[href='/repos/#{managed_repo_id}/runs/run-triage-456']"
           )

    recorded_requests = launch_requests |> Agent.get(&Enum.reverse(&1))
    project_route = "/repos/#{managed_repo_id}"

    assert [
             %{
               workflow_name: "fix_failing_tests",
               project_id: ^managed_repo_id,
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-ready"
               },
               trigger: %{
                 source: "project_detail",
                 mode: "manual",
                 source_row: %{
                   route: ^project_route,
                   project_id: ^managed_repo_id
                 }
               },
               context_item: %{type: :issue},
               initiating_actor: %{id: fix_actor_id}
             },
             %{
               workflow_name: "issue_triage",
               project_id: ^managed_repo_id,
               project_defaults: %{
                 default_branch: "main",
                 github_full_name: "owner/repo-ready"
               },
               trigger: %{
                 source: "project_detail",
                 mode: "manual",
                 source_row: %{
                   route: ^project_route,
                   project_id: ^managed_repo_id
                 }
               },
               context_item: %{type: :issue},
               initiating_actor: %{id: triage_actor_id}
             }
           ] = recorded_requests

    assert is_binary(fix_actor_id)
    assert fix_actor_id != ""
    assert is_binary(triage_actor_id)
    assert triage_actor_id != ""

    assert Enum.all?(recorded_requests, fn kickoff_request ->
             Map.has_key?(kickoff_request.initiating_actor, :email)
           end)
  end

  test "disables project-detail launch controls with remediation when execution prerequisites are blocked",
       %{
         conn: _conn
       } do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-blocked",
        github_full_name: "owner/repo-blocked",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "clone_status" => "error",
            "last_error_type" => "baseline_sync_unavailable",
            "retry_instructions" => "Retry step 7 after baseline sync is repaired."
          }
        }
      })

    launcher_invocations = start_supervised!({Agent, fn -> %{fix: 0, triage: 0} end})

    Application.put_env(:jido_code, :workbench_fix_workflow_launcher, fn _kickoff_request ->
      Agent.update(launcher_invocations, fn state -> Map.update!(state, :fix, &(&1 + 1)) end)
      {:ok, %{run_id: "unexpected-fix-run"}}
    end)

    Application.put_env(
      :jido_code,
      :workbench_issue_triage_workflow_launcher,
      fn _kickoff_request ->
        Agent.update(launcher_invocations, fn state -> Map.update!(state, :triage, &(&1 + 1)) end)
        {:ok, %{run_id: "unexpected-triage-run"}}
      end
    )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-launch-disabled-guidance")

    assert has_element?(
             view,
             "#project-detail-launch-disabled-fix-failing-tests[aria-disabled='true']",
             "Launch workflow"
           )

    assert has_element?(
             view,
             "#project-detail-launch-disabled-issue-triage[aria-disabled='true']",
             "Launch workflow"
           )

    assert has_element?(view, "#project-detail-launch-disabled-type", "baseline_sync_unavailable")

    assert has_element?(
             view,
             "#project-detail-launch-disabled-detail",
             "clone or baseline sync failed"
           )

    assert has_element?(view, "#project-detail-launch-disabled-remediation", "Retry step 7")

    refute has_element?(view, "#project-detail-launch-fix-failing-tests")
    refute has_element?(view, "#project-detail-launch-issue-triage")

    assert %{fix: 0, triage: 0} = Agent.get(launcher_invocations, & &1)
  end

  test "renders project overview without conversation controls", %{conn: _conn} do
    register_owner("owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-overview-ui",
        github_full_name: "owner/repo-overview-ui",
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

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    vue = assert_vue_component(view, "ProjectDetailOverviewWidget", id: "project-detail-overview-widget")

    assert vue.props["githubFullName"] == "owner/repo-overview-ui"
    assert vue.props["launchReady"] == true
    assert length(vue.props["workflowCards"]) == 2

    refute has_element?(view, "#project-detail-conversation-panel")
    refute render(view) =~ "Start conversation"
  end

  test "hosts bounded semantic inspection inside the managed repo detail route", %{conn: _conn} do
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    register_owner("semantic-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("semantic-owner@example.com", "owner-password-123")

    workspace_path = create_semantic_workspace_path!("ProjectDetailSemantic.Alpha")

    {:ok, project} =
      Project.create(%{
        name: "repo-semantic-ui",
        github_full_name: "owner/repo-semantic-ui",
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

    managed_repo_id = managed_repo_route_id!(project.id)

    assert {:ok, _load_result} =
             AgentWorkspace.load_source_code_graph(
               managed_repo_id,
               workspace_path,
               revision: "phase-25-ready"
             )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-semantic-inspection")
    refute has_element?(view, "#project-detail-semantic-notice")

    vue =
      assert_vue_component(
        view,
        "ProjectDetailSemanticExplorerWidget",
        id: "project-detail-semantic-explorer-widget"
      )

    assert vue.props["managedRepoId"] == managed_repo_id
    assert vue.props["graph"]["state"] == "ready"
    assert Enum.any?(vue.props["summaryCards"], &(&1["id"] == "modules"))
    assert Enum.any?(vue.props["modules"], &(&1["moduleName"] == "ProjectDetailSemantic.Alpha"))

    assert_vue_handler(
      view,
      "requestRecovery",
      "recover_semantic_graph",
      id: "project-detail-semantic-explorer-widget"
    )
  end

  test "shows stale semantic status and lets operators recover from repo detail", %{conn: _conn} do
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    register_owner("semantic-stale-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("semantic-stale-owner@example.com", "owner-password-123")

    workspace_path = create_semantic_workspace_path!("ProjectDetailSemantic.Stale")

    {:ok, project} =
      Project.create(%{
        name: "repo-semantic-stale",
        github_full_name: "owner/repo-semantic-stale",
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

    managed_repo_id = managed_repo_route_id!(project.id)

    assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

    rewrite_semantic_workspace_module!(workspace_path, "ProjectDetailSemantic.Refreshed")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-semantic-notice")
    assert has_element?(view, "#project-detail-semantic-notice-type", "source_code_graph_stale")
    assert has_element?(view, "#project-detail-semantic-recover", "Refresh semantic graph")

    view
    |> element("#project-detail-semantic-recover")
    |> render_click()

    assert has_element?(view, "#project-detail-semantic-feedback-type", "semantic_graph_recovered")
    refute has_element?(view, "#project-detail-semantic-notice")

    vue =
      assert_vue_component(
        view,
        "ProjectDetailSemanticExplorerWidget",
        id: "project-detail-semantic-explorer-widget"
      )

    assert vue.props["graph"]["state"] == "ready"
  end

  test "falls back to server-rendered semantic inspection when richer delivery degrades", %{conn: _conn} do
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    register_owner("semantic-fallback-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("semantic-fallback-owner@example.com", "owner-password-123")

    Application.put_env(:jido_code, :frontend_assets_override, %{
      mode: :fallback,
      reason: :asset_manifest_unavailable
    })

    workspace_path = create_semantic_workspace_path!("ProjectDetailSemantic.Fallback")

    {:ok, project} =
      Project.create(%{
        name: "repo-semantic-fallback",
        github_full_name: "owner/repo-semantic-fallback",
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

    managed_repo_id = managed_repo_route_id!(project.id)

    assert {:ok, _load_result} =
             AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(
             view,
             "#project-detail-semantic-explorer-widget-fallback",
             "Interactive semantic explorer temporarily unavailable"
           )

    assert has_element?(
             view,
             "#project-detail-semantic-explorer-widget-fallback",
             "server-rendered semantic summary"
           )

    assert has_element?(view, "#project-detail-semantic-fallback")
    assert has_element?(view, "#project-detail-semantic-fallback-modules")
    assert has_element?(view, "#project-detail-semantic-fallback-impact-list")
  end

  test "hosts bounded memory and provenance inspection inside the managed repo detail route", %{conn: _conn} do
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    register_owner("memory-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("memory-owner@example.com", "owner-password-123")

    workspace_path = create_semantic_workspace_path!("ProjectDetailMemory.Alpha")

    {:ok, project} =
      Project.create(%{
        name: "repo-memory-ui",
        github_full_name: "owner/repo-memory-ui",
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

    managed_repo_id = managed_repo_route_id!(project.id)
    seed_memory_graph!(managed_repo_id, workspace_path, "phase-32-repo-detail")

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-memory-inspection")
    assert has_element?(view, "#project-detail-memory-summary-memories")
    assert has_element?(view, "#project-detail-memory-summary-provenance")
    assert has_element?(view, "#project-detail-memory-list")
    assert has_element?(view, "#project-detail-provenance-list")
    assert has_element?(view, "#project-detail-memory-summary-memories")
  end

  test "surfaces stale memory inspection with recovery on repo detail", %{conn: _conn} do
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    register_owner("memory-stale-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("memory-stale-owner@example.com", "owner-password-123")

    workspace_path = create_semantic_workspace_path!("ProjectDetailMemory.Stale")

    {:ok, project} =
      Project.create(%{
        name: "repo-memory-stale",
        github_full_name: "owner/repo-memory-stale",
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

    managed_repo_id = managed_repo_route_id!(project.id)
    seed_memory_graph!(managed_repo_id, workspace_path, "phase-32-repo-stale")

    assert {:ok, _invalidate_result} =
             AgentWorkspace.invalidate_memory_graph(
               managed_repo_id,
               workspace_path,
               reason: :manual_invalidation
             )

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-memory-notice")
    assert has_element?(view, "#project-detail-memory-recover", "Validate memory graph")

    view
    |> element("#project-detail-memory-recover")
    |> render_click()

    assert has_element?(view, "#project-detail-memory-feedback-type", "memory_graph_recovered")
  end

  defp create_workspace_path! do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido-code-project-workspace-#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end

  defp managed_repo_route_id!(legacy_project_id) do
    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(legacy_project_id, actor: Actor.operator_actor())

    managed_repo.id
  end

  defp create_semantic_workspace_path!(module_name) do
    workspace_path = create_workspace_path!()
    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule ProjectDetailSemantic.MixProject do
        use Mix.Project

        def project do
          [app: :project_detail_semantic, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_semantic_workspace_module!(workspace_path, module_name)
    workspace_path
  end

  defp rewrite_semantic_workspace_module!(workspace_path, module_name) do
    module_basename =
      module_name
      |> String.split(".")
      |> List.last()
      |> Macro.underscore()

    File.write!(
      Path.join(workspace_path, "lib/#{module_basename}.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
    |> Path.join("lib/*.ex")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "#{module_basename}.ex"))
    |> Enum.each(&File.rm!/1)
  end

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path, revision: revision)

    session_id = "detail-session-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:project-detail-memory",
                 workflow: :plan,
                 work_item_id: "work-32",
                 goal: "Seed project detail memory inspection"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, _plan_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.plan(
                 session_id: session_id,
                 actor_id: "system:project-detail-memory",
                 workflow: :plan,
                 work_item_id: "work-32",
                 content: "Generated a bounded plan artifact for the repository.",
                 anchors: %{module_name: "ExampleWorkspace"}
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
                 actor_id: "system:project-detail-memory",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Repository decisions should keep ExampleWorkspace.greet/1 stable.",
                 rationale: "Greeting behavior is used as a stable onboarding example.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExampleWorkspace"},
                 governed_context: %{run_id: "run-32", work_item_id: "work-32"},
                 classification: %{
                   source: "project_detail_test",
                   reason: "Repo detail memory inspection needs durable decision history."
                 }
               ),
               revision: revision
             )
  end
end
