defmodule JidoCode.Pods.SourceCodeGraphPod do
  # covers: architecture.repository_runtime_integration.source_code_graph_pod_singleton_when_enabled
  # covers: architecture.source_code_graph_pod.repo_scoped_source_code_graph_pod
  @moduledoc """
  Repository-scoped pod for semantic source-code graph work.

  The pod owns one eager graph context agent for repository-local graph/store
  metadata and lazy specialist agents for ontology analysis, named-graph load
  and refresh, and semantic query execution.
  """

  use Jido.Pod,
    name: "source_code_graph_pod",
    topology: %{
      source_code_graph_context: %{
        agent: JidoCode.Agents.SourceCodeGraphContext,
        manager: :jido_code_source_code_graph_contexts,
        activation: :eager
      },
      source_code_graph_analyzer: %{
        agent: JidoCode.Agents.SourceCodeGraphAnalyzer,
        manager: :jido_code_source_code_graph_analyzers,
        activation: :lazy
      },
      source_code_graph_loader: %{
        agent: JidoCode.Agents.SourceCodeGraphLoader,
        manager: :jido_code_source_code_graph_loaders,
        activation: :lazy
      },
      source_code_graph_querier: %{
        agent: JidoCode.Agents.SourceCodeGraphQuerier,
        manager: :jido_code_source_code_graph_queriers,
        activation: :lazy
      }
    }
end
