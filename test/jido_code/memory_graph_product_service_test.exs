defmodule JidoCode.MemoryGraphProductServiceTest do
  # covers: architecture.memory_graph_product_adoption.product_owned_memory_service_boundary
  # covers: architecture.memory_graph_product_adoption.memory_operator_surfaces_show_freshness_validation_and_recovery
  # covers: architecture.memory_graph_product_adoption.operator_surfaces_do_not_expose_raw_memory_graph_internals
  # covers: architecture.memory_graph_product_adoption.memory_and_provenance_views_can_cross_link_to_source_code
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.MemoryGraph
  alias JidoCode.MemoryGraph.{CaptureEnvelope, DurableMemoryEnvelope, ProductService}

  setup do
    previous = Application.get_env(:jido_code, :memory_graph_enabled, false)
    Application.put_env(:jido_code, :memory_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :memory_graph_enabled, previous)
    end)

    :ok
  end

  describe "summary/3" do
    test "returns explicit not-ready state before repository memory is prepared" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()

      assert {:ok, summary} = ProductService.summary(managed_repo_id, workspace_path)

      assert summary.kind == :memory_graph_summary
      assert summary.graph.state == :not_ready
      assert summary.groups.memories.status == :unavailable
      assert summary.groups.provenance.status == :unavailable
    end

    test "returns bounded memory and provenance groups after memory capture" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-32-summary"

      %{memory_resource_iri: memory_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      assert {:ok, summary} =
               ProductService.summary(
                 managed_repo_id,
                 workspace_path,
                 revision: revision
               )

      assert summary.graph.graph_name == "memory"
      assert summary.graph.state == :ready
      assert summary.groups.memories.status == :ok
      assert summary.groups.memories.count >= 1
      assert summary.groups.provenance.status == :ok
      assert summary.groups.provenance.count >= 1

      assert Enum.any?(summary.groups.memories.items, fn item ->
               item.memory_iri == memory_resource_iri
             end)
    end
  end

  describe "bounded recall projections" do
    test "returns product-shaped durable memories without raw query bindings" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-32-memories"

      %{memory_resource_iri: memory_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      assert {:ok, projection} =
               ProductService.memories(
                 managed_repo_id,
                 workspace_path,
                 content_contains: "Repository decisions",
                 revision: revision
               )

      assert projection.kind == :memories
      assert projection.graph.state == :ready
      refute Map.has_key?(projection, :bindings)
      refute Map.has_key?(projection, :compiled_sparql)

      assert Enum.any?(projection.items, fn item ->
               item.memory_iri == memory_resource_iri and
                 item.memory_kind == "Decision" and
                 item.module_name == "ExampleWorkspace" and
                 item.decision_status == "accepted"
             end)

      memory_item = Enum.find(projection.items, &(&1.memory_iri == memory_resource_iri))

      assert Enum.any?(memory_item.governed_context, fn link ->
               link.kind == :run and link.id == "run-32" and
                 link.route == "/repos/#{managed_repo_id}/runs/run-32"
             end)

      assert Enum.any?(memory_item.governed_context, fn link ->
               link.kind == :work_item and link.id == "work-32" and
                 link.label == "Work item work-32"
             end)
    end

    test "returns product-shaped workflow provenance projections" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-32-provenance"

      %{plan_resource_iri: plan_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      assert {:ok, projection} =
               ProductService.provenance(
                 managed_repo_id,
                 workspace_path,
                 label_contains: "plan artifact",
                 revision: revision
               )

      assert projection.kind == :provenance
      assert projection.graph.state == :ready

      assert Enum.any?(projection.items, fn item ->
               item.resource_iri == plan_resource_iri and item.provenance_kind == "Plan"
             end)

      plan_item = Enum.find(projection.items, &(&1.resource_iri == plan_resource_iri))

      assert Enum.any?(plan_item.governed_context, fn link ->
               link.kind == :run and link.id == "run-32"
             end)

      assert Enum.any?(plan_item.governed_context, fn link ->
               link.kind == :evidence and link.id == "evidence-32" and
                 link.label == "Evidence evidence-32"
             end)
    end

    test "returns bounded cross-graph navigation for memory resources" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-32-cross-links"

      %{memory_resource_iri: memory_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      assert {:ok, projection} =
               ProductService.cross_links(
                 managed_repo_id,
                 workspace_path,
                 memory_resource_iri,
                 revision: revision
               )

      assert projection.kind == :cross_links

      assert Enum.any?(projection.navigation.source_code, fn link ->
               link.kind == :module and link.label == "ExampleWorkspace"
             end)

      assert Enum.any?(projection.navigation.governed_records, fn link ->
               link.kind == :run and link.id == "run-32" and
                 link.route == "/repos/#{managed_repo_id}/runs/run-32"
             end)

      refute Enum.any?(projection.navigation.governed_records, &(&1.kind == :artifact))
    end

    test "returns typed governed labels when no canonical route exists yet" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-37-cross-links"

      %{plan_resource_iri: plan_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      assert {:ok, projection} =
               ProductService.cross_links(
                 managed_repo_id,
                 workspace_path,
                 plan_resource_iri,
                 revision: revision
               )

      assert Enum.any?(projection.navigation.governed_records, fn link ->
               link.kind == :evidence and link.id == "evidence-32" and
                 link.label == "Evidence evidence-32" and is_nil(link.route)
             end)
    end

    test "returns governed-artifact scoped memory and provenance projections" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-33-governed-surface"

      %{memory_resource_iri: memory_resource_iri, plan_resource_iri: plan_resource_iri} =
        seed_memory_graph!(managed_repo_id, workspace_path, revision)

      artifact_paths = [
        JidoCode.MemoryGraph.artifact_path(:run, "run-32"),
        JidoCode.MemoryGraph.artifact_path(:evidence, "evidence-32")
      ]

      assert {:ok, memories_projection} =
               ProductService.memories_for_governed_artifacts(
                 managed_repo_id,
                 workspace_path,
                 artifact_paths,
                 revision: revision
               )

      assert Enum.any?(memories_projection.items, &(&1.memory_iri == memory_resource_iri))

      assert {:ok, provenance_projection} =
               ProductService.provenance_for_governed_artifacts(
                 managed_repo_id,
                 workspace_path,
                 artifact_paths,
                 revision: revision
               )

      assert Enum.any?(provenance_projection.items, &(&1.resource_iri == plan_resource_iri))
    end

    test "keeps stale memory explicit and only returns degraded recall when requested" do
      managed_repo_id = "repo-#{System.unique_integer([:positive])}"
      workspace_path = create_workspace_path!()
      revision = "phase-32-stale"

      seed_memory_graph!(managed_repo_id, workspace_path, revision)
      rewrite_workspace_module!(workspace_path, "ExampleWorkspaceRenamed")

      assert {:error, :memory_graph_stale, projection} =
               ProductService.memories(managed_repo_id, workspace_path)

      assert projection.kind == :memories
      assert projection.graph.state == :stale
      assert projection.error.type == :memory_graph_stale

      assert {:ok, degraded_projection} =
               ProductService.memories(managed_repo_id, workspace_path, allow_stale?: true)

      assert degraded_projection.graph.state == :degraded
      assert degraded_projection.result_group.degraded? == true
      assert degraded_projection.result_group.stale? == true
    end
  end

  defp seed_memory_graph!(managed_repo_id, workspace_path, revision) do
    assert {:ok, _refresh_result} =
             AgentWorkspace.refresh_memory_graph(
               managed_repo_id,
               workspace_path,
               revision: revision
             )

    session_id = "session-#{System.unique_integer([:positive])}"

    assert {:ok, _session_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.work_session(
                 session_id: session_id,
                 actor_id: "system:memory-graph-product-service",
                 workflow: :plan,
                 work_item_id: "work-32",
                 goal: "Seed memory graph product service"
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, plan_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               CaptureEnvelope.plan(
                 session_id: session_id,
                 actor_id: "system:memory-graph-product-service",
                 workflow: :plan,
                 work_item_id: "work-32",
                 content: "Generated a bounded plan artifact for the repository.",
                 anchors: %{module_name: "ExampleWorkspace"},
                 governed_context: %{run_id: "run-32", evidence_id: "evidence-32"}
               ),
               graph_name: MemoryGraph.workflow_provenance_graph_name(),
               revision: revision
             )

    assert {:ok, memory_result} =
             AgentWorkspace.record_memory_graph(
               managed_repo_id,
               workspace_path,
               DurableMemoryEnvelope.decision(
                 session_id: session_id,
                 actor_id: "system:memory-graph-product-service",
                 workflow: :review,
                 work_item_id: "work-32",
                 content: "Repository decisions should keep ExampleWorkspace.greet/1 stable.",
                 rationale: "Greeting behavior is used as a stable onboarding example.",
                 decision_status: :accepted,
                 revision: revision,
                 anchors: %{module_name: "ExampleWorkspace"},
                 governed_context: %{run_id: "run-32", work_item_id: "work-32"},
                 classification: %{
                   source: "product_service_test",
                   reason: "Section 32.1 needs durable memory for bounded recall tests."
                 }
               ),
               revision: revision
             )

    %{
      memory_resource_iri: memory_result.capture.resource_iri,
      plan_resource_iri: plan_result.capture.resource_iri,
      session_id: session_id
    }
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_memory_graph_product_service_#{System.unique_integer([:positive])}")

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule Example.MixProject do
        use Mix.Project

        def project do
          [app: :example, version: "0.1.0", elixir: "~> 1.18", deps: []]
        end
      end
      """
    )

    rewrite_workspace_module!(workspace_path, "ExampleWorkspace")
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
end
