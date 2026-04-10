defmodule JidoCode.AgentOSPhaseTwentyOneIntegrationTest do
  # covers: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
  # covers: architecture.agent_os_integration.product_work_entrypoints_route_to_workspace
  # covers: architecture.agent_os_integration.workspace_context_hides_kernel_topology
  # covers: architecture.source_code_graph_pod.full_elixir_ontology_profile_is_required
  # covers: architecture.source_code_graph_pod.local_triple_store_quad_schema_is_canonical_store
  # covers: architecture.source_code_graph_pod.source_code_named_graph_is_canonical_target
  # covers: architecture.source_code_graph_pod.ontology_schema_and_project_individuals_are_loaded_together
  # covers: architecture.source_code_graph_pod.graph_refresh_replaces_named_graph_coherently
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  describe "21.4.1 Full ontology analysis scenarios" do
    test "21.4.1.1 analysis runs in full ontology mode and stages schema plus individuals" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyOne.Alpha")

      assert {:ok, analysis_result} =
               AgentWorkspace.analyze_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-one"
               )

      assert analysis_result.analysis.extraction_mode == :full
      assert analysis_result.analysis.options.include_expressions == true
      assert analysis_result.analysis.options.exclude_tests == true
      assert length(analysis_result.load_artifacts.ontology_schema.artifacts) == 5
      assert analysis_result.load_artifacts.project_individuals.triple_count > 0
      assert analysis_result.latest_analysis_status.state == :analyzed
      assert analysis_result.latest_analysis_status.analyzed_revision == "rev-one"

      assert String.starts_with?(
               analysis_result.latest_analysis_status.workspace_snapshot_identity,
               "snapshot:"
             )
    end

    test "21.4.1.2 analysis failure returns typed bounded diagnostics" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      missing_workspace = Path.join(System.tmp_dir!(), "missing-phase-twenty-one-#{System.unique_integer()}")

      assert {:error, :source_code_graph_analysis_failed, diagnostics} =
               AgentWorkspace.analyze_source_code_graph(
                 managed_repo_id,
                 missing_workspace,
                 revision: "rev-fail"
               )

      assert diagnostics.state == :analysis_failed
      assert diagnostics.analyzed_revision == "rev-fail"
      assert diagnostics.graph_name == "source_code"
      assert is_binary(diagnostics.failure)
    end
  end

  describe "21.4.2 Named-graph load and refresh scenarios" do
    test "21.4.2.1 initial load and refresh keep one coherent source_code graph snapshot" do
      managed_repo_id = "repo-#{System.unique_integer()}"
      workspace_path = create_workspace_path!("PhaseTwentyOne.Alpha")

      assert {:ok, load_result} =
               AgentWorkspace.load_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-one"
               )

      assert load_result.store.backend == :triple_store
      assert load_result.store.schema == :quad
      assert load_result.latest_import_status.imported_revision == "rev-one"

      assert_graph_snapshot!(
        load_result.store.path,
        managed_repo_id,
        present_modules: ["PhaseTwentyOne.Alpha"],
        absent_modules: ["PhaseTwentyOne.Beta"]
      )

      rewrite_workspace_module!(workspace_path, "PhaseTwentyOne.Beta")

      assert {:ok, refresh_result} =
               AgentWorkspace.refresh_source_code_graph(
                 managed_repo_id,
                 workspace_path,
                 revision: "rev-two"
               )

      assert refresh_result.store.path == load_result.store.path
      assert refresh_result.latest_import_status.imported_revision == "rev-two"
      assert refresh_result.latest_import_status.refresh_mode == :replace_named_graph

      assert_graph_snapshot!(
        refresh_result.store.path,
        managed_repo_id,
        present_modules: ["PhaseTwentyOne.Beta"],
        absent_modules: ["PhaseTwentyOne.Alpha"]
      )
    end
  end

  defp assert_graph_snapshot!(store_path, managed_repo_id, opts) do
    present_modules = Keyword.get(opts, :present_modules, [])
    absent_modules = Keyword.get(opts, :absent_modules, [])
    named_graph = RDF.iri(SourceCodeGraph.named_graph_iri())

    {:ok, store} = TripleStore.open(store_path, create_if_missing: false, schema: :quad)

    try do
      assert {:ok, %{^named_graph => quad_count}} =
               TripleStore.QuadOperations.graphs_summary(store.db, include_default: false)

      assert quad_count > 0

      {:ok, graph_id} = TripleStore.Adapter.term_to_id(store.dict_manager, named_graph)
      {:ok, rdf_type_id} = TripleStore.Adapter.term_to_id(store.dict_manager, RDF.iri(RDF.type()))

      {:ok, module_class_id} =
        TripleStore.Adapter.term_to_id(
          store.dict_manager,
          RDF.iri("https://w3id.org/elixir-code/structure#Module")
        )

      {:ok, owl_class_id} =
        TripleStore.Adapter.term_to_id(
          store.dict_manager,
          RDF.iri("http://www.w3.org/2002/07/owl#Class")
        )

      assert TripleStore.QuadOperations.quad_exists?(
               store.db,
               {module_class_id, rdf_type_id, owl_class_id, graph_id}
             )

      Enum.each(present_modules, fn module_name ->
        assert TripleStore.QuadOperations.quad_exists?(
                 store.db,
                 {module_term_id!(store, managed_repo_id, module_name), rdf_type_id, module_class_id, graph_id}
               )
      end)

      Enum.each(absent_modules, fn module_name ->
        refute TripleStore.QuadOperations.quad_exists?(
                 store.db,
                 {module_term_id!(store, managed_repo_id, module_name), rdf_type_id, module_class_id, graph_id}
               )
      end)
    after
      :ok = TripleStore.close(store)
    end
  end

  defp module_term_id!(store, managed_repo_id, module_name) do
    module_iri = RDF.iri("#{SourceCodeGraph.base_iri(managed_repo_id)}#{module_name}")
    {:ok, module_id} = TripleStore.Adapter.term_to_id(store.dict_manager, module_iri)
    module_id
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_one_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyOne.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_one_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
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
