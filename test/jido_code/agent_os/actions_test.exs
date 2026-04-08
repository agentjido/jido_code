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
    InspectSourceCodeGraphDataset
  }

  describe "ReadFile action" do
    test "has correct action configuration" do
      assert ReadFile.name() == "jido_code_read_file"
      assert function_exported?(ReadFile, :run, 2)
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
  end

  describe "SearchCode action" do
    test "has correct action configuration" do
      assert SearchCode.name() == "jido_code_search_code"
      assert function_exported?(SearchCode, :run, 2)
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
end
