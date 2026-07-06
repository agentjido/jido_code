defmodule JidoCode.Agents.TaskBoard do
  # covers: architecture.repository_runtime_integration.pod_hierarchy
  # covers: architecture.repository_runtime_integration.coding_agents
  # covers: architecture.repository_runtime_integration.pod_contains_multiple_agents
  # covers: architecture.repository_runtime_integration.signal_routing_within_pod
  # covers: architecture.repository_runtime_integration.eager_collaboration_state_is_seeded_before_specialist_work
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

  alias JidoCode.Actions.{AddTask, AppendEvent, SelectTask, StoreArtifact}

  use Jido.Agent,
    name: "task_board",
    priority: :high,
    schema: [
      tasks: [
        type: {:list, :map},
        default: [],
        doc: "Tracked task records for this work item pod"
      ],
      active_task_id: [
        type: :string,
        default: nil,
        doc: "Currently selected task identifier"
      ],
      activity_log: [
        type: {:list, :map},
        default: [],
        doc: "Activity log for stage transitions and task events"
      ],
      artifacts: [
        type: {:list, :map},
        default: [],
        doc: "Stored workflow artifacts emitted by specialists"
      ],
      last_updated_at: [
        type: :string,
        default: nil,
        doc: "Timestamp when task board state last changed"
      ],
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

  def signal_routes(_ctx) do
    [
      {"task.add", AddTask},
      {"task.select", SelectTask},
      {"task.store", StoreArtifact},
      {"task.event", AppendEvent}
    ]
  end
end
