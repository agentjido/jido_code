defmodule JidoCode.Pods.MemoryGraphPod do
  # covers: architecture.repository_runtime_integration.memory_graph_pod_singleton_when_enabled
  # covers: architecture.memory_graph.repo_scoped_memory_graph_pod
  @moduledoc """
  Repository-scoped pod for durable coding memory and workflow provenance work.

  The pod owns one eager memory graph context agent for repository-local graph,
  revision, and failure metadata, plus lazy specialists for recording, querying,
  and validating repository memory state.
  """

  use Jido.Pod,
    name: "memory_graph_pod",
    topology: %{
      memory_graph_context: %{
        agent: JidoCode.Agents.MemoryGraphContext,
        manager: :jido_code_memory_graph_contexts,
        activation: :eager
      },
      memory_graph_recorder: %{
        agent: JidoCode.Agents.MemoryGraphRecorder,
        manager: :jido_code_memory_graph_recorders,
        activation: :lazy
      },
      memory_graph_querier: %{
        agent: JidoCode.Agents.MemoryGraphQuerier,
        manager: :jido_code_memory_graph_queriers,
        activation: :lazy
      },
      memory_graph_validator: %{
        agent: JidoCode.Agents.MemoryGraphValidator,
        manager: :jido_code_memory_graph_validators,
        activation: :lazy
      }
    }
end
