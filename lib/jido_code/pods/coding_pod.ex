defmodule JidoCode.Pods.CodingPod do
  # covers: architecture.agent_os_integration.coding_pod_per_work_item
  # covers: architecture.agent_os_integration.pod_contains_multiple_agents
  # covers: architecture.agent_os_integration.eager_and_lazy_agent_activation
  # covers: architecture.agent_os_integration.pod_hierarchy
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Multi-agent pod for handling coding work items.

  This pod is instantiated per WorkItem and contains eager agents for
  task coordination and project context, with lazy AI specialists that
  are activated on demand.

  ## Agents

  ### Eager (started with the pod)
  * `TaskBoard` - Coordinates task status and workflow transitions
  * `ProjectContext` - Maintains workspace path, file index, and project-level context

  ### Lazy (started on demand)
  * `Planner` - Generates implementation plans
  * `Coder` - Implements code changes
  * `Reviewer` - Reviews proposed changes
  * `Refactorer` - Refactors code for improved structure
  * `Explainer` - Explains code and changes

  ## Lifecycle

  This pod is created when a WorkItem begins and is shut down when the
  work is complete, providing isolated execution contexts for concurrent work.
  """

  use Jido.AgentOS.Pod,
    name: "coding_pod",
    signal_routes: [
      {"jido.agent.child.started", Jido.Actions.Control.Noop},
      {"jido.agent.child.exit", Jido.Actions.Control.Noop},
      {"jido.agent.orphaned", Jido.Actions.Control.Noop}
    ],
    topology: %{
      task_board: %{
        agent: JidoCode.Agents.TaskBoard,
        manager: :task_board,
        activation: :eager
      },
      project_context: %{
        agent: JidoCode.Agents.ProjectContext,
        manager: :project_context,
        activation: :eager
      },
      # Lazy AI specialists - started on demand
      planner: %{
        agent: JidoCode.Agents.Planner,
        manager: :planning,
        activation: :lazy
      },
      coder: %{
        agent: JidoCode.Agents.Coder,
        manager: :coding,
        activation: :lazy
      },
      reviewer: %{
        agent: JidoCode.Agents.Reviewer,
        manager: :review,
        activation: :lazy
      },
      refactorer: %{
        agent: JidoCode.Agents.Refactorer,
        manager: :refactoring,
        activation: :lazy
      },
      explainer: %{
        agent: JidoCode.Agents.Explainer,
        manager: :explanation,
        activation: :lazy
      }
    }
end
