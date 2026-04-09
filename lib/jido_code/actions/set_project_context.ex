defmodule JidoCode.Actions.SetProjectContext do
  # covers: architecture.agent_os_integration.actions
  # covers: architecture.agent_os_integration.signal_routing_within_pod
  # covers: architecture.agent_os_integration.eager_collaboration_state_is_seeded_before_specialist_work
  @moduledoc """
  Action to seed or refresh the eager project-context node for a CodingPod.

  Keeps workspace and work-item bindings explicit on the project context agent
  so specialist workflows have stable pod-local context.
  """

  use Jido.Action,
    name: "jido_code_set_project_context",
    description: "Set workspace and work-item bindings on the project context agent.",
    schema: [
      workspace_path: [type: :string, required: true],
      work_item_id: [type: :string, required: true],
      project_metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{workspace_path: workspace_path, work_item_id: work_item_id, project_metadata: metadata}, _context) do
    alias Jido.Agent.StateOp

    state_op =
      StateOp.set_state(%{
        workspace_path: workspace_path,
        work_item_id: work_item_id,
        project_metadata: metadata,
        index_updated_at: DateTime.utc_now()
      })

    {:ok,
     %{
       workspace_path: workspace_path,
       work_item_id: work_item_id,
       set: true
     }, state_op}
  end
end
