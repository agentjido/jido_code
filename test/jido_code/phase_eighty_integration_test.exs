defmodule JidoCode.PhaseEightyIntegrationTest do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.repository_runtime_integration.repo_pod_singleton_when_enabled
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Agents.RepoMonitor
  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.RefreshScheduler

  setup do
    previous_source_graph = Application.get_env(:jido_code, :source_code_graph_enabled)
    previous_auto_refresh = Application.get_env(:jido_code, :source_code_graph_auto_refresh_enabled)
    previous_refresh_debounce = Application.get_env(:jido_code, :source_code_graph_refresh_debounce_ms)
    previous_refresh_coalesce = Application.get_env(:jido_code, :source_code_graph_refresh_max_coalesce_ms)

    Application.put_env(:jido_code, :source_code_graph_enabled, true)
    Application.put_env(:jido_code, :source_code_graph_auto_refresh_enabled, true)
    Application.put_env(:jido_code, :source_code_graph_refresh_debounce_ms, 1)
    Application.put_env(:jido_code, :source_code_graph_refresh_max_coalesce_ms, 1)

    on_exit(fn ->
      restore_env(:source_code_graph_enabled, previous_source_graph)
      restore_env(:source_code_graph_auto_refresh_enabled, previous_auto_refresh)
      restore_env(:source_code_graph_refresh_debounce_ms, previous_refresh_debounce)
      restore_env(:source_code_graph_refresh_max_coalesce_ms, previous_refresh_coalesce)
    end)

    :ok
  end

  describe "80.5 save-triggered source graph refresh" do
    test "80.5.2.1 simulated watcher save refreshes the loaded graph and preserves stale-query semantics while running" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!("PhaseEighty.HumanBefore")

      on_exit(fn ->
        RepoMonitor.stop_source_watcher(managed_repo_id)
        RefreshScheduler.stop(managed_repo_id)
      end)

      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, _pid} =
               RefreshScheduler.ensure_started(
                 managed_repo_id,
                 refresh_fun: blocking_refresh_fun(self()),
                 refresh_debounce_ms: 1,
                 refresh_max_coalesce_ms: 1
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))
      rewrite_workspace_module!(workspace_path, "PhaseEighty.HumanAfter")

      assert {:ok, _watcher_pid} =
               RepoMonitor.ensure_source_watcher(
                 managed_repo_id,
                 workspace_path,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      assert :ok =
               RepoMonitor.notify_source_changed(
                 managed_repo_id,
                 Path.join(workspace_path, "lib/example_workspace.ex"),
                 [:modified],
                 :human_watcher
               )

      assert_receive {:workspace_source_changed, %{event_source: :human_watcher}}, 200
      assert_receive {:refresh_started, refresh_task, %{event_source: :human_watcher}}, 500

      assert {:error, :source_code_graph_stale, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )

      assert {:ok, stale_query} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o } LIMIT 5",
                 allow_stale?: true
               )

      assert stale_query.degraded? == true
      assert stale_query.stale_graph? == true

      send(refresh_task, :release_refresh)
      assert_receive {:refresh_completed, {:ok, refresh_result}}, 5_000
      assert refresh_result.latest_import_status.ready? == true

      assert {:ok, refreshed_status} = AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)
      assert refreshed_status.ready? == true
      assert refreshed_status.stale? == false
      assert refreshed_status.imported_revision == refreshed_status.current_revision

      assert {:ok, modules_after} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseEighty"
               )

      assert module_present?(modules_after, "PhaseEighty.HumanAfter")
      refute module_present?(modules_after, "PhaseEighty.HumanBefore")
    end

    test "80.5.2.2 product LLM write notification follows the same refresh path" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!("PhaseEighty.LlmBefore")

      on_exit(fn ->
        RepoMonitor.stop_source_watcher(managed_repo_id)
        RefreshScheduler.stop(managed_repo_id)
      end)

      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, _pid} =
               RefreshScheduler.ensure_started(
                 managed_repo_id,
                 refresh_fun: blocking_refresh_fun(self()),
                 refresh_debounce_ms: 1,
                 refresh_max_coalesce_ms: 1
               )

      Phoenix.PubSub.subscribe(JidoCode.PubSub, RepoMonitor.source_change_topic(managed_repo_id))
      rewrite_workspace_module!(workspace_path, "PhaseEighty.LlmAfter")

      assert :ok =
               AgentWorkspace.notify_workspace_source_changed(
                 managed_repo_id,
                 workspace_path,
                 "lib/example_workspace.ex",
                 event_source: :llm_write,
                 start_file_system?: false,
                 debounce_ms: 1
               )

      assert_receive {:workspace_source_changed, %{event_source: :llm_write}}, 200
      assert_receive {:refresh_started, refresh_task, %{event_source: :llm_write}}, 500

      send(refresh_task, :release_refresh)
      assert_receive {:refresh_completed, {:ok, _refresh_result}}, 5_000

      assert {:ok, refreshed_status} = AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)
      assert refreshed_status.ready? == true
      assert refreshed_status.stale? == false

      assert {:ok, modules_after} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseEighty"
               )

      assert module_present?(modules_after, "PhaseEighty.LlmAfter")
      refute module_present?(modules_after, "PhaseEighty.LlmBefore")
    end
  end

  defp blocking_refresh_fun(parent) do
    fn managed_repo_id, workspace_path, event, _opts ->
      send(parent, {:refresh_started, self(), event})

      receive do
        :release_refresh -> :ok
      after
        5_000 -> :ok
      end

      result = AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path)
      send(parent, {:refresh_completed, result})
      result
    end
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_eighty_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseEighty.MixProject do
        use Mix.Project

        def project do
          [app: :phase_eighty_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_workspace_module!(workspace_path, module_name)

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
    File.write!(
      Path.join(workspace_path, "lib/example_workspace.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )
  end

  defp module_present?(result, module_name) do
    Enum.any?(Map.get(result, :bindings, []), fn row ->
      get_in(row, ["module_name", :value]) == module_name
    end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
