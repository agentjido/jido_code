defmodule JidoCodeWeb.ProjectDetailLiveTest do
  # covers: architecture.frontend_stack.adoption_is_incremental_per_surface
  # covers: architecture.frontend_stack.server_authored_props_streams_and_events
  # covers: architecture.source_code_graph_product_adoption.managed_repo_routes_host_semantic_inspection
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.conversation_orchestration.ui_delivery_is_event_driven_and_reconnectable
  # covers: architecture.conversation_orchestration.degraded_mode_falls_back_to_persisted_state
  # covers: architecture.conversation_orchestration.managed_repo_routes_host_repo_conversations
  # covers: architecture.conversation_orchestration.operator_surfaces_show_conversation_work_item_linkage
  # covers: architecture.conversation_orchestration.real_llm_turn_execution_replaces_surface_simulation
  # covers: architecture.conversation_orchestration.llm_readiness_and_failure_states_are_explicit
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

  test "renders project overview with a repo conversation entrypoint", %{conn: _conn} do
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

    assert has_element?(view, "#project-detail-conversation-panel")
    assert has_element?(view, "#project-detail-conversation-open", "Open repo conversation")
    refute render(view) =~ "Start conversation"
  end

  test "hosts repo conversation interaction inside the managed repo detail route", %{conn: _conn} do
    register_owner("conversation-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("conversation-owner@example.com", "owner-password-123")

    workspace_path = create_workspace_path!()

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-ui",
        github_full_name: "owner/repo-conversation-ui",
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

    on_exit(fn ->
      case AgentWorkspace.latest_repo_conversation(managed_repo_id, actor: Actor.operator_actor()) do
        {:ok, %{id: conversation_id}} ->
          case AgentWorkspace.stop_conversation(conversation_id) do
            :ok -> :ok
            {:error, _reason} -> :ok
          end

        _other -> :ok
      end
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    view
    |> element("#project-detail-conversation-open")
    |> render_click()

    assert has_element?(view, "#project-detail-conversation-id")
    assert has_element?(view, "#project-detail-conversation-status", "active")

    conversation_id = latest_repo_conversation_id!(managed_repo_id)

    html =
      view
      |> form("#project-detail-conversation-form", %{
        "input" => "Inspect the repo detail conversation flow."
      })
      |> render_submit()

    assert html =~ "Inspect the repo detail conversation flow."
    assert has_element?(view, "#project-detail-conversation-events")

    _html =
      view
      |> form("#project-detail-conversation-form", %{
        "input" => "Clarify which file needs input."
      })
      |> render_submit()

    assert_eventually(fn ->
      has_element?(view, "#project-detail-conversation-pending-clarification")
    end)

    _html =
      view
      |> form("#project-detail-conversation-form", %{
        "input" => "lib/jido_code_web/live/project_detail_live.ex"
      })
      |> render_submit()

    assert_eventually(fn ->
      rendered = render(view)

      rendered =~ "deterministic explainer response" and
        rendered =~ "Queue review operator request work for the managed repository." and
        rendered =~ "canonical WorkItem scope" and
        rendered =~ "lib/jido_code_web/live/project_detail_live.ex" and
        has_element?(view, "#project-detail-conversation-work-resolution", "created") and
        has_element?(view, "#project-detail-conversation-governed-work") and
        has_element?(view, "#project-detail-conversation-governed-work-status", "open") and
        has_element?(view, "#project-detail-conversation-open-workbench", "Open in Workbench") and
        not has_element?(view, "#project-detail-conversation-pending-clarification")
    end)

    assert_conversation_settled!(conversation_id)
    assert :ok = AgentWorkspace.stop_conversation(conversation_id)
  end

  test "surfaces explicit conversation runtime readiness failures on the repo detail route", %{
    conn: _conn
  } do
    register_owner("conversation-runtime-owner@example.com", "owner-password-123")

    {authed_conn, _session_token} =
      authenticate_owner_conn("conversation-runtime-owner@example.com", "owner-password-123")

    {:ok, project} =
      Project.create(%{
        name: "repo-conversation-runtime-missing-workspace",
        github_full_name: "owner/repo-conversation-runtime-missing-workspace",
        default_branch: "main",
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "clone_status" => "ready",
            "workspace_initialized" => true,
            "baseline_synced" => true
          }
        }
      })

    managed_repo_id = managed_repo_route_id!(project.id)

    on_exit(fn ->
      case AgentWorkspace.latest_repo_conversation(managed_repo_id, actor: Actor.operator_actor()) do
        {:ok, %{id: conversation_id}} ->
          case AgentWorkspace.stop_conversation(conversation_id) do
            :ok -> :ok
            {:error, _reason} -> :ok
          end

        _other -> :ok
      end
    end)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    view
    |> element("#project-detail-conversation-open")
    |> render_click()

    conversation_id = latest_repo_conversation_id!(managed_repo_id)

    _html =
      view
      |> form("#project-detail-conversation-form", %{
        "input" => "Explain why this repository is ready."
      })
      |> render_submit()

    assert_eventually(fn ->
      rendered = render(view)

      rendered =~ "Repository workspace path is missing for real conversation runtime." and
        not String.contains?(rendered, "deterministic explainer response")
    end)

    assert_conversation_settled!(conversation_id)
    assert :ok = AgentWorkspace.stop_conversation(conversation_id)
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
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

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

    seed_memory_graph!(
      managed_repo_id,
      workspace_path,
      "phase-32-repo-detail",
      module_name: "ProjectDetailMemory.Alpha"
    )

    assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

    {:ok, view, _html} = live(recycle(authed_conn), ~p"/repos/#{project.id}", on_error: :warn)

    assert has_element?(view, "#project-detail-memory-inspection")
    assert has_element?(view, "#project-detail-memory-summary-memories")
    assert has_element?(view, "#project-detail-memory-summary-provenance")
    assert has_element?(view, "#project-detail-memory-list")
    assert has_element?(view, "#project-detail-provenance-list")
    assert has_element?(view, "#project-detail-memory-summary-memories")
    assert render(view) =~ "Governed context"
    assert render(view) =~ "Work item work-32"
    assert render(view) =~ "ProjectDetailMemory.Alpha"
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

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision, opts \\ []) do
    module_name = Keyword.get(opts, :module_name, "ExampleWorkspace")

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
                 anchors: %{module_name: module_name}
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
                 content: "Repository decisions should keep #{module_name}.greet/1 stable.",
                 rationale: "Greeting behavior is used as a stable onboarding example.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: module_name},
                 governed_context: %{run_id: "run-32", work_item_id: "work-32"},
                 classification: %{
                   source: "project_detail_test",
                   reason: "Repo detail memory inspection needs durable decision history."
                 }
               ),
               revision: revision
             )
  end

  defp latest_repo_conversation_id!(managed_repo_id) do
    assert {:ok, %{id: conversation_id}} =
             AgentWorkspace.latest_repo_conversation(managed_repo_id, actor: Actor.operator_actor())

    conversation_id
  end

  defp assert_conversation_settled!(conversation_id) do
    assert_eventually(fn ->
      case AgentWorkspace.conversation_snapshot(conversation_id) do
        {:ok, snapshot} ->
          is_nil(snapshot.active_turn) and is_nil(snapshot.active_child_work)

        _other ->
          false
      end
    end)
  end

  defp assert_eventually(fun, attempts \\ 20)

  defp assert_eventually(fun, attempts) when attempts <= 1 do
    assert fun.()
  end

  defp assert_eventually(fun, attempts) do
    if fun.() do
      assert true
    else
      receive do
      after
        25 -> assert_eventually(fun, attempts - 1)
      end
    end
  end
end
