defmodule JidoCode.Agents.CompactionStore do
  # covers: architecture.context_management_pod.compaction_store_is_product_owned
  @moduledoc """
  Eager context-management agent representing the deterministic summary store.

  Summaries are persisted in product-owned pod metadata. The agent gives the
  context-management pod a stable runtime node for store-related signals.
  """

  use Jido.Agent,
    name: "compaction_store",
    priority: :normal,
    schema: [
      managed_repo_id: [type: :string, default: nil],
      work_item_id: [type: :string, default: nil],
      summaries: [type: {:list, :map}, default: []],
      compacted_spans: [type: {:list, :map}, default: []],
      policy: [type: :map, default: %{}]
    ]
end
