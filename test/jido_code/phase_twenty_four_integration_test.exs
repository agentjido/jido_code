defmodule JidoCode.PhaseTwentyFourIntegrationTest do
  # covers: architecture.source_code_graph_product_adoption.product_owned_semantic_service_boundary
  # covers: architecture.source_code_graph_product_adoption.semantic_operator_surfaces_show_freshness_and_recovery
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: architecture.source_code_graph_product_adoption.operator_surfaces_do_not_expose_raw_graph_internals
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

  describe "24.3.1 Product service boundary scenarios" do
    test "24.3.1.1 product semantic services return bounded repo-scoped projections without raw graph internals" do
      managed_repo = create_managed_repo!()
      workspace_path = create_workspace_path!("PhaseTwentyFour.Alpha")

      assert {:ok, _load_result} =
               JidoCode.AgentWorkspace.load_source_code_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-24-1"
               )

      assert {:ok, modules} =
               ProductService.modules(
                 managed_repo.id,
                 workspace_path,
                 module_name_contains: "PhaseTwentyFour",
                 revision: "rev-24-1"
               )

      assert modules.kind == :modules
      assert modules.managed_repo_id == managed_repo.id
      assert modules.graph.state == :ready
      assert modules.result_group.count >= 1
      refute Map.has_key?(modules, :bindings)
      refute Map.has_key?(modules, :compiled_sparql)
      refute Map.has_key?(modules, :pod_id)

      assert Enum.any?(modules.items, fn item ->
               item.module_name == "PhaseTwentyFour.Alpha"
             end)
    end

    test "24.3.1.2 stale graph state stays explicit at the product boundary with bounded recovery affordances" do
      managed_repo = create_managed_repo!()
      workspace_path = create_workspace_path!("PhaseTwentyFour.Beta")

      assert {:ok, _load_result} =
               JidoCode.AgentWorkspace.load_source_code_graph(managed_repo.id, workspace_path)

      rewrite_workspace_module!(workspace_path, "PhaseTwentyFour.Gamma")

      assert {:error, :source_code_graph_stale, stale_projection} =
               ProductService.modules(managed_repo.id, workspace_path)

      assert stale_projection.graph.state == :stale
      assert stale_projection.graph.stale? == true
      assert stale_projection.graph.recovery_action == :refresh
      assert stale_projection.error.type == :source_code_graph_stale

      assert {:ok, degraded_projection} =
               ProductService.modules(managed_repo.id, workspace_path, allow_stale?: true)

      assert degraded_projection.graph.state == :degraded
      assert degraded_projection.graph.stale? == true
      assert degraded_projection.result_group.degraded? == true
    end
  end

  describe "24.3.2 Governed materialization scenarios" do
    test "24.3.2.1 semantic findings only influence the control plane after explicit materialization" do
      managed_repo = create_managed_repo!()
      workspace_path = create_workspace_path!("PhaseTwentyFour.Delta")

      assert {:ok, _load_result} =
               JidoCode.AgentWorkspace.load_source_code_graph(
                 managed_repo.id,
                 workspace_path,
                 revision: "rev-24-2"
               )

      assert {:ok, projection} =
               ProductService.impact(
                 managed_repo.id,
                 workspace_path,
                 module_name: "PhaseTwentyFour.Delta",
                 revision: "rev-24-2"
               )

      assert {:ok, []} =
               Observation.read(
                 query: [filter: [managed_repo_id: managed_repo.id, source: "source_code_graph"]],
                 actor: Actor.operator_actor()
               )

      assert {:ok, work_seed} =
               ProductService.work_item_seed(
                 projection,
                 query: %{module_name: "PhaseTwentyFour.Delta"}
               )

      assert {:ok, evidence_input} =
               ProductService.evidence_input(
                 projection,
                 query: %{module_name: "PhaseTwentyFour.Delta"}
               )

      assert work_seed.work_metadata["source"] == "source_code_graph"
      assert evidence_input.evidence_details["graph"]["imported_revision"] == "rev-24-2"

      assert {:ok, %{observation: observation, assessment: assessment}} =
               ProductService.materialize_assessment(
                 projection,
                 query: %{module_name: "PhaseTwentyFour.Delta"}
               )

      assert observation.managed_repo_id == managed_repo.id
      assert observation.source == "source_code_graph"
      assert assessment.managed_repo_id == managed_repo.id
      assert assessment.inputs["graph"]["imported_revision"] == "rev-24-2"

      assert {:ok, observations} =
               Observation.read(
                 query: [filter: [managed_repo_id: managed_repo.id, source: "source_code_graph"]],
                 actor: Actor.operator_actor()
               )

      assert length(observations) == 1

      assert {:ok, assessments} =
               Assessment.read(
                 query: [filter: [managed_repo_id: managed_repo.id, category: "semantic_impact_finding"]],
                 actor: Actor.operator_actor()
               )

      assert length(assessments) == 1
    end
  end

  defp create_managed_repo! do
    name = "phase-24-#{System.unique_integer([:positive])}"

    {:ok, %{managed_repo: managed_repo}} =
      RepoBridge.upsert_managed_repo(%{
        name: name,
        full_name: "owner/#{name}",
        default_branch: "main",
        workspace_settings: %{"clone_status" => "ready", "workspace_initialized" => true}
      })

    managed_repo
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      Path.join(
        System.tmp_dir!(),
        "jido_code_phase_twenty_four_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(Path.join(workspace_path, "lib"))

    File.write!(
      Path.join(workspace_path, "mix.exs"),
      """
      defmodule PhaseTwentyFour.MixProject do
        use Mix.Project

        def project do
          [app: :phase_twenty_four_example, version: "0.1.0", elixir: "~> 1.18", deps: []]
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
