defmodule JidoCode.TestSupport.Conversations.TurnBridgeCodingAssistanceFake do
  @moduledoc false

  @state __MODULE__.State

  def clear do
    ensure_started()

    Agent.update(@state, fn _state ->
      %{
        turn: nil,
        events: [],
        review: %{},
        artifacts: [],
        calls: %{},
        subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-1"}},
        unsubscribe_result: {:ok, %{delivery_status: "detached"}},
        live_envelopes: []
      }
    end)

    :ok
  end

  def configure(turn, events, review \\ %{}, artifacts \\ [], opts \\ [])
      when is_map(turn) and is_list(events) and is_map(review) and is_list(artifacts) and is_list(opts) do
    ensure_started()

    Agent.update(@state, fn state ->
      state
      |> Map.put(:turn, turn)
      |> Map.put(:events, events)
      |> Map.put(:review, review)
      |> Map.put(:artifacts, artifacts)
      |> Map.put(:subscribe_result, Keyword.get(opts, :subscribe_result, state.subscribe_result))
      |> Map.put(:unsubscribe_result, Keyword.get(opts, :unsubscribe_result, state.unsubscribe_result))
      |> Map.put(:live_envelopes, Keyword.get(opts, :live_envelopes, state.live_envelopes))
    end)

    :ok
  end

  def calls(operation) when is_atom(operation) do
    ensure_started()
    Agent.get(@state, fn state -> state.calls |> Map.get(operation, []) |> Enum.reverse() end)
  end

  def get_turn(_actor_id, payload) do
    ensure_started()
    record_call(:get_turn, payload)

    case Agent.get(@state, & &1.turn) do
      nil -> {:error, :turn_not_found}
      turn -> {:ok, turn}
    end
  end

  def list_turn_events(_actor_id, payload) do
    ensure_started()
    record_call(:list_turn_events, payload)
    after_event_id = Map.get(payload, :after_event_id) || Map.get(payload, "after_event_id")

    events =
      Agent.get(@state, fn state ->
        filter_events_after(state.events, after_event_id)
      end)

    {:ok, events}
  end

  def subscribe_turn_events(_actor_id, payload) do
    ensure_started()
    record_call(:subscribe_turn_events, payload)

    result = Agent.get(@state, & &1.subscribe_result)

    case result do
      {:ok, %{} = ack} ->
        subscriber = Map.get(payload, :subscriber) || Map.get(payload, "subscriber")
        send_live_envelopes(subscriber, ack)
        {:ok, ack}

      other ->
        other
    end
  end

  def unsubscribe_turn_events(_actor_id, payload) do
    ensure_started()
    record_call(:unsubscribe_turn_events, payload)
    Agent.get(@state, & &1.unsubscribe_result)
  end

  def review_turn(_actor_id, payload) do
    ensure_started()
    record_call(:review_turn, payload)
    {:ok, Agent.get(@state, & &1.review)}
  end

  def list_turn_artifacts(_actor_id, payload) do
    ensure_started()
    record_call(:list_turn_artifacts, payload)
    {:ok, Agent.get(@state, & &1.artifacts)}
  end

  defp send_live_envelopes(subscriber, ack) when is_pid(subscriber) do
    envelopes = Agent.get(@state, & &1.live_envelopes)

    Task.start(fn ->
      Enum.each(envelopes, fn envelope ->
        normalized_envelope =
          envelope
          |> Map.put_new(:subscription_id, ack[:subscription_id] || ack["subscription_id"])

        send(subscriber, {:jido_os_turn_delivery, normalized_envelope})
      end)
    end)
  end

  defp send_live_envelopes(_subscriber, _ack), do: :ok

  defp record_call(operation, payload) do
    Agent.update(@state, fn state ->
      updated_calls = Map.update(state.calls, operation, [payload], &[payload | &1])
      %{state | calls: updated_calls}
    end)
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
          Agent.start_link(
            fn ->
              %{
                turn: nil,
                events: [],
                review: %{},
                artifacts: [],
                calls: %{},
                subscribe_result: {:ok, %{delivery_status: "subscribed", subscription_id: "sub-1"}},
                unsubscribe_result: {:ok, %{delivery_status: "detached"}},
                live_envelopes: []
              }
            end,
            name: @state
          )

        :ok

      _pid ->
        :ok
    end
  end
end
