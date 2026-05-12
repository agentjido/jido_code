defmodule JidoCode.Agents.RepoMonitor do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  # covers: architecture.agent_os_integration.pod_hierarchy
  # covers: architecture.source_code_graph_pod.graph_revision_state_is_explicit_and_explainable
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

  alias JidoCode.Agents.RepoMonitor.SourceWatcher

  @source_change_topic_prefix "repo_monitor:source_changes"

  @doc """
  Starts or reconfigures the repo-scoped local source watcher.

  The watcher emits normalized `:workspace_source_changed` events for source
  files that participate in source-code graph revision detection.
  """
  @spec ensure_source_watcher(String.t(), String.t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_source_watcher(managed_repo_id, workspace_path, opts \\ []) do
    SourceWatcher.ensure_started(managed_repo_id, workspace_path, opts)
  end

  @doc """
  Stops the repo-scoped local source watcher when a repository runtime shuts down
  or changes workspace binding.
  """
  @spec stop_source_watcher(String.t()) :: :ok
  def stop_source_watcher(managed_repo_id) do
    SourceWatcher.stop(managed_repo_id)
  end

  @doc """
  Emits a normalized source-change event through the repo-scoped watcher.

  This is primarily useful for tests and product-owned write boundaries that
  already know a source path changed successfully.
  """
  @spec notify_source_changed(String.t(), String.t(), [atom() | String.t()], atom()) :: :ok | {:error, term()}
  def notify_source_changed(managed_repo_id, changed_path, file_events \\ [:modified], event_source \\ :runtime_write) do
    SourceWatcher.notify_change(managed_repo_id, changed_path, file_events, event_source)
  end

  @doc """
  PubSub topic used for normalized workspace source-change observations.
  """
  @spec source_change_topic(String.t()) :: String.t()
  def source_change_topic(managed_repo_id) when is_binary(managed_repo_id) do
    @source_change_topic_prefix <> ":" <> managed_repo_id
  end
end
