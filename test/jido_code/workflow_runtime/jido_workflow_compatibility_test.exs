defmodule JidoCode.WorkflowRuntime.JidoWorkflowCompatibilityTest do
  # covers: workflow.runtime.compatibility.local_override_present
  # covers: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  # covers: workflow.runtime.compatibility.action_workflow_execution
  use ExUnit.Case, async: false

  alias Jido.Code.Server, as: Runtime
  alias Jido.Code.Server.TestSupport.TempProject

  defmodule WorkflowEchoAction do
    use Jido.Action,
      name: "workflow_compatibility_echo_action",
      schema: [
        file_path: [type: :string, required: true]
      ]

    @impl true
    def run(%{file_path: file_path}, _context) do
      {:ok, %{"file_path" => file_path}}
    end
  end

  setup do
    on_exit(fn ->
      Enum.each(Runtime.list_projects(), fn %{project_id: project_id} ->
        _ = Runtime.stop_project(project_id)
      end)
    end)

    :ok
  end

  test "workflow asset tools stay registered and executable through the local compatibility runtime" do
    root = TempProject.create!(with_seed_files: true)
    on_exit(fn -> TempProject.cleanup(root) end)

    workflow_path = Path.join(root, ".jido/workflows/example_workflow.md")
    File.write!(workflow_path, valid_workflow_markdown())

    assert {:ok, project_id} =
             Runtime.start_project(root,
               project_id: "workflow-compatibility-runtime",
               network_egress_policy: :allow
             )

    workflow_tool =
      project_id
      |> Runtime.list_tools()
      |> Enum.find(&(&1.name == "workflow.run.example_workflow"))

    assert workflow_tool.kind == :workflow_run
    assert workflow_tool.asset_name == "example_workflow"
    assert get_in(workflow_tool, [:input_schema, "properties", "file_path", "type"]) == "string"
    assert get_in(workflow_tool, [:input_schema, "properties", "inputs", "required"]) == ["file_path"]

    assert {:ok, %{status: :ok, tool: "workflow.run.example_workflow", result: result}} =
             Runtime.run_tool(project_id, %{
               name: "workflow.run.example_workflow",
               args: %{"inputs" => %{"file_path" => "lib/example.ex"}}
             })

    assert result.mode == :executed
    assert result.runtime == :jido_workflow
    assert result.workflow == "example_workflow"
    assert get_in(result, [:execution, :status]) == :completed
    assert get_in(result, [:execution, :workflow_id]) == "example_workflow"
    assert get_in(result, [:execution, :result, "file_path"]) == "lib/example.ex"
  end

  defp valid_workflow_markdown do
    """
    ---
    name: example_workflow
    version: "1.0.0"
    description: Example workflow fixture for compatibility runtime tests
    enabled: true
    inputs:
      - name: file_path
        type: string
        required: true
        description: Path to file
    ---
    # Example Workflow

    ## Steps

    ### echo
    - **type**: action
    - **module**: JidoCode.WorkflowRuntime.JidoWorkflowCompatibilityTest.WorkflowEchoAction
    - **inputs**:
      - file_path: `input:file_path`

    ## Return
    - **value**: echo
    """
  end
end
