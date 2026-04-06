defmodule JidoCode.Agents.WorkRegistry do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.pod_hierarchy
  @moduledoc """
  Eager agent that tracks all active WorkItems in the repository.

  Maintains a registry of WorkItems and their associated CodingPods,
  enabling coordination between multiple concurrent work sessions.

  ## Capabilities

  * Register/unregister WorkItems
  * Track which CodingPod is handling each WorkItem
  * List all active WorkItems
  * Prevent duplicate WorkItem registrations
  """

  use Jido.Agent,
    name: "work_registry",
    priority: :high,
    schema: [
      # Map of work_item_id -> coding_pod_name
      work_items: [
        type: {:map, :string, :string},
        default: %{},
        doc: "Map of WorkItem IDs to their associated CodingPod names"
      ],
      # ManagedRepo ID
      managed_repo_id: [
        type: :string,
        default: nil,
        doc: "The ID of the managed repository being monitored"
      ]
    ]
end
