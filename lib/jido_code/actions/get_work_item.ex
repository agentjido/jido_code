defmodule JidoCode.Actions.GetWorkItem do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to fetch WorkItem details from the JidoCode product API.

  Retrieves the current state, instructions, and context for a WorkItem.
  """

  use Jido.Action,
    name: "jido_code_get_work_item",
    description: "Fetch WorkItem details from the JidoCode API.",
    schema: [
      work_item_id: [type: :string, required: true]
    ]

  @impl true
  def run(%{work_item_id: work_item_id}, _context) do
    # This is a placeholder implementation. In production, this would:
    # 1. Call the JidoCode product API
    # 2. Fetch the WorkItem by ID
    # 3. Return the WorkItem details

    case JidoCode.WorkItems.get_work_item(work_item_id) do
      {:ok, work_item} ->
        {:ok,
         %{
           work_item_id: work_item.id,
           title: work_item.title,
           description: work_item.description,
           status: work_item.status,
           workspace_path: work_item.workspace_path,
           managed_repo_id: work_item.managed_repo_id,
           metadata: work_item.metadata
         }}

      {:error, :not_found} ->
        {:error, :work_item_not_found, "WorkItem not found: #{work_item_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
