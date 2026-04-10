defmodule JidoCode.Pods.MemoryGraphPod do
  # covers: architecture.agent_os_integration.memory_graph_pod_singleton_when_enabled
  # covers: architecture.memory_graph.repo_scoped_memory_graph_pod
  @moduledoc """
  Repository-scoped pod for durable coding memory and workflow provenance work.

  The pod owns one eager memory graph context agent for repository-local graph,
  revision, and failure metadata, plus lazy specialists for recording, querying,
  and validating repository memory state.
  """

  use Jido.AgentOS.Pod,
    name: "memory_graph_pod",
    signal_routes: [
      {"jido.agent.child.started", Jido.Actions.Control.Noop},
      {"jido.agent.child.exit", Jido.Actions.Control.Noop},
      {"jido.agent.orphaned", Jido.Actions.Control.Noop}
    ],
    topology: %{
      memory_graph_context: %{
        agent: JidoCode.Agents.MemoryGraphContext,
        manager: :memory_graph_context,
        activation: :eager
      },
      memory_graph_recorder: %{
        agent: JidoCode.Agents.MemoryGraphRecorder,
        manager: :memory_graph_record,
        activation: :lazy
      },
      memory_graph_querier: %{
        agent: JidoCode.Agents.MemoryGraphQuerier,
        manager: :memory_graph_query,
        activation: :lazy
      },
      memory_graph_validator: %{
        agent: JidoCode.Agents.MemoryGraphValidator,
        manager: :memory_graph_validate,
        activation: :lazy
      }
    }
end
