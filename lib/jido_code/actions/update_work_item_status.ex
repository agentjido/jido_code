defmodule JidoCode.Actions.UpdateWorkItemStatus do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to update WorkItem status via the JidoCode product API.

  Updates the status of a WorkItem to reflect progress in the workflow.
  """

  alias JidoCode.Operations.RecordStore
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
  def run(%{work_item_id: work_item_id, status: status, message: message}, _context) do
    if status_atom = normalize_status(status) do
      with {:ok, %WorkItem{} = work_item} <- fetch_work_item(work_item_id),
           audit_log = append_audit_log(work_item.audit_log, status_atom, message),
           {:ok, updated_work_item} <-
             RecordStore.update_work_item(
               work_item,
               %{status: status_atom, audit_log: audit_log}
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
  end

  defp fetch_work_item(work_item_id) when is_binary(work_item_id) do
    case RecordStore.get(:work_item, work_item_id) do
      {:ok, %WorkItem{} = work_item} -> {:ok, work_item}
      {:ok, nil} -> {:error, :work_item_not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_work_item(_work_item_id), do: {:error, :work_item_not_found}

  defp normalize_status(status)
       when is_atom(status) and status in [:open, :in_progress, :blocked, :completed, :cancelled, :suppressed],
       do: status

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.downcase()
    |> case do
      "open" -> :open
      "in_progress" -> :in_progress
      "blocked" -> :blocked
      "completed" -> :completed
      "cancelled" -> :cancelled
      "suppressed" -> :suppressed
      _other -> nil
    end
  end

  defp normalize_status(_status), do: nil

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
