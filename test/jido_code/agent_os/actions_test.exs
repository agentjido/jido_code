defmodule JidoCode.AgentOSActionsTest do
  # covers: architecture.agent_os_integration.actions
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    ReadFile,
    WriteFile,
    ListFiles,
    SearchCode,
    RunTests,
    GitStatus,
    GitDiff,
    AddTask,
    SelectTask,
    StoreArtifact,
    AppendEvent,
    GetWorkItem,
    UpdateWorkItemStatus,
    AnalyzeSourceCodeGraph,
    LoadSourceCodeGraph,
    RefreshSourceCodeGraph,
    GetSourceCodeGraphStatus,
    QuerySourceCodeGraph,
    InspectSourceCodeGraphDataset,
    FindSourceCodeGraphModules,
    FindSourceCodeGraphFunctions,
    FindSourceCodeGraphRuntimePatterns,
    TraceSourceCodeGraphImpact
  }

  describe "ReadFile action" do
    test "has correct action configuration" do
      assert ReadFile.name() == "jido_code_read_file"
      assert function_exported?(ReadFile, :run, 2)
    end

    test "returns bounded output diagnostics" do
      workspace_path = workspace_path!()
      File.write!(Path.join(workspace_path, "large.txt"), String.duplicate("x", 12_000))

      assert {:ok, result} =
               ReadFile.run(%{path: "large.txt", max_chars: 50_000}, %{tool_context: %{workspace_path: workspace_path}})

      assert result.truncated?
      assert result.budget.state == :truncated
      assert result.budget.truncated_by_byte_limit?
    end
  end

  describe "WriteFile action" do
    test "has correct action configuration" do
      assert WriteFile.name() == "jido_code_write_file"
      assert function_exported?(WriteFile, :run, 2)
    end
  end

  describe "ListFiles action" do
    test "has correct action configuration" do
      assert ListFiles.name() == "jido_code_list_files"
      assert function_exported?(ListFiles, :run, 2)
    end

    test "clamps list results with budget diagnostics" do
      workspace_path = workspace_path!()

      Enum.each(1..5, fn index ->
        File.write!(Path.join(workspace_path, "file_#{index}.ex"), "defmodule Example#{index} do\nend\n")
      end)

      assert {:ok, result} =
               ListFiles.run(%{path: ".", recursive: false, extensions: nil, include_hidden: false, max_results: 2}, %{
                 tool_context: %{workspace_path: workspace_path}
               })

      assert result.truncated?
      assert result.count == 2
      assert result.budget.state == :truncated
      assert result.budget.truncated_by_action_limit?
    end
  end

  describe "SearchCode action" do
    test "has correct action configuration" do
      assert SearchCode.name() == "jido_code_search_code"
      assert function_exported?(SearchCode, :run, 2)
    end

    test "clamps search results with budget diagnostics" do
      workspace_path = workspace_path!()

      Enum.each(1..5, fn index ->
        File.write!(
          Path.join(workspace_path, "search_#{index}.ex"),
          "defmodule Search#{index} do\n  def marker, do: :ok\nend\n"
        )
      end)

      assert {:ok, result} =
               SearchCode.run(
                 %{
                   query: "marker",
                   path: ".",
                   case_sensitive: false,
                   regex: false,
                   file_pattern: "*.ex",
                   max_results: 2
                 },
                 %{tool_context: %{workspace_path: workspace_path}}
               )

      assert result.truncated?
      assert result.count == 2
      assert result.budget.state == :truncated
      assert result.budget.truncated_by_action_limit?
    end
  end

  describe "RunTests action" do
    test "has correct action configuration" do
      assert RunTests.name() == "jido_code_run_tests"
      assert function_exported?(RunTests, :run, 2)
    end
  end

  describe "GitStatus action" do
    test "has correct action configuration" do
      assert GitStatus.name() == "jido_code_git_status"
      assert function_exported?(GitStatus, :run, 2)
    end
  end

  describe "GitDiff action" do
    test "has correct action configuration" do
      assert GitDiff.name() == "jido_code_git_diff"
      assert function_exported?(GitDiff, :run, 2)
    end
  end

  describe "AddTask action" do
    test "has correct action configuration" do
      assert AddTask.name() == "jido_code_add_task"
      assert function_exported?(AddTask, :run, 2)
    end
  end

  describe "SelectTask action" do
    test "has correct action configuration" do
      assert SelectTask.name() == "jido_code_select_task"
      assert function_exported?(SelectTask, :run, 2)
    end
  end

  describe "StoreArtifact action" do
    test "has correct action configuration" do
      assert StoreArtifact.name() == "jido_code_store_artifact"
      assert function_exported?(StoreArtifact, :run, 2)
    end
  end

  describe "AppendEvent action" do
    test "has correct action configuration" do
      assert AppendEvent.name() == "jido_code_append_event"
      assert function_exported?(AppendEvent, :run, 2)
    end
  end

  describe "GetWorkItem action" do
    test "has correct action configuration" do
      assert GetWorkItem.name() == "jido_code_get_work_item"
      assert function_exported?(GetWorkItem, :run, 2)
    end
  end

  describe "UpdateWorkItemStatus action" do
    test "has correct action configuration" do
      assert UpdateWorkItemStatus.name() == "jido_code_update_work_item_status"
      assert function_exported?(UpdateWorkItemStatus, :run, 2)
    end
  end

  describe "AnalyzeSourceCodeGraph action" do
    test "has correct action configuration" do
      assert AnalyzeSourceCodeGraph.name() == "jido_code_analyze_source_code_graph"
      assert function_exported?(AnalyzeSourceCodeGraph, :run, 2)
    end
  end

  describe "LoadSourceCodeGraph action" do
    test "has correct action configuration" do
      assert LoadSourceCodeGraph.name() == "jido_code_load_source_code_graph"
      assert function_exported?(LoadSourceCodeGraph, :run, 2)
    end
  end

  describe "RefreshSourceCodeGraph action" do
    test "has correct action configuration" do
      assert RefreshSourceCodeGraph.name() == "jido_code_refresh_source_code_graph"
      assert function_exported?(RefreshSourceCodeGraph, :run, 2)
    end
  end

  describe "GetSourceCodeGraphStatus action" do
    test "has correct action configuration" do
      assert GetSourceCodeGraphStatus.name() == "jido_code_get_source_code_graph_status"
      assert function_exported?(GetSourceCodeGraphStatus, :run, 2)
    end
  end

  describe "QuerySourceCodeGraph action" do
    test "has correct action configuration" do
      assert QuerySourceCodeGraph.name() == "jido_code_query_source_code_graph"
      assert function_exported?(QuerySourceCodeGraph, :run, 2)
    end
  end

  describe "InspectSourceCodeGraphDataset action" do
    test "has correct action configuration" do
      assert InspectSourceCodeGraphDataset.name() == "jido_code_inspect_source_code_graph_dataset"
      assert function_exported?(InspectSourceCodeGraphDataset, :run, 2)
    end
  end

  describe "FindSourceCodeGraphModules action" do
    test "has correct action configuration" do
      assert FindSourceCodeGraphModules.name() == "jido_code_find_source_code_graph_modules"
      assert function_exported?(FindSourceCodeGraphModules, :run, 2)
    end
  end

  describe "FindSourceCodeGraphFunctions action" do
    test "has correct action configuration" do
      assert FindSourceCodeGraphFunctions.name() == "jido_code_find_source_code_graph_functions"
      assert function_exported?(FindSourceCodeGraphFunctions, :run, 2)
    end
  end

  describe "FindSourceCodeGraphRuntimePatterns action" do
    test "has correct action configuration" do
      assert FindSourceCodeGraphRuntimePatterns.name() ==
               "jido_code_find_source_code_graph_runtime_patterns"

      assert function_exported?(FindSourceCodeGraphRuntimePatterns, :run, 2)
    end
  end

  describe "TraceSourceCodeGraphImpact action" do
    test "has correct action configuration" do
      assert TraceSourceCodeGraphImpact.name() == "jido_code_trace_source_code_graph_impact"
      assert function_exported?(TraceSourceCodeGraphImpact, :run, 2)
    end
  end

  defp workspace_path! do
    workspace_path =
      Path.join(System.tmp_dir!(), "jido-code-agent-os-actions-#{System.unique_integer([:positive])}")

    File.mkdir_p!(workspace_path)
    on_exit(fn -> File.rm_rf(workspace_path) end)
    workspace_path
  end
end
