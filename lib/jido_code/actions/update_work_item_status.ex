defmodule JidoCode.Actions.UpdateWorkItemStatus do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to update WorkItem status via the JidoCode product API.

  Updates the status of a WorkItem to reflect progress in the workflow.
  """

  alias JidoCode.Control.Actor
  alias JidoCode.Operations.WorkItem

  use Jido.Action,
    name: "jido_code_update_work_item_status",
    description: "Update WorkItem status via the JidoCode API.",
    schema: [
      work_item_id: [type: :string, required: true],
      status: [type: :string, required: true],
      message: [type: :string, default: nil]
    ]

  @impl true
  @actor Actor.managed_repo_orchestrator_actor(%{
           "id" => "system:agent-os-update-work-item",
           "email" => "agent-os-update-work-item@system.local"
         })

  def run(%{work_item_id: work_item_id, status: status, message: message}, _context) do
    valid_statuses = [:open, :in_progress, :blocked, :completed, :cancelled, :suppressed]

    status_atom =
      if is_binary(status) do
        String.to_existing_atom(status)
      else
        status
      end

    if status_atom in valid_statuses do
      with {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id),
           audit_log = append_audit_log(work_item.audit_log, status_atom, message),
           {:ok, updated_work_item} <-
             WorkItem.update(
               work_item,
               %{status: status_atom, audit_log: audit_log},
               actor: @actor
             ) do
        {:ok,
         %{
           work_item_id: updated_work_item.id,
           status: updated_work_item.status,
           updated: true
         }}
      end
    else
      {:error, :invalid_status, "Invalid status: #{status}"}
    end
  rescue
    ArgumentError ->
      {:error, :invalid_status, "Invalid status: #{status}"}
  end

  defp fetch_work_item(work_item_id) when is_binary(work_item_id) do
    case WorkItem.read(query: [filter: [id: work_item_id], limit: 1], actor: @actor) do
      {:ok, [%WorkItem{} = work_item | _rest]} -> {:ok, work_item}
      {:ok, []} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_work_item(_work_item_id), do: {:error, :work_item_not_found}

  defp append_audit_log(audit_log, status, message) when is_list(audit_log) do
    audit_log ++
      [
        %{
          "event" => "status_updated",
          "status" => Atom.to_string(status),
          "message" => message,
          "recorded_at" => DateTime.utc_now() |> DateTime.truncate(:microsecond)
        }
      ]
  end

  defp append_audit_log(_audit_log, status, message), do: append_audit_log([], status, message)
end
