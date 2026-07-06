defmodule JidoCode.Actions.SelectTask do
  # covers: architecture.repository_runtime_integration.actions
  @moduledoc """
  Action to select the active task on the task board.

  Changes the active_task_id to the specified task.
  """

  use Jido.Action,
    name: "jido_code_select_task",
    description: "Select a task as the active task.",
    schema: [
      task_id: [type: :string, required: true]
    ]

  @impl true
  def run(%{task_id: task_id}, context) do
    alias Jido.Agent.StateOp

    current_tasks = Map.get(context.state, :tasks, [])
    task_exists? = Enum.any?(current_tasks, fn t -> t.id == task_id end)

    active_task_id =
      if task_exists? do
        task_id
      else
        Map.get(context.state, :active_task_id, "")
      end

    state_op =
      StateOp.set_state(%{
        active_task_id: active_task_id,
        last_updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, %{task_id: task_id, selected: task_exists?}, state_op}
  end
end
