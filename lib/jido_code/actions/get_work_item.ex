defmodule JidoCode.Actions.GetWorkItem do
  # covers: architecture.repository_runtime_integration.actions
  @moduledoc """
  Action to fetch WorkItem details from the JidoCode product API.

  Retrieves the current state, instructions, and context for a WorkItem.
  """

  alias JidoCode.Control.{ManagedRepo, ManagedRepoStore}
  alias JidoCode.Operations.RecordStore
  alias JidoCode.Operations.WorkItem

  use Jido.Action,
    name: "jido_code_get_work_item",
    description: "Fetch WorkItem details from the JidoCode API.",
    schema: [
      work_item_id: [type: :string, required: true]
    ]

  @impl true
  def run(%{work_item_id: work_item_id}, _context) do
    case fetch_work_item(work_item_id) do
      {:ok, %WorkItem{} = work_item} ->
        {:ok,
         %{
           work_item_id: work_item.id,
           title: work_item.summary,
           description: work_item.recommended_action,
           status: work_item.status,
           workspace_path: workspace_path(work_item.managed_repo_id),
           managed_repo_id: work_item.managed_repo_id,
           metadata: work_item.work_metadata
         }}

      {:error, :not_found} ->
        {:error, :work_item_not_found, "WorkItem not found: #{work_item_id}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_work_item(work_item_id) when is_binary(work_item_id) do
    case RecordStore.get(:work_item, work_item_id) do
      {:ok, %WorkItem{} = work_item} -> {:ok, work_item}
      {:ok, nil} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_work_item(_work_item_id), do: {:error, :not_found}

  defp workspace_path(managed_repo_id) when is_binary(managed_repo_id) do
    case ManagedRepoStore.get_by_id(managed_repo_id) do
      {:ok, %ManagedRepo{} = managed_repo} ->
        managed_repo
        |> Map.get(:workspace_settings, %{})
        |> Map.get("workspace_path")

      _other ->
        nil
    end
  end

  defp workspace_path(_managed_repo_id), do: nil
end
