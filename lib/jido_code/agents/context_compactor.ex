defmodule JidoCode.Agents.ContextCompactor do
  # covers: architecture.context_management_pod.context_compactor_is_bounded_specialist
  @moduledoc """
  Lazy context-management agent for bounded compaction work.

  The first runtime keeps compaction deterministic at the product boundary; the
  lazy agent reserves the repository runtime topology slot for future AI-backed summarizing
  without making active specialist turns depend on it.
  """

  use Jido.Agent,
    name: "context_compactor",
    priority: :normal,
    schema: [
      managed_repo_id: [type: :string, default: nil],
      work_item_id: [type: :string, default: nil],
      latest_candidate: [type: :map, default: nil],
      latest_summary: [type: :map, default: nil],
      latest_failure: [type: :map, default: nil],
      policy: [type: :map, default: %{}]
    ]
end
