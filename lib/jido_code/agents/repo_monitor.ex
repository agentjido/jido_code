defmodule JidoCode.Agents.RepoMonitor do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.pod_hierarchy
  @moduledoc """
  Eager agent that monitors repository state.

  Tracks git status, file changes, and repository health. Provides
  up-to-date information about the repository's current state.

  ## Capabilities

  * Git status tracking (branch, uncommitted changes, sync state)
  * File change detection
  * Repository health checks
  """

  use Jido.Agent,
    name: "repo_monitor",
    priority: :high,
    schema: [
      # Current git branch
      branch: [
        type: :string,
        default: nil,
        doc: "The current git branch name"
      ],
      # Uncommitted files
      uncommitted_files: [
        type: {:list, :string},
        default: [],
        doc: "List of files with uncommitted changes"
      ],
      # Last status check timestamp
      last_checked_at: [
        type: :datetime,
        default: nil,
        doc: "Timestamp of the last status check"
      ],
      # ManagedRepo ID
      managed_repo_id: [
        type: :string,
        default: nil,
        doc: "The ID of the managed repository being monitored"
      ]
    ]
end
