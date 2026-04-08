defmodule JidoCode.AgentOSSourceCodeGraphAgentAdoptionTest do
  # covers: architecture.source_code_graph_pod.explicit_actions_drive_analyze_load_refresh_and_query
  # covers: architecture.source_code_graph_pod.sparql_library_is_canonical_query_surface
  use ExUnit.Case, async: true

  alias JidoCode.Actions.{
    FindSourceCodeGraphFunctions,
    FindSourceCodeGraphModules,
    FindSourceCodeGraphRuntimePatterns,
    QuerySourceCodeGraph,
    TraceSourceCodeGraphImpact
  }

  alias JidoCode.Agents.{Coder, Explainer, Planner, Refactorer, Reviewer}

  describe "selected coding specialists" do
    test "planner composes explicit semantic graph helper tools" do
      planner = Planner.new()
      tools = planner.state.__strategy__.config.tools
      prompt = planner.state.__strategy__.config.system_prompt

      assert FindSourceCodeGraphModules in tools
      assert FindSourceCodeGraphFunctions in tools
      assert TraceSourceCodeGraphImpact in tools
      assert prompt =~ "explicit"
      assert prompt =~ "source-code graph"
    end

    test "reviewer composes explicit semantic query tools" do
      reviewer = Reviewer.new()
      tools = reviewer.state.__strategy__.config.tools
      prompt = reviewer.state.__strategy__.config.system_prompt

      assert QuerySourceCodeGraph in tools
      assert FindSourceCodeGraphFunctions in tools
      assert FindSourceCodeGraphRuntimePatterns in tools
      assert TraceSourceCodeGraphImpact in tools
      assert prompt =~ "explicit tool calls"
    end

    test "explainer composes explicit semantic lookup tools" do
      explainer = Explainer.new()
      tools = explainer.state.__strategy__.config.tools
      prompt = explainer.state.__strategy__.config.system_prompt

      assert QuerySourceCodeGraph in tools
      assert FindSourceCodeGraphModules in tools
      assert FindSourceCodeGraphFunctions in tools
      assert prompt =~ "semantic graph tools"
    end

    test "coder and refactorer remain free of semantic graph tools by default" do
      coder_tools = Coder.new().state.__strategy__.config.tools
      refactorer_tools = Refactorer.new().state.__strategy__.config.tools

      refute QuerySourceCodeGraph in coder_tools
      refute FindSourceCodeGraphModules in coder_tools
      refute TraceSourceCodeGraphImpact in coder_tools

      refute QuerySourceCodeGraph in refactorer_tools
      refute FindSourceCodeGraphFunctions in refactorer_tools
      refute FindSourceCodeGraphRuntimePatterns in refactorer_tools
    end
  end
end
