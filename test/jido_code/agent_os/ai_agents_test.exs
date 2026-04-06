defmodule JidoCode.AgentOSAIAgentsTest do
  # covers: architecture.agent_os_integration.coding_agents
  use ExUnit.Case, async: true

  alias JidoCode.Agents.{Planner, Coder, Reviewer, Refactorer, Explainer}
  alias JidoCode.Pods.CodingPod

  describe "CodingPod with AI agents" do
    test "module exists and is a pod" do
      assert function_exported?(CodingPod, :pod?, 0)
      assert CodingPod.pod?() == true
    end

    test "has all eager and lazy agents configured" do
      topology = CodingPod.topology()
      nodes = topology.nodes

      # Eager agents
      assert nodes.task_board.module == JidoCode.Agents.TaskBoard
      assert nodes.task_board.activation == :eager
      assert nodes.project_context.module == JidoCode.Agents.ProjectContext
      assert nodes.project_context.activation == :eager

      # Lazy AI agents
      assert nodes.planner.module == Planner
      assert nodes.planner.activation == :lazy
      assert nodes.coder.module == Coder
      assert nodes.coder.activation == :lazy
      assert nodes.reviewer.module == Reviewer
      assert nodes.reviewer.activation == :lazy
      assert nodes.refactorer.module == Refactorer
      assert nodes.refactorer.activation == :lazy
      assert nodes.explainer.module == Explainer
      assert nodes.explainer.activation == :lazy
    end
  end

  describe "Planner agent" do
    test "is an AI agent with ask function" do
      assert function_exported?(Planner, :ask, 2)
      assert function_exported?(Planner, :ask, 3)
    end

    test "has correct name" do
      assert Planner.name() == "jido_code_planner"
    end
  end

  describe "Coder agent" do
    test "is an AI agent with ask function" do
      assert function_exported?(Coder, :ask, 2)
      assert function_exported?(Coder, :ask, 3)
    end

    test "has correct name" do
      assert Coder.name() == "jido_code_coder"
    end
  end

  describe "Reviewer agent" do
    test "is an AI agent with ask function" do
      assert function_exported?(Reviewer, :ask, 2)
      assert function_exported?(Reviewer, :ask, 3)
    end

    test "has correct name" do
      assert Reviewer.name() == "jido_code_reviewer"
    end
  end

  describe "Refactorer agent" do
    test "is an AI agent with ask function" do
      assert function_exported?(Refactorer, :ask, 2)
      assert function_exported?(Refactorer, :ask, 3)
    end

    test "has correct name" do
      assert Refactorer.name() == "jido_code_refactorer"
    end
  end

  describe "Explainer agent" do
    test "is an AI agent with ask function" do
      assert function_exported?(Explainer, :ask, 2)
      assert function_exported?(Explainer, :ask, 3)
    end

    test "has correct name" do
      assert Explainer.name() == "jido_code_explainer"
    end
  end
end
