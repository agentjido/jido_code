defmodule JidoCode.AgentOS.Actions.UpdateWorkItemStatus do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to update WorkItem status via the JidoCode product API.

  Updates the status of a WorkItem to reflect progress in the workflow.
  """

  use Jido.Action,
    name: "jido_code_update_work_item_status",
    description: "Update WorkItem status via the JidoCode API.",
    schema: [
      work_item_id: [type: :string, required: true],
      status: [type: :string, required: true],
      message: [type: :string, default: nil]
    ]

  @impl true
  def run(%{work_item_id: work_item_id, status: status, message: message}, _context) do
    # This is a placeholder implementation. In production, this would:
    # 1. Call the JidoCode product API
    # 2. Update the WorkItem status
    # 3. Return the updated WorkItem

    valid_statuses = [:pending, :planning, :coding, :reviewing, :completed, :failed]

    status_atom =
      if is_binary(status) do
        String.to_existing_atom(status)
      else
        status
      end

    if status_atom in valid_statuses do
      case JidoCode.WorkItems.update_status(work_item_id, status_atom, message) do
        {:ok, work_item} ->
          {:ok,
           %{
             work_item_id: work_item.id,
             status: work_item.status,
             updated: true
           }}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :invalid_status, "Invalid status: #{status}"}
    end
  rescue
    ArgumentError ->
      {:error, :invalid_status, "Invalid status: #{status}"}
  end
end
