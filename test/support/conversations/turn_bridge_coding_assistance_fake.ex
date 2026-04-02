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
        sessions: %{},
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

  def ensure_session(session_id, actor_id, attrs)
      when is_binary(session_id) and is_binary(actor_id) and is_map(attrs) do
    ensure_started()
    record_call(:ensure_session, %{session_id: session_id, actor_id: actor_id, attrs: attrs})

    session =
      %{
        session_id: session_id,
        actor_id: actor_id,
        project_id: Map.get(attrs, :project_id) || Map.get(attrs, "project_id"),
        request_id: Map.get(attrs, :request_id) || Map.get(attrs, "request_id"),
        correlation_id: Map.get(attrs, :correlation_id) || Map.get(attrs, "correlation_id"),
        workspace_id: Map.get(attrs, :workspace_id) || Map.get(attrs, "workspace_id")
      }

    Agent.update(@state, fn state ->
      %{state | sessions: Map.put(state.sessions, session_id, session)}
    end)

    {:ok, session}
  end

  def bind_project(session_id, actor_id, project_id, attrs)
      when is_binary(session_id) and is_binary(actor_id) and is_binary(project_id) and is_map(attrs) do
    ensure_started()

    record_call(:bind_project, %{
      session_id: session_id,
      actor_id: actor_id,
      project_id: project_id,
      attrs: attrs
    })

    Agent.update(@state, fn state ->
      updated_session =
        state.sessions
        |> Map.get(session_id, %{session_id: session_id, actor_id: actor_id})
        |> Map.put(:project_id, project_id)
        |> Map.put(:request_id, Map.get(attrs, :request_id) || Map.get(attrs, "request_id"))
        |> Map.put(:correlation_id, Map.get(attrs, :correlation_id) || Map.get(attrs, "correlation_id"))
        |> Map.put(:workspace_id, Map.get(attrs, :workspace_id) || Map.get(attrs, "workspace_id"))

      %{state | sessions: Map.put(state.sessions, session_id, updated_session)}
    end)

    {:ok, %{session_id: session_id, actor_id: actor_id, project_id: project_id}}
  end

  def start_turn(actor_id, payload) when is_binary(actor_id) and is_map(payload) do
    ensure_started()
    record_call(:start_turn, Map.put(payload, :actor_id, actor_id))

    case Agent.get(@state, & &1.turn) do
      nil ->
        {:error, :turn_not_found}

      turn ->
        started_turn =
          turn
          |> Map.put_new(:turn_id, Map.get(payload, :turn_id) || Map.get(payload, "turn_id") || "turn-1")
          |> Map.put(:session_id, Map.get(payload, :session_id) || Map.get(payload, "session_id"))
          |> Map.put_new(:project_id, Map.get(payload, :project_id) || Map.get(payload, "project_id"))
          |> Map.put_new(:request_id, Map.get(payload, :request_id) || Map.get(payload, "request_id"))
          |> Map.put_new(:correlation_id, Map.get(payload, :correlation_id) || Map.get(payload, "correlation_id"))
          |> Map.put_new(:workspace_id, Map.get(payload, :workspace_id) || Map.get(payload, "workspace_id"))
          |> Map.put_new(:actor_id, actor_id)

        Agent.update(@state, fn state -> %{state | turn: started_turn} end)
        {:ok, started_turn}
    end
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
                sessions: %{},
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
