defmodule JidoCode.TestSupport.Conversations.TurnBridgeCodingAssistanceFake do
  @moduledoc false

  @state __MODULE__.State

  def clear do
    ensure_started()
    Agent.update(@state, fn _state -> %{turn: nil, events: [], review: %{}, artifacts: []} end)
    :ok
  end

  def configure(turn, events, review \\ %{}, artifacts \\ [])
      when is_map(turn) and is_list(events) and is_map(review) and is_list(artifacts) do
    ensure_started()

    Agent.update(@state, fn _state ->
      %{turn: turn, events: events, review: review, artifacts: artifacts}
    end)

    :ok
  end

  def get_turn(_actor_id, _payload) do
    ensure_started()

    case Agent.get(@state, & &1.turn) do
      nil -> {:error, :turn_not_found}
      turn -> {:ok, turn}
    end
  end

  def list_turn_events(_actor_id, payload) do
    ensure_started()
    after_event_id = Map.get(payload, :after_event_id) || Map.get(payload, "after_event_id")

    events =
      Agent.get(@state, fn state ->
        filter_events_after(state.events, after_event_id)
      end)

    {:ok, events}
  end

  def review_turn(_actor_id, _payload) do
    ensure_started()
    {:ok, Agent.get(@state, & &1.review)}
  end

  def list_turn_artifacts(_actor_id, _payload) do
    ensure_started()
    {:ok, Agent.get(@state, & &1.artifacts)}
  end

  defp filter_events_after(events, nil), do: events

  defp filter_events_after(events, after_event_id) do
    case Enum.split_while(events, fn event ->
           event_id = Map.get(event, :event_id) || Map.get(event, "event_id")
           event_id != after_event_id
         end) do
      {_leading, []} -> []
      {_leading, [_matched | remaining]} -> remaining
    end
  end

  defp ensure_started do
    case Process.whereis(@state) do
      nil ->
        {:ok, _pid} =
          Agent.start_link(fn -> %{turn: nil, events: [], review: %{}, artifacts: []} end, name: @state)

        :ok

      _pid ->
        :ok
    end
  end
end
