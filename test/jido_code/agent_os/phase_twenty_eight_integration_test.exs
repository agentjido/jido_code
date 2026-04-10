defmodule JidoCode.AgentOSPhaseTwentyEightIntegrationTest do
  # covers: architecture.agent_os_integration.memory_graph_pod_singleton_when_enabled
  # covers: architecture.agent_os_integration.memory_graph_read_write_and_query_stay_workspace_bound
  # covers: architecture.memory_graph.repo_scoped_memory_graph_pod
  # covers: architecture.memory_graph.local_quad_store_hosts_source_memory_and_workflow_graphs
  # covers: architecture.memory_graph.memory_named_graph_is_canonical_target
  # covers: architecture.memory_graph.workflow_provenance_named_graph_is_canonical_target
  # covers: architecture.memory_graph.memory_graph_links_to_source_code_entities_by_stable_iri
  # covers: architecture.memory_graph.explicit_actions_drive_memory_recording_query_and_invalidation
  # covers: architecture.memory_graph.memory_graph_status_and_freshness_are_explicit
  # covers: architecture.memory_graph.memory_graph_consumers_use_bounded_product_or_workspace_entrypoints
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentOS.Manager
  alias JidoCode.AgentWorkspace

  alias JidoCode.Actions.{
    GetMemoryGraphStatus,
    InvalidateMemoryGraph,
    QueryMemoryGraph,
    RecordMemoryGraph,
    RefreshMemoryGraph,
    ValidateMemoryGraph
  }

  alias JidoCode.{MemoryGraph, SourceCodeGraph}

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

  describe "28.3.1 Pod and store foundation scenarios" do
    test "28.3.1.1 one repository can host a memory graph pod without affecting another kernel" do
      repo_one = "repo-#{System.unique_integer()}"
      repo_two = "repo-#{System.unique_integer()}"
      workspace_one = create_workspace_path!("PhaseTwentyEight.One")
      workspace_two = create_workspace_path!("PhaseTwentyEight.Two")

      assert {:ok, repo_one_summary} =
               AgentWorkspace.ensure_memory_graph_pod(repo_one, workspace_one)

      assert {:ok, repo_two_summary} =
               AgentWorkspace.ensure_memory_graph_pod(repo_two, workspace_two)

      assert repo_one_summary.pod_id == "memory_graph"
      assert repo_two_summary.pod_id == "memory_graph"
      assert repo_one_summary.graph_store_path != repo_two_summary.graph_store_path

      assert Manager.pod_status(repo_one, "memory_graph").metadata.workspace_path == workspace_one
      assert Manager.pod_status(repo_two, "memory_graph").metadata.workspace_path == workspace_two
    end

    test "28.3.1.2 memory and workflow provenance are explicit named graphs in the repository-local quad store" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyEight.Graphs")

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert_memory_graphs_present!(refresh_result.store.path)
    end

    test "28.3.1.3 stable source graph anchors remain available for later cross-graph links" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyEight.Anchor")

      assert {:ok, _source_graph} =
               AgentWorkspace.load_source_code_graph(managed_repo_id, workspace_path)

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert_graph_anchor_present!(refresh_result.store.path, managed_repo_id, "PhaseTwentyEight.Anchor")
    end
  end

  describe "28.3.2 Action and workspace boundary scenarios" do
    test "28.3.2.1 record query validate invalidate and refresh route through explicit actions" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyEight.Actions")

      expected_actions = [
        {RefreshMemoryGraph, :workspace_path},
        {ValidateMemoryGraph, :workspace_path},
        {GetMemoryGraphStatus, :graph_name},
        {QueryMemoryGraph, :sparql},
        {RecordMemoryGraph, :capture},
        {InvalidateMemoryGraph, :reason}
      ]

      Enum.each(expected_actions, fn {action, expected_field} ->
        assert function_exported?(action, :run, 2)
        assert function_exported?(action, :schema, 0)
        assert Keyword.keyword?(action.schema())
        assert Keyword.has_key?(action.schema(), expected_field)
      end)

      context = %{managed_repo_id: managed_repo_id, workspace_path: workspace_path}

      assert {:ok, refresh_result} = RefreshMemoryGraph.run(%{}, context)

      assert {:ok, validate_result} =
               ValidateMemoryGraph.run(
                 %{},
                 Map.put(context, :latest_validation_status, refresh_result.latest_validation_status)
               )

      assert validate_result.status == :memory_graph_validated

      assert {:ok, status_result} =
               GetMemoryGraphStatus.run(
                 %{},
                 Map.put(context, :latest_validation_status, validate_result.latest_validation_status)
               )

      assert status_result.ready? == true

      assert {:ok, query_result} =
               QueryMemoryGraph.run(
                 %{sparql: "SELECT * WHERE { ?s ?p ?o } LIMIT 1"},
                 Map.put(context, :latest_validation_status, validate_result.latest_validation_status)
               )

      assert query_result.status == :query_succeeded

      assert {:error, :memory_capture_plane_not_ready, diagnostics} =
               RecordMemoryGraph.run(
                 %{capture: %{kind: :fact, content: "placeholder"}},
                 Map.put(context, :latest_validation_status, validate_result.latest_validation_status)
               )

      assert diagnostics.state == :capture_plane_not_ready

      assert {:ok, invalidate_result} =
               InvalidateMemoryGraph.run(
                 %{reason: :manual_invalidation},
                 Map.put(context, :latest_validation_status, validate_result.latest_validation_status)
               )

      assert invalidate_result.status == :memory_graph_invalidated
    end

    test "28.3.2.2 AgentWorkspace exposes typed bounded status and recovery behavior" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyEight.Workspace")

      assert {:error, :memory_graph_not_ready, _message} =
               AgentWorkspace.query_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 "SELECT * WHERE { ?s ?p ?o }"
               )

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_memory_graph(managed_repo_id, workspace_path)

      assert refresh_result.latest_validation_status.ready? == true

      assert {:ok, status_result} =
               AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path)

      assert status_result.ready? == true
      assert status_result.stale? == false

      assert {:error, :memory_capture_plane_not_ready, diagnostics} =
               AgentWorkspace.record_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 %{kind: :fact, content: "placeholder"}
               )

      assert diagnostics.state == :capture_plane_not_ready

      assert {:ok, invalidate_result} =
               AgentWorkspace.invalidate_memory_graph(
                 managed_repo_id,
                 workspace_path,
                 reason: :manual_invalidation
               )

      assert invalidate_result.status == :memory_graph_invalidated

      assert {:ok, invalidated_status} =
               AgentWorkspace.memory_graph_status(managed_repo_id, workspace_path)

      assert invalidated_status.latest_validation_status.state == :invalidated
      assert invalidated_status.latest_validation_status.ready? == false
    end
  end

  defp assert_memory_graphs_present!(store_path) do
    memory_graph = RDF.iri(MemoryGraph.memory_named_graph_iri())
    workflow_graph = RDF.iri(MemoryGraph.workflow_provenance_named_graph_iri())

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      assert {:ok, graphs_summary} =
               TripleStore.QuadOperations.graphs_summary(store.db, include_default: false)

      assert Map.get(graphs_summary, memory_graph, 0) > 0
      assert Map.get(graphs_summary, workflow_graph, 0) > 0
    after
      :ok = TripleStore.close(store)
    end
  end

  defp assert_graph_anchor_present!(store_path, managed_repo_id, module_name) do
    source_graph = RDF.iri(SourceCodeGraph.named_graph_iri())

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      {:ok, graph_id} = TripleStore.Adapter.term_to_id(store.dict_manager, source_graph)
      {:ok, rdf_type_id} = TripleStore.Adapter.term_to_id(store.dict_manager, RDF.iri(RDF.type()))

      {:ok, module_class_id} =
        TripleStore.Adapter.term_to_id(
          store.dict_manager,
          RDF.iri("https://w3id.org/elixir-code/structure#Module")
        )

      module_iri = RDF.iri("#{SourceCodeGraph.base_iri(managed_repo_id)}#{module_name}")
      {:ok, module_id} = TripleStore.Adapter.term_to_id(store.dict_manager, module_iri)

      assert TripleStore.QuadOperations.quad_exists?(
               store.db,
               {module_id, rdf_type_id, module_class_id, graph_id}
             )
    after
      :ok = TripleStore.close(store)
    end
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_eight_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyEight.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_eight_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    File.write!(
      Path.join(workspace_path, "lib/phase_twenty_eight_example.ex"),
      """
      defmodule #{module_name} do
        def greet(name) when is_binary(name), do: "hello " <> name
      end
      """
    )

    on_exit(fn -> File.rm_rf!(workspace_path) end)
    workspace_path
  end
end
