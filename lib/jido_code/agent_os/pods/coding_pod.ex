defmodule JidoCode.AgentOS.Pods.CodingPod do
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
  * `Planner` - Generates implementation plans (referenced in Section 19.3)
  * `Coder` - Implements code changes (referenced in Section 19.3)
  * `Reviewer` - Reviews proposed changes (referenced in Section 19.3)

  ## Lifecycle

  This pod is created when a WorkItem begins and is shut down when the
  work is complete, providing isolated execution contexts for concurrent work.
  """

  use Jido.AgentOS.Pod,
    name: "coding_pod",
    topology: %{
      task_board: %{
        agent: JidoCode.AgentOS.Agents.TaskBoard,
        manager: :task_board,
        activation: :eager
      },
      project_context: %{
        agent: JidoCode.AgentOS.Agents.ProjectContext,
        manager: :project_context,
        activation: :eager
      }

      # Lazy AI specialists - started on demand
      # These will be added in Section 19.3
      # planner: %{agent: JidoCode.AgentOS.Agents.Planner, manager: :planning, activation: :lazy},
      # coder: %{agent: JidoCode.AgentOS.Agents.Coder, manager: :coding, activation: :lazy},
      # reviewer: %{agent: JidoCode.AgentOS.Agents.Reviewer, manager: :review, activation: :lazy}
    }
end
