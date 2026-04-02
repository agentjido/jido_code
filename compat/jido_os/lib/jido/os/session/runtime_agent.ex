defmodule Jido.Os.Session.RuntimeAgent do
  # covers: jido_os.runtime.compatibility.public_runtime_surface
  # covers: jido_os.runtime.compatibility.session_and_envelope_behaviour
  @moduledoc false

  alias Jido.Os.State

  def load_session(instance_id, session_id, _context)
      when is_binary(instance_id) and is_binary(session_id) do
    case State.get_session(instance_id, session_id) do
      nil -> {:error, :session_not_found}
      session -> {:ok, session}
    end
  end

  def create_session(instance_id, session_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_map(context) do
    session =
      %{
        instance_id: instance_id,
        session_id: session_id,
        actor_id: Map.get(context, :actor_id),
        request_id: Map.get(context, :request_id),
        correlation_id: Map.get(context, :correlation_id),
        project_id: Map.get(context, :project_id),
        workspace_id: Map.get(context, :workspace_id)
      }
      |> compact_nil_values()

    State.put_session(instance_id, session_id, session)
    {:ok, session}
  end

  def update_session_ai_preferences(instance_id, session_id, selection, _context)
      when is_binary(instance_id) and is_binary(session_id) and is_map(selection) do
    State.update_session(instance_id, session_id, fn session ->
      Map.merge(session, selection)
    end)
  end

  def get_session_ai_preferences(instance_id, session_id, context)
      when is_binary(instance_id) and is_binary(session_id) do
    with {:ok, session} <- load_session(instance_id, session_id, context) do
      {:ok,
       session
       |> Map.take([:preferred_model_profile, :preferred_provider, :preferred_model])
       |> compact_nil_values()}
    end
  end

  def store_turn(instance_id, session_id, turn, events, review, context)
      when is_binary(instance_id) and is_binary(session_id) and is_map(turn) and is_list(events) and
             is_map(review) do
    with {:ok, _session} <- load_session(instance_id, session_id, context),
         turn_id when is_binary(turn_id) <- Map.get(turn, :turn_id) do
      State.put_turn(instance_id, session_id, turn_id, turn)
      State.put_turn_events(instance_id, session_id, turn_id, events)
      State.put_turn_review(instance_id, session_id, turn_id, review)
      {:ok, turn}
    else
      nil -> {:error, :missing_turn_id}
      {:error, _reason} = error -> error
    end
  end

  def get_turn(instance_id, session_id, turn_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) do
    with {:ok, _session} <- load_session(instance_id, session_id, context) do
      case State.get_turn(instance_id, session_id, turn_id) do
        nil -> {:error, :turn_not_found}
        turn -> {:ok, turn}
      end
    end
  end

  def list_turns(instance_id, session_id, context)
      when is_binary(instance_id) and is_binary(session_id) do
    with {:ok, _session} <- load_session(instance_id, session_id, context) do
      {:ok, State.list_turns(instance_id, session_id)}
    end
  end

  def list_turn_events(instance_id, session_id, turn_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) do
    with {:ok, _turn} <- get_turn(instance_id, session_id, turn_id, context) do
      {:ok, State.list_turn_events(instance_id, session_id, turn_id)}
    end
  end

  def list_turn_artifacts(instance_id, session_id, turn_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) do
    with {:ok, turn} <- get_turn(instance_id, session_id, turn_id, context) do
      artifacts =
        turn
        |> Map.get(:outputs, %{})
        |> Map.get(:artifacts, [])

      {:ok, artifacts}
    end
  end

  def get_turn_review(instance_id, session_id, turn_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) do
    with {:ok, _turn} <- get_turn(instance_id, session_id, turn_id, context) do
      case State.get_turn_review(instance_id, session_id, turn_id) do
        nil -> {:error, :turn_review_not_found}
        review -> {:ok, review}
      end
    end
  end

  def subscribe_turn_events(instance_id, session_id, turn_id, subscription_id, subscriber, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) and
             is_binary(subscription_id) and is_pid(subscriber) do
    with {:ok, _turn} <- get_turn(instance_id, session_id, turn_id, context) do
      subscription = %{
        instance_id: instance_id,
        session_id: session_id,
        turn_id: turn_id,
        subscription_id: subscription_id,
        subscriber: subscriber
      }

      State.put_turn_subscription(instance_id, session_id, turn_id, subscription_id, subscription)
      {:ok, subscription}
    end
  end

  def unsubscribe_turn_events(instance_id, session_id, turn_id, subscription_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) and
             is_binary(subscription_id) do
    with {:ok, _turn} <- get_turn(instance_id, session_id, turn_id, context) do
      {:ok, State.delete_turn_subscription(instance_id, session_id, turn_id, subscription_id)}
    end
  end

  def cancel_turn(instance_id, session_id, turn_id, context)
      when is_binary(instance_id) and is_binary(session_id) and is_binary(turn_id) do
    with {:ok, _session} <- load_session(instance_id, session_id, context) do
      State.update_turn(instance_id, session_id, turn_id, fn turn ->
        case Map.get(turn, :state) do
          state when state in ["completed", "failed", "interrupted", "cancelled"] ->
            turn

          _other ->
            now = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

            turn
            |> Map.put(:state, "cancelled")
            |> Map.put(:phase, "cancelled")
            |> Map.put(:terminal_at, now)
        end
      end)
    end
  end

  defp compact_nil_values(map) do
    Enum.reduce(map, %{}, fn
      {_key, nil}, acc -> acc
      {key, value}, acc -> Map.put(acc, key, value)
    end)
  end
end
