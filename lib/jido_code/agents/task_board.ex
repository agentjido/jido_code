defmodule JidoCode.Agents.TaskBoard do
  # covers: architecture.agent_os_integration.pod_hierarchy
  # covers: architecture.agent_os_integration.coding_agents
  @moduledoc """
  Eager agent that coordinates task status and workflow transitions.

  Tracks the current state of the WorkItem being handled by this CodingPod,
  managing state transitions and providing visibility into progress.

  ## Task States

  * `:pending` - Task is queued but not started
  * `:planning` - Generating implementation plan
  * `:coding` - Implementing code changes
  * `:reviewing` - Reviewing proposed changes
  * `:completed` - Task completed successfully
  * `:failed` - Task failed

  ## Capabilities

  * Track task state
  * Manage state transitions
  * Record task history and events
  """

  use Jido.Agent,
    name: "task_board",
    priority: :high,
    schema: [
      # Current task state
      status: [
        type: :atom,
        default: :pending,
        doc: "Current task status"
      ],
      # WorkItem ID
      work_item_id: [
        type: :string,
        default: nil,
        doc: "The ID of the WorkItem being managed"
      ],
      # Task history
      history: [
        type: {:list, :map},
        default: [],
        doc: "List of historical state transitions"
      ],
      # Error information if failed
      error: [
        type: :string,
        default: nil,
        doc: "Error message if status is :failed"
      ],
      # Current plan (if any)
      plan: [
        type: :map,
        default: nil,
        doc: "Current implementation plan"
      ]
    ]
end
