defmodule JidoCode.Agents.ProjectContext do
  # covers: architecture.repository_runtime_integration.pod_hierarchy
  # covers: architecture.repository_runtime_integration.coding_agents
  # covers: architecture.repository_runtime_integration.pod_contains_multiple_agents
  # covers: architecture.repository_runtime_integration.signal_routing_within_pod
  # covers: architecture.repository_runtime_integration.eager_collaboration_state_is_seeded_before_specialist_work
  @moduledoc """
  Eager agent that maintains project context for the coding session.

  Tracks workspace path, file index, and project-level metadata that
  is shared across all agents in the CodingPod.

  ## Capabilities

  * Workspace path management
  * File indexing and lookup
  * Project metadata tracking
  * Context-aware file operations
  """

  alias JidoCode.Actions.SetProjectContext

  use Jido.Agent,
    name: "project_context",
    priority: :high,
    schema: [
      # Workspace path
      workspace_path: [
        type: :string,
        default: nil,
        doc: "Path to the workspace root"
      ],
      # File index: path -> metadata map
      file_index: [
        type: {:map, :string, :map},
        default: %{},
        doc: "Index of files with their metadata"
      ],
      # WorkItem ID
      work_item_id: [
        type: :string,
        default: nil,
        doc: "The ID of the WorkItem this context belongs to"
      ],
      # Project metadata
      project_metadata: [
        type: :map,
        default: %{},
        doc: "Additional project-level metadata"
      ],
      # Index last updated
      index_updated_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp when the file index was last updated"
      ]
    ]

  def signal_routes(_ctx) do
    [
      {"project.context.set", SetProjectContext}
    ]
  end
end
