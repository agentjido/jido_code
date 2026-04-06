defmodule JidoCode.Actions.AddTask do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to add a task to the task board.

  Creates a new task and adds it to the tasks list in the TaskBoard state.
  """

  use Jido.Action,
    name: "jido_code_add_task",
    description: "Add a new task to the task board.",
    schema: [
      title: [type: :string, required: true],
      description: [type: :string, required: true],
      priority: [type: :string, default: "medium"],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{title: title, description: description, priority: priority, metadata: metadata}, context) do
    alias Jido.Agent.StateOp

    task = %{
      id: generate_task_id(),
      title: title,
      description: description,
      priority: priority,
      status: :pending,
      metadata: metadata,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    current_tasks = Map.get(context.state, :tasks, [])
    active_task_id = Map.get(context.state, :active_task_id, "")

    state_op =
      StateOp.set_state(%{
        tasks: current_tasks ++ [task],
        active_task_id: if(active_task_id == "", do: task.id, else: active_task_id),
        last_updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, %{task: task, added: true}, state_op}
  end

  defp generate_task_id do
    "task_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
