defmodule JidoCode.PhaseTwentySevenIntegrationTest do
  # covers: architecture.source_code_graph_product_adoption.semantic_workflows_request_explicit_graph_context
  # covers: architecture.source_code_graph_product_adoption.semantic_findings_rejoin_governed_product_records
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: docs.product_foundation.readme_source_graph_orientation_present
  use JidoCode.DataCase, async: false

  alias JidoCode.Control.{Actor, ManagedRepo}
  alias JidoCode.Projects.Project
  alias JidoCode.SourceCodeGraph.WorkflowService

  setup do
    previous = Application.get_env(:jido_code, :source_code_graph_enabled, false)
    Application.put_env(:jido_code, :source_code_graph_enabled, true)

    workspace_path_one = create_workspace_path!("ExampleWorkspaceOne")
    workspace_path_two = create_workspace_path!("ExampleWorkspaceTwo")

    on_exit(fn ->
      Application.put_env(:jido_code, :source_code_graph_enabled, previous)
      File.rm_rf!(workspace_path_one)
      File.rm_rf!(workspace_path_two)
    end)

    {:ok, workspace_path_one: workspace_path_one, workspace_path_two: workspace_path_two}
  end

  test "27.3.1.2 workflow entrypoints fail safely and preserve explicit freshness metadata", %{
    workspace_path_one: workspace_path
  } do
    managed_repo = create_managed_repo!("phase-27-safe-failure")

    assert {:error, :source_code_graph_not_ready, error} =
             WorkflowService.plan(
               managed_repo.id,
               "work-#{System.unique_integer([:positive])}",
               "Plan with missing graph",
               workspace_path: workspace_path,
               semantic: [
                 workspace_path: workspace_path,
                 prepare: :none,
                 modules: [module_name_contains: "ExampleWorkspaceOne"]
               ]
             )

    assert error.feedback.state == :not_ready
    assert error.feedback.recovery.action == :load
    assert error.error.remediation == "Open repo detail to load semantic graph data."
  end

  test "27.3.1.3 multi-repository semantic workflow behavior stays isolated and consistent", %{
    workspace_path_one: workspace_path_one,
    workspace_path_two: workspace_path_two
  } do
    managed_repo_one = create_managed_repo!("phase-27-isolated-one")
    managed_repo_two = create_managed_repo!("phase-27-isolated-two")

    assert {:ok, _load_two} =
             JidoCode.AgentWorkspace.load_source_code_graph(
               managed_repo_two.id,
               workspace_path_two,
               revision: "rev-27-two"
             )

    assert {:error, :source_code_graph_not_ready, not_ready_error} =
             WorkflowService.review(
               managed_repo_one.id,
               "review-#{System.unique_integer([:positive])}",
               "Review repo without loaded graph",
               workspace_path: workspace_path_one,
               semantic: [
                 workspace_path: workspace_path_one,
                 prepare: :none,
                 functions: [module_name: "ExampleWorkspaceOne", function_name: "greet"]
               ]
             )

    assert not_ready_error.feedback.state == :not_ready
    assert not_ready_error.feedback.recovery.action == :load

    assert {:ok, ready_result} =
             WorkflowService.review(
               managed_repo_two.id,
               "review-#{System.unique_integer([:positive])}",
               "Review fresh repo",
               workspace_path: workspace_path_two,
               semantic: [
                 workspace_path: workspace_path_two,
                 prepare: :none,
                 functions: [module_name: "ExampleWorkspaceTwo", function_name: "greet"]
               ]
             )

    assert ready_result.semantic_input.freshness.state == :ready
    assert ready_result.semantic_input.graph.imported_revision == "rev-27-two"
  end

  test "27.3.2.1 contributor verification surfaces include the semantic product stack" do
    mixfile = File.read!("mix.exs")
    readme = File.read!("README.md")
    contributing = File.read!("CONTRIBUTING.md")
    agents = File.read!("AGENTS.md")

    assert mixfile =~ "\"semantic.verify\""
    assert mixfile =~ "\"source_graph.verify\""
    assert readme =~ "mix semantic.verify"
    assert contributing =~ "mix semantic.verify"
    assert agents =~ "mix semantic.verify"
    assert contributing =~ "bounded enhancement"
  end

  defp create_managed_repo!(name) do
    {:ok, project} =
      Project.create(%{
        name: name,
        github_full_name: "owner/#{name}",
        default_branch: "main",
        settings: %{}
      })

    {:ok, managed_repo} =
      ManagedRepo.get_by_legacy_project_id(project.id, actor: Actor.operator_actor())

    managed_repo
  end

  defp create_workspace_path!(module_name) do
    workspace_path =
      System.tmp_dir!()
      |> Path.join("jido_code_phase_twenty_seven_#{module_name}_#{System.unique_integer([:positive])}")

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
      defmodule #{module_name} do
        def greet(name), do: "hello \#{name}"
      end
      """
    )

    workspace_path
  end
end
