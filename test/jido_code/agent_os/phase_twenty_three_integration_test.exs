defmodule JidoCode.AgentOSPhaseTwentyThreeIntegrationTest do
  # covers: architecture.agent_os_integration.source_code_graph_stale_and_recovery_state_stays_workspace_bound
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
  # covers: architecture.source_code_graph_pod.stale_queries_and_failures_remain_bounded
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  # covers: package.jido_code.version_controlled_quality_surfaces
  use ExUnit.Case, async: false

  alias JidoCode.AgentWorkspace

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "23.3.1 Revision and recovery scenarios" do
    test "23.3.1.1 stale revision is surfaced explicitly and refresh restores coherence" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyThree.Alpha")

      assert {:ok, load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      rewrite_workspace_module!(workspace_path, "PhaseTwentyThree.Beta")

      assert {:ok, stale_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert stale_status.ready? == true
      assert stale_status.stale? == true
      assert stale_status.stale_reason == :workspace_revision_changed
      assert stale_status.queryable_when_stale? == true
      assert stale_status.current_revision != load_result.latest_import_status.imported_revision

      assert {:ok, stale_query} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o } LIMIT 5",
                 allow_stale?: true
               )

      assert stale_query.degraded? == true
      assert stale_query.stale_graph? == true

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, refreshed_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert refresh_result.latest_import_status.imported_revision == refreshed_status.current_revision
      assert refreshed_status.ready? == true
      assert refreshed_status.stale? == false
      assert refreshed_status.latest_failure == nil
    end

    test "23.3.1.2 failed load attempts preserve recovery metadata and bounded query behavior" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyThree.Gamma")
      blocker_path = Path.join(workspace_path, ".jido_code")

      File.write!(blocker_path, "block store directory")

      assert {:error, :source_code_graph_store_failed, diagnostics} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert diagnostics.stage == :prepare_store_parent

      assert {:ok, failed_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert failed_status.ready? == false
      assert failed_status.latest_failure.kind == :source_code_graph_store_failed
      assert failed_status.latest_failure.stage == :prepare_store_parent

      assert {:error, :source_code_graph_not_ready, _message} =
               AgentWorkspace.query_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )

      File.rm!(blocker_path)

      assert {:ok, recovery_result} =
               AgentWorkspace.recover_source_code_graph(managed_repo_id, workspace_path)

      assert recovery_result.recovery_action == :load
      assert recovery_result.graph_status.ready? == true

      assert {:ok, recovered_status} =
               AgentWorkspace.source_code_graph_status(managed_repo_id, workspace_path)

      assert recovered_status.ready? == true
      assert recovered_status.latest_failure == nil
    end
  end

  describe "23.3.2 End-to-end repository semantic workflow scenarios" do
    test "23.3.2.1 one repository can analyze, load, refresh, and query its source_code graph end to end" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyThree.Delta")

      assert {:ok, analysis_result} =
               AgentWorkspace.analyze_source_code_graph(managed_repo_id, workspace_path)

      assert analysis_result.latest_analysis_status.state == :analyzed

      assert {:ok, _load_result} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, modules_before} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseTwentyThree"
               )

      assert Enum.any?(modules_before.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.Delta"
             end)

      rewrite_workspace_module!(workspace_path, "PhaseTwentyThree.Epsilon")

      assert {:ok, _refresh_result} =
               AgentWorkspace.refresh_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, modules_after} =
               AgentWorkspace.find_source_code_graph_modules(
                 managed_repo_id,
                 workspace_path,
                 module_name_contains: "PhaseTwentyThree"
               )

      refute Enum.any?(modules_after.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.Delta"
             end)

      assert Enum.any?(modules_after.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.Epsilon"
             end)
    end

    test "23.3.2.2 multiple repositories keep isolated local stores and named graphs" do
      repo_one = "repo-#{System.unique_integer()}"
      repo_two = "repo-#{System.unique_integer()}"
      workspace_one = create_workspace_path!("PhaseTwentyThree.RepoOne")
      workspace_two = create_workspace_path!("PhaseTwentyThree.RepoTwo")

      assert {:ok, repo_one_summary} =
               AgentWorkspace.ensure_source_code_graph_pod(repo_one, workspace_one)

      assert {:ok, repo_two_summary} =
               AgentWorkspace.ensure_source_code_graph_pod(repo_two, workspace_two)

      assert repo_one_summary.graph_store_path != repo_two_summary.graph_store_path

      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(repo_one, workspace_one)
      assert {:ok, _load_result} = AgentWorkspace.load_source_code_graph(repo_two, workspace_two)

      assert {:ok, repo_one_modules} =
               AgentWorkspace.find_source_code_graph_modules(
                 repo_one,
                 workspace_one,
                 module_name_contains: "PhaseTwentyThree"
               )

      assert {:ok, repo_two_modules} =
               AgentWorkspace.find_source_code_graph_modules(
                 repo_two,
                 workspace_two,
                 module_name_contains: "PhaseTwentyThree"
               )

      assert Enum.any?(repo_one_modules.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.RepoOne"
             end)

      refute Enum.any?(repo_one_modules.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.RepoTwo"
             end)

      assert Enum.any?(repo_two_modules.bindings, fn row ->
               get_in(row, ["module_name", :value]) == "PhaseTwentyThree.RepoTwo"
             end)
    end

    test "23.3.2.3 docs and verification surfaces stay aligned with the semantic graph architecture" do
      assert File.read!("README.md") =~ "mix source_graph.verify"
      assert File.read!("README.md") =~ "semantic source-code graph capability"
      assert File.read!("CONTRIBUTING.md") =~ "mix source_graph.verify"
      assert File.read!("AGENTS.md") =~ "When touching the semantic graph boundary"
      assert File.read!("mix.exs") =~ "\"source_graph.verify\""
    end
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_three_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyThree.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_three_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_workspace_module!(workspace_path, module_name)

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end

  defp rewrite_workspace_module!(workspace_path, module_name) do
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
end
