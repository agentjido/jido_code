defmodule JidoCode.Actions.StoreArtifact do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to store an artifact from a coding operation.

  Stores plans, patches, reviews, and other outputs from coding operations.
  """

  use Jido.Action,
    name: "jido_code_store_artifact",
    description: "Store an artifact (plan, patch, review, etc.) from a coding operation.",
    schema: [
      type: [type: :string, required: true],
      content: [type: :string, required: true],
      task_id: [type: :string, default: nil],
      metadata: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{type: type, content: content, task_id: task_id, metadata: metadata}, context) do
    alias Jido.Agent.StateOp

    artifact = %{
      id: generate_artifact_id(),
      type: type,
      content: content,
      task_id: task_id,
      metadata: metadata,
      created_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    current_artifacts = Map.get(context.state, :artifacts, [])

    state_op =
      StateOp.set_state(%{
        artifacts: current_artifacts ++ [artifact],
        last_updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, %{artifact: artifact, stored: true}, state_op}
  end

  defp generate_artifact_id do
    "artifact_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
