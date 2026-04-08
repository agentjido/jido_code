defmodule JidoCode.Pods.SourceCodeGraphPod do
  # covers: architecture.agent_os_integration.source_code_graph_pod_singleton_when_enabled
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  @moduledoc """
  Repository-scoped pod for semantic source-code graph work.

  The pod owns one eager graph context agent for repository-local graph/store
  metadata and lazy specialist agents for ontology analysis, named-graph load
  and refresh, and semantic query execution.
  """

  use Jido.AgentOS.Pod,
    name: "source_code_graph_pod",
    signal_routes: [
      {"jido.agent.child.started", Jido.Actions.Control.Noop},
      {"jido.agent.child.exit", Jido.Actions.Control.Noop},
      {"jido.agent.orphaned", Jido.Actions.Control.Noop}
    ],
    topology: %{
      source_code_graph_context: %{
        agent: JidoCode.Agents.SourceCodeGraphContext,
        manager: :source_code_graph_context,
        activation: :eager
      },
      source_code_graph_analyzer: %{
        agent: JidoCode.Agents.SourceCodeGraphAnalyzer,
        manager: :source_code_graph_analysis,
        activation: :lazy
      },
      source_code_graph_loader: %{
        agent: JidoCode.Agents.SourceCodeGraphLoader,
        manager: :source_code_graph_load,
        activation: :lazy
      },
      source_code_graph_querier: %{
        agent: JidoCode.Agents.SourceCodeGraphQuerier,
        manager: :source_code_graph_query,
        activation: :lazy
      }
    }
end
