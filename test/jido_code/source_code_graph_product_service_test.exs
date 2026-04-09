defmodule JidoCode.SourceCodeGraphProductServiceTest do
  use JidoCode.DataCase, async: false

  alias JidoCode.AgentWorkspace
  alias JidoCode.SourceCodeGraph.ProductService

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
end
