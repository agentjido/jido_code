defmodule JidoCode.Agents.BudgetMonitor do
  # covers: architecture.context_management_pod.budget_monitor_observes_budget_diagnostics
  @moduledoc """
  Eager context-management agent that owns budget observation state.

  Product code updates persisted pod metadata through `AgentWorkspace`; this
  runtime agent exists so the AgentOS topology has an addressable monitor node
  and can grow signal handling without changing product entrypoints.
  """

  use Jido.Agent,
    name: "budget_monitor",
    priority: :high,
    schema: [
      managed_repo_id: [type: :string, default: nil],
      work_item_id: [type: :string, default: nil],
      observations: [type: {:list, :map}, default: []],
      recommendations: [type: {:list, :map}, default: []],
      latest_decision: [type: :map, default: nil],
      policy: [type: :map, default: %{}]
    ]
end
