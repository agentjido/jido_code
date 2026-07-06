defmodule JidoCode.Pods.RepoPod do
  # covers: architecture.repository_runtime_integration.kernel_per_managed_repo
  # covers: architecture.repository_runtime_integration.repo_pod_singleton_per_kernel
  # covers: architecture.repository_runtime_integration.pod_hierarchy
  @moduledoc """
  Repository-level pod for monitoring repository state and tracking work.

  This pod is instantiated once per repository runtime and contains
  eager agents that continuously monitor the repository and track active work.

  ## Agents

  * `RepoMonitor` - Tracks git status, file changes, and repository state
  * `WorkRegistry` - Tracks all active WorkItems and their associated CodingPods

  ## Lifecycle

  This pod is started when the kernel is created and remains active for the
  lifetime of the kernel, providing persistent monitoring and registry capabilities.
  """

  use Jido.Pod,
    name: "repo_pod",
    topology: %{
      repo_monitor: %{
        agent: JidoCode.Agents.RepoMonitor,
        manager: :jido_code_repo_monitors,
        activation: :eager
      },
      work_registry: %{
        agent: JidoCode.Agents.WorkRegistry,
        manager: :jido_code_work_registries,
        activation: :eager
      }
    }
end
