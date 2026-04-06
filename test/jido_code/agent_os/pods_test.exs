defmodule JidoCode.AgentOSPodsTest do
  # covers: architecture.agent_os_integration.pod_hierarchy
  use ExUnit.Case, async: true

  alias JidoCode.AgentOS.Pods.{RepoPod, CodingPod}
  alias JidoCode.AgentOS.Agents.{RepoMonitor, WorkRegistry, TaskBoard, ProjectContext}

  describe "RepoPod" do
    test "module exists and is a pod" do
      assert function_exported?(RepoPod, :pod?, 0)
      assert RepoPod.pod?() == true
    end

    test "has correct pod configuration" do
      assert RepoPod.name() == "repo_pod"
      assert is_map(RepoPod.topology())
    end

    test "has eager agents configured" do
      topology = RepoPod.topology()
      nodes = topology.nodes

      assert nodes.repo_monitor.module == RepoMonitor
      assert nodes.repo_monitor.activation == :eager
      assert nodes.work_registry.module == WorkRegistry
      assert nodes.work_registry.activation == :eager
    end
  end

  describe "CodingPod" do
    test "module exists and is a pod" do
      assert function_exported?(CodingPod, :pod?, 0)
      assert CodingPod.pod?() == true
    end

    test "has correct pod configuration" do
      assert CodingPod.name() == "coding_pod"
      assert is_map(CodingPod.topology())
    end

    test "has eager agents configured" do
      topology = CodingPod.topology()
      nodes = topology.nodes

      assert nodes.task_board.module == TaskBoard
      assert nodes.task_board.activation == :eager
      assert nodes.project_context.module == ProjectContext
      assert nodes.project_context.activation == :eager
    end
  end

  describe "RepoMonitor agent" do
    test "has correct name and schema" do
      assert RepoMonitor.name() == "repo_monitor"
      assert is_map(RepoMonitor.schema())
    end
  end

  describe "WorkRegistry agent" do
    test "has correct name and schema" do
      assert WorkRegistry.name() == "work_registry"
      assert is_map(WorkRegistry.schema())
    end
  end

  describe "TaskBoard agent" do
    test "has correct name and schema" do
      assert TaskBoard.name() == "task_board"
      assert is_map(TaskBoard.schema())
    end
  end

  describe "ProjectContext agent" do
    test "has correct name and schema" do
      assert ProjectContext.name() == "project_context"
      assert is_map(ProjectContext.schema())
    end
  end
end
