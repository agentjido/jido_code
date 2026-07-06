defmodule JidoCode.Runtime.RepositoryRuntimeAcceptanceTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.{AgentWorkspace, ContextManagement, MemoryGraph, Runtime, SourceCodeGraph}

  setup do
    repos =
      for label <- ["one", "two"] do
        managed_repo_id = "runtime-acceptance-#{label}-#{System.unique_integer([:positive])}"
        workspace_path = workspace_path!(managed_repo_id)
        {managed_repo_id, workspace_path}
      end

    on_exit(fn ->
      for {managed_repo_id, workspace_path} <- repos do
        Runtime.shutdown_repository(managed_repo_id)
        File.rm_rf(workspace_path)
      end
    end)

    [{repo_one, workspace_one}, {repo_two, workspace_two}] = repos

    {:ok, repo_one: repo_one, workspace_one: workspace_one, repo_two: repo_two, workspace_two: workspace_two}
  end

  test "two ManagedRepos run isolated repository runtimes with concurrent work", %{
    repo_one: repo_one,
    workspace_one: workspace_one,
    repo_two: repo_two,
    workspace_two: workspace_two
  } do
    work_specs = [
      {repo_one, workspace_one, "work-one-a"},
      {repo_one, workspace_one, "work-one-b"},
      {repo_two, workspace_two, "work-two-a"},
      {repo_two, workspace_two, "work-two-b"}
    ]

    results =
      work_specs
      |> Task.async_stream(
        fn {managed_repo_id, workspace_path, work_item_id} ->
          Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)
        end,
        max_concurrency: 4,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, %{lifecycle: :running}}, &1))
    assert Runtime.active_work_items(repo_one) == ["work-one-a", "work-one-b"]
    assert Runtime.active_work_items(repo_two) == ["work-two-a", "work-two-b"]

    for {managed_repo_id, _workspace_path, work_item_id} <- work_specs do
      assert %{metadata: %{managed_repo_id: ^managed_repo_id, work_item_id: ^work_item_id}} =
               Runtime.coding_pod_status(managed_repo_id, work_item_id)
    end
  end

  test "one repository runtime hosts graph, memory, context management, and specialist work", %{
    repo_one: managed_repo_id,
    workspace_one: workspace_path
  } do
    work_item_id = "work-full-topology"

    assert {:ok, plan_result} =
             AgentWorkspace.plan_work(managed_repo_id, work_item_id, "Plan runtime acceptance",
               workspace_path: workspace_path
             )

    assert plan_result.plan =~ "deterministic planner response"
    assert {:ok, _source_pod} = Runtime.ensure_source_code_graph_pod(managed_repo_id)
    assert {:ok, _memory_pod} = Runtime.ensure_memory_graph_pod(managed_repo_id)

    assert {:ok, _context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, %{
               context_management_status: :healthy
             })

    assert {:ok, _planner_pid} = Runtime.ensure_work_item_node(managed_repo_id, work_item_id, :planner)

    assert {:ok, _source_pod} =
             Runtime.update_pod_metadata(managed_repo_id, SourceCodeGraph.pod_id(), %{
               latest_import_status: %{ready?: true, state: :loaded, imported_revision: "acceptance-source"}
             })

    assert {:ok, _memory_pod} =
             Runtime.update_pod_metadata(managed_repo_id, MemoryGraph.pod_id(), %{
               latest_validation_status: %{ready?: true, state: :validated, validated_revision: "acceptance-memory"}
             })

    assert %{
             lifecycle: :ready,
             active_work_count: 1,
             source_code_graph: %{present?: true, ready?: true, state: :loaded},
             memory_graph: %{present?: true, ready?: true, state: :validated},
             context_management: [%{work_item_id: ^work_item_id, state: "healthy"}]
           } = Runtime.repository_health(managed_repo_id)
  end

  test "degraded runtime health stays product-readable when graph, memory, and context pods exit", %{
    repo_one: managed_repo_id,
    workspace_one: workspace_path
  } do
    work_item_id = "work-degraded-topology"

    assert {:ok, _status} = Runtime.ensure_repository(managed_repo_id, workspace_path)
    assert {:ok, _source_pod} = Runtime.ensure_source_code_graph_pod(managed_repo_id)
    assert {:ok, _memory_pod} = Runtime.ensure_memory_graph_pod(managed_repo_id)
    assert {:ok, _coding_pod} = Runtime.ensure_coding_pod(managed_repo_id, work_item_id, workspace_path)

    assert {:ok, _context_pod} =
             Runtime.ensure_context_management_pod(managed_repo_id, work_item_id, workspace_path, %{})

    kill_runtime_pod!(managed_repo_id, SourceCodeGraph.pod_id())
    kill_runtime_pod!(managed_repo_id, MemoryGraph.pod_id())
    kill_runtime_pod!(managed_repo_id, ContextManagement.pod_id(work_item_id))

    assert %{
             lifecycle: :degraded,
             active_work_count: 1,
             source_code_graph: %{present?: false, ready?: false, state: :unavailable},
             memory_graph: %{present?: false, ready?: false, state: :unavailable},
             context_management: [],
             diagnostics: diagnostics
           } = health = Runtime.repository_health(managed_repo_id)

    diagnostic_kinds = diagnostics |> Enum.map(&Map.get(&1, :kind)) |> MapSet.new()
    assert MapSet.subset?(MapSet.new([:source_code_graph, :memory_graph, :context_management]), diagnostic_kinds)

    rendered_health = inspect(health)
    refute rendered_health =~ "#PID"
    refute rendered_health =~ "runtime_pid"
    refute rendered_health =~ "nodes"
  end

  defp kill_runtime_pod!(managed_repo_id, pod_id) do
    assert %{runtime_pid: pod_pid} = Runtime.pod_status(managed_repo_id, pod_id)

    monitor_ref = Process.monitor(pod_pid)
    Process.exit(pod_pid, :kill)
    assert_receive {:DOWN, ^monitor_ref, :process, ^pod_pid, :killed}, 1_000
    sync_runtime!(managed_repo_id)
  end

  defp sync_runtime!(managed_repo_id) do
    assert {:ok, runtime_pid} = Runtime.lookup_repository_pid(managed_repo_id)
    _state = :sys.get_state(runtime_pid)
    :ok
  end

  defp workspace_path!(name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_runtime_acceptance_#{name}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule RuntimeAcceptanceExample.MixProject do
        use Mix.Project

        def project do
          [app: :runtime_acceptance_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/example.ex"),
      """
      defmodule RuntimeAcceptanceExample do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    workspace_path
  end
end
