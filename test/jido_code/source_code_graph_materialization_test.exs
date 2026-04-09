defmodule JidoCode.SourceCodeGraphMaterializationTest do
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: package.jido_code.version_controlled_quality_surfaces
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, RepoBridge}
  alias JidoCode.Operations.{Assessment, Observation}
  alias JidoCode.SourceCodeGraph.ProductService

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
    end)

    :ok
  end

  test "builds a bounded semantic finding from a product projection" do
    managed_repo = create_managed_repo!()
    workspace_path = create_workspace_path!()

    assert {:ok, _load_result} =
             JidoCode.AgentWorkspace.load_source_code_graph(
               managed_repo.id,
               workspace_path,
               revision: "rev-1"
             )

    assert {:ok, projection} =
             ProductService.modules(
               managed_repo.id,
               workspace_path,
               module_name_contains: "ExampleWorkspace",
               revision: "rev-1"
             )

    assert {:ok, finding} =
             ProductService.to_finding(
               projection,
               query: %{module_name_contains: "ExampleWorkspace"}
             )

    assert finding.kind == :semantic_finding
    assert finding.managed_repo_id == managed_repo.id
    assert finding.finding_type == :modules
    assert finding.graph.imported_revision == "rev-1"
    assert finding.provenance.projection_kind == :modules
    assert finding.provenance.selected_count >= 1
    assert is_binary(finding.digest)
    refute Map.has_key?(finding.payload, :bindings)
  end

  test "materializes semantic findings into governed observation and assessment records" do
    managed_repo = create_managed_repo!()
    workspace_path = create_workspace_path!()

    assert {:ok, _load_result} =
             JidoCode.AgentWorkspace.load_source_code_graph(
               managed_repo.id,
               workspace_path,
               revision: "rev-2"
             )

    assert {:ok, projection} =
             ProductService.functions(
               managed_repo.id,
               workspace_path,
               module_name: "ExampleWorkspace",
               function_name: "greet",
               revision: "rev-2"
             )

    assert {:ok, %{finding: finding, observation: observation, event: event, assessment: assessment}} =
             ProductService.materialize_assessment(
               projection,
               query: %{module_name: "ExampleWorkspace", function_name: "greet"}
             )

    assert observation.managed_repo_id == managed_repo.id
    assert observation.source == "source_code_graph"
    assert observation.category == "semantic_function_finding"
    assert observation.payload["provenance"]["projection_kind"] == "functions"
    assert observation.payload["graph"]["imported_revision"] == "rev-2"

    assert event.observation_id == observation.id
    assert event.category == "semantic.source_code_graph.semantic_function_finding"

    assert assessment.event_id == event.id
    assert assessment.category == "semantic_function_finding"
    assert assessment.recommended_action == "review_semantic_function_finding"
    assert assessment.inputs["graph"]["imported_revision"] == "rev-2"
    assert assessment.assessment_metadata["semantic_finding_digest"] == finding.digest
  end

  test "keeps materialization optional while preserving stale graph metadata in work and evidence inputs" do
    managed_repo = create_managed_repo!()
    workspace_path = create_workspace_path!()

    assert {:ok, _load_result} =
             JidoCode.AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path)

    rewrite_workspace_module!(workspace_path, "ExampleWorkspaceRenamed")

    assert {:ok, projection} =
             ProductService.modules(
               managed_repo.id,
               workspace_path,
               module_name_contains: "ExampleWorkspace",
               allow_stale?: true
             )

    assert projection.graph.state == :degraded
    assert projection.graph.stale? == true

    assert {:ok, work_seed} =
             ProductService.work_item_seed(
               projection,
               query: %{module_name_contains: "ExampleWorkspace"}
             )

    assert work_seed.managed_repo_id == managed_repo.id
    assert work_seed.dedup_key =~ "semantic_finding:"
    assert work_seed.work_metadata["graph"]["stale?"] == true
    assert work_seed.work_metadata["graph"]["recovery_action"] == "refresh"

    assert {:ok, evidence_input} =
             ProductService.evidence_input(
               projection,
               query: %{module_name_contains: "ExampleWorkspace"}
             )

    assert evidence_input.managed_repo_id == managed_repo.id
    assert evidence_input.evidence_type == "source_code_graph_finding"
    assert evidence_input.evidence_details["graph"]["stale?"] == true
    assert evidence_input.source == "source_code_graph"

    assert {:ok, []} =
             Observation.read(
               query: [filter: [managed_repo_id: managed_repo.id, source: "source_code_graph"]],
               actor: Actor.operator_actor()
             )

    assert {:ok, []} =
             Assessment.read(
               query: [filter: [managed_repo_id: managed_repo.id]],
               actor: Actor.operator_actor()
             )
  end

  defp create_managed_repo! do
    name = "semantic-#{System.unique_integer([:positive])}"

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: name,
        full_name: "owner/#{name}",
        default_branch: "main",
        workspace_settings: %{"clone_status" => "ready", "workspace_initialized" => true}
      })

    managed_repo
  end

  defp create_workspace_path! do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_source_graph_materialization_#{System.unique_integer([:positive])}")

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
end
