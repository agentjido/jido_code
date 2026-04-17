defmodule JidoCode.WorkflowRuntime.JidoWorkflowCompatibilityTest do
  # covers: workflow.runtime.compatibility.local_override_present
  # covers: workflow.runtime.compatibility.legacy_loader_and_engine_surface
  # covers: workflow.runtime.compatibility.action_workflow_execution
  use ExUnit.Case, async: false

  alias JidoWorkflow.Workflow.Engine
  alias JidoWorkflow.Workflow.Loader

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

  test "legacy workflow loader and engine stay executable through the local compatibility package" do
    workflow_path = write_workflow_fixture!(valid_workflow_markdown())

    assert {:ok, definition} = Loader.load_markdown(workflow_path)
    assert definition.name == "example_workflow"
    assert Enum.map(definition.inputs, & &1.name) == ["file_path"]

    assert {:ok, result} =
             Engine.execute_definition(
               definition,
               %{"file_path" => "lib/example.ex"},
               workflow_id: definition.name,
               run_id: "workflow-compatibility-runtime"
             )

    assert result.status == :completed
    assert result.workflow_id == "example_workflow"
    assert result.run_id == "workflow-compatibility-runtime"
    assert result.result["file_path"] == "lib/example.ex"
    assert result.workflow.name == "example_workflow"
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

  defp write_workflow_fixture!(contents) do
    root =
      Path.join(
        System.tmp_dir!(),
        "jido-code-workflow-compatibility-#{System.unique_integer([:positive])}"
      )

    on_exit(fn -> File.rm_rf(root) end)

    File.mkdir_p!(root)

    workflow_path = Path.join(root, "example_workflow.md")
    File.write!(workflow_path, contents)
    workflow_path
  end
end
