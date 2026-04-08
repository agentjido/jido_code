defmodule JidoCode.AgentOSPodsTest do
  # covers: architecture.agent_os_integration.pod_hierarchy
  use ExUnit.Case, async: true

  alias JidoCode.Pods.{RepoPod, CodingPod, SourceCodeGraphPod}

  alias JidoCode.Agents.{
    RepoMonitor,
    WorkRegistry,
    TaskBoard,
    ProjectContext,
    SourceCodeGraphContext,
    SourceCodeGraphAnalyzer,
    SourceCodeGraphLoader,
    SourceCodeGraphQuerier
  }

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

    test "has lazy AI agents configured" do
      topology = CodingPod.topology()
      nodes = topology.nodes

      # Verify lazy agents exist and are lazy
      assert nodes.planner.activation == :lazy
      assert nodes.coder.activation == :lazy
      assert nodes.reviewer.activation == :lazy
      assert nodes.refactorer.activation == :lazy
      assert nodes.explainer.activation == :lazy
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

      assert nodes.task_board.module == JidoCode.Agents.TaskBoard
      assert nodes.task_board.activation == :eager
      assert nodes.project_context.module == JidoCode.Agents.ProjectContext
      assert nodes.project_context.activation == :eager
    end
  end

  describe "SourceCodeGraphPod" do
    test "module exists and is a pod" do
      assert function_exported?(SourceCodeGraphPod, :pod?, 0)
      assert SourceCodeGraphPod.pod?() == true
    end

    test "has correct pod configuration" do
      assert SourceCodeGraphPod.name() == "source_code_graph_pod"
      assert is_map(SourceCodeGraphPod.topology())
    end

    test "has eager graph context and lazy specialist agents" do
      topology = SourceCodeGraphPod.topology()
      nodes = topology.nodes

      assert nodes.source_code_graph_context.module == SourceCodeGraphContext
      assert nodes.source_code_graph_context.activation == :eager

      assert nodes.source_code_graph_analyzer.module == SourceCodeGraphAnalyzer
      assert nodes.source_code_graph_analyzer.activation == :lazy

      assert nodes.source_code_graph_loader.module == SourceCodeGraphLoader
      assert nodes.source_code_graph_loader.activation == :lazy

      assert nodes.source_code_graph_querier.module == SourceCodeGraphQuerier
      assert nodes.source_code_graph_querier.activation == :lazy
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

  describe "SourceCodeGraphContext agent" do
    test "has correct name and schema" do
      assert SourceCodeGraphContext.name() == "source_code_graph_context"
      assert is_map(SourceCodeGraphContext.schema())
    end
  end
end
