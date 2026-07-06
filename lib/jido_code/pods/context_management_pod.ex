defmodule JidoCode.Pods.ContextManagementPod do
  # covers: architecture.context_management_pod.coding_pod_owns_context_management
  # covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics
  # covers: architecture.context_management_pod.context_compactor_is_bounded_specialist
  # covers: architecture.context_management_pod.compaction_store_is_product_owned
  @moduledoc """
  Work-item-scoped context-management pod owned alongside each CodingPod.

  The pod contains an eager monitor and deterministic store, plus a lazy
  compactor. Repository-scoped pods may observe aggregate health later, but
  specialist history compaction is owned here so context cannot bleed between
  work items.
  """

  use Jido.Pod,
    name: "context_management_pod",
    topology: %{
      budget_monitor: %{
        agent: JidoCode.Agents.BudgetMonitor,
        manager: :jido_code_budget_monitors,
        activation: :eager
      },
      compaction_store: %{
        agent: JidoCode.Agents.CompactionStore,
        manager: :jido_code_compaction_stores,
        activation: :eager
      },
      context_compactor: %{
        agent: JidoCode.Agents.ContextCompactor,
        manager: :jido_code_context_compactors,
        activation: :lazy
      }
    }
end
