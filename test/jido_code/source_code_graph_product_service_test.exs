defmodule JidoCode.SourceCodeGraphProductServiceTest do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.ProductService
  alias JidoCode.SourceCodeGraph.RefreshScheduler
  alias JidoCode.Workbench.ProjectSemanticInspection

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "summary/3" do
    test "returns bounded semantic summary groups after load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-123"
               )

      assert {:ok, summary} =
               ProductService.summary(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-123",
                 allow_stale?: true
               )

      assert summary.kind == :semantic_summary
      assert summary.managed_repo_id == managed_repo_id
      assert summary.graph.graph_name == "source_code"
      assert summary.graph.state == :ready
      assert summary.groups.modules.status == :ok
      assert summary.groups.modules.count >= 1
      assert summary.groups.runtime_patterns.status == :ok
    end

    test "returns semantic summary with explicit not-ready state before graph load" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, summary} = ProductService.summary(managed_repo_id, workspace_path)

      assert summary.graph.state == :not_ready
      assert summary.groups.modules.status == :unavailable
      assert summary.groups.runtime_patterns.status == :unavailable
    end

    test "semantic status hints explain queued background refresh activity" do
      previous_auto_refresh = Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled)
      Application.put_env(:jido_code, :source_code_graph_auto_refresh_enabled, true)

      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn ->
        restore_env(:source_code_graph_auto_refresh_enabled, previous_auto_refresh)
        RefreshScheduler.stop(managed_repo_id)
      end)

      assert {:ok, _pod} =
               AgentWorkspace.ensure_source_code_graph_pod(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false
               )

      assert {:ok, _pid} =
               RefreshScheduler.ensure_started(
                 managed_repo_id,
                 refresh_fun: fn _managed_repo_id, _workspace_path, _event, _opts ->
                   {:ok, %{status: :graph_refreshed}}
                 end,
                 refresh_debounce_ms: 1_000
               )

      assert :ok = RefreshScheduler.enqueue(source_change_event(managed_repo_id, workspace_path, ["lib/example.ex"]))
      assert {:ok, _scheduler_status} = RefreshScheduler.status(managed_repo_id)

      project_like = %{
        managed_repo_id: managed_repo_id,
        settings: %{
          "workspace" => %{
            "workspace_environment" => "local",
            "workspace_path" => workspace_path
          }
        }
      }

      assert %{} = hint = ProjectSemanticInspection.status_hint(project_like)
      assert hint.detail == "Background source-code graph refresh is queued after a source save."
      assert hint.remediation == "Refresh status will update after the debounce window."
    end
  end

  describe "status/3" do
    test "projects background refresh activity without changing graph state" do
      previous_auto_refresh = Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled)
      Application.put_env(:jido_code, :source_code_graph_auto_refresh_enabled, true)

      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      on_exit(fn ->
        restore_env(:source_code_graph_auto_refresh_enabled, previous_auto_refresh)
        RefreshScheduler.stop(managed_repo_id)
      end)

      assert {:ok, _pod} =
               AgentWorkspace.ensure_source_code_graph_pod(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false
               )

      assert {:ok, _pid} =
               RefreshScheduler.ensure_started(
                 managed_repo_id,
                 refresh_fun: fn _managed_repo_id, _workspace_path, _event, _opts ->
                   {:ok, %{status: :graph_refreshed}}
                 end,
                 refresh_debounce_ms: 1_000
               )

      assert :ok = RefreshScheduler.enqueue(source_change_event(managed_repo_id, workspace_path, ["lib/example.ex"]))
      assert {:ok, scheduler_status} = RefreshScheduler.status(managed_repo_id)
      assert scheduler_status.refresh_queued? == true

      assert {:ok, status} = ProductService.status(managed_repo_id, workspace_path)

      assert status.graph.state == :not_ready
      assert status.graph.refresh.auto_refresh_enabled? == true
      assert status.graph.refresh.refresh_queued? == true
      assert status.graph.refresh.refresh_in_flight? == false
      assert status.graph.refresh.pending_changed_paths == ["lib/example.ex"]
    end
  end

  describe "bounded lookup projections" do
    test "returns product-shaped module projections instead of raw bindings" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, projection} =
               ProductService.modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "ExampleWorkspace"
               )

      assert projection.kind == :modules
      assert projection.graph.state == :ready
      assert projection.result_group.count >= 1
      refute Map.has_key?(projection, :bindings)
      refute Map.has_key?(projection, :compiled_sparql)

      assert Enum.any?(projection.items, fn item ->
               item.module_name == "ExampleWorkspace" and is_binary(item.module_iri)
             end)
    end

    test "returns typed stale outcome with explicit graph recovery state" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path
               )

      rewrite_workspace_module!(workspace_path, "ExampleWorkspaceRenamed")

      assert {:error, :source_code_graph_stale, projection} =
               ProductService.modules(managed_repo_id, workspace_path)

      assert projection.kind == :modules
      assert projection.graph.state == :stale
      assert projection.graph.recovery_action == :refresh
      assert projection.error.type == :source_code_graph_stale
    end

    test "allows stale product projections when explicitly requested" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path
               )

      rewrite_workspace_module!(workspace_path, "ExampleWorkspaceRenamed")

      assert {:ok, projection} =
               ProductService.modules(managed_repo_id, workspace_path, allow_stale?: true)

      assert projection.graph.state == :degraded
      assert projection.result_group.degraded? == true
      assert projection.result_group.stale? == true
    end

    test "returns bounded function, runtime pattern, and impact projections" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!()

      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, functions} =
               ProductService.functions(
                 managed_repo_id,
                 workspace_path,
                 module_name: "ExampleWorkspace",
                 function_name: "greet"
               )

      assert functions.kind == :functions

      assert Enum.any?(functions.items, fn item ->
               item.module_name == "ExampleWorkspace" and item.function_name == "greet" and item.arity == 1
             end)

      assert {:ok, runtime_patterns} = ProductService.runtime_patterns(managed_repo_id, workspace_path)
      assert runtime_patterns.kind == :runtime_patterns
      assert is_list(runtime_patterns.items)

      assert {:ok, impact} =
               ProductService.impact(
                 managed_repo_id,
                 workspace_path,
                 module_name: "ExampleWorkspace"
               )

      assert impact.kind == :impact

      assert Enum.any?(impact.items, fn item ->
               item.predicate_name == "containsFunction"
             end)
    end
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_source_graph_product_service_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [app: :example, version: "0.1.0"]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule ExampleWorkspace do
        def greet(name), do: "hello \#{name}"
      end
      """
    )

    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name), do: "hello \#{name}"
      end
      """
    )
  end

  defp source_change_event(managed_repo_id, workspace_path, changed_paths) do
    %{
      kind: :workspace_source_changed,
      managed_repo_id: managed_repo_id,
      workspace_path: workspace_path,
      changed_paths: changed_paths,
      changed_path: List.first(changed_paths),
      file_events: [:modified],
      event_source: :human_watcher,
      event_sources: [:human_watcher],
      observed_at: DateTime.utc_now()
    }
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
