defmodule JidoCode.Actions.AppendEvent do
  # covers: architecture.repository_runtime_integration.actions
  @moduledoc """
  Action to append an event to the activity log.

  Provides an audit trail of all operations performed during coding work.
  """

  use Jido.Action,
    name: "jido_code_append_event",
    description: "Append an event to the activity log for audit trail.",
    schema: [
      event_type: [type: :string, required: true],
      message: [type: :string, required: true],
      data: [type: :map, default: %{}]
    ]

  @impl true
  def run(%{event_type: event_type, message: message, data: data}, context) do
    alias Jido.Agent.StateOp

    event = %{
      id: generate_event_id(),
      type: event_type,
      message: message,
      data: data,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    current_log = Map.get(context.state, :activity_log, [])

    state_op =
      StateOp.set_state(%{
        activity_log: [event | current_log] |> Enum.take(100),
        last_updated_at: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    {:ok, %{event: event, logged: true}, state_op}
  end

  defp generate_event_id do
    "event_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
