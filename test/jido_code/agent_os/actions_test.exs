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
    UpdateWorkItemStatus
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
end
