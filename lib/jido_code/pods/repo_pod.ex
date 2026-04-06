defmodule JidoCode.Pods.RepoPod do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.pod_hierarchy
  @moduledoc """
  Repository-level pod for monitoring repository state and tracking work.

  This pod is instantiated once per kernel (one per ManagedRepo) and contains
  eager agents that continuously monitor the repository and track active work.

  ## Agents

  * `RepoMonitor` - Tracks git status, file changes, and repository state
  * `WorkRegistry` - Tracks all active WorkItems and their associated CodingPods

  ## Lifecycle

  This pod is started when the kernel is created and remains active for the
  lifetime of the kernel, providing persistent monitoring and registry capabilities.
  """

  use Jido.AgentOS.Pod,
    name: "repo_pod",
    topology: %{
      repo_monitor: %{
        agent: JidoCode.Agents.RepoMonitor,
        manager: :repo_monitor,
        activation: :eager
      },
      work_registry: %{
        agent: JidoCode.Agents.WorkRegistry,
        manager: :work_registry,
        activation: :eager
      }
    }
end
