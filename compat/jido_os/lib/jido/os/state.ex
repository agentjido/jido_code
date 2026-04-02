defmodule Jido.Os.State do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(
      fn ->
        %{
          instances: %{},
          sessions: %{},
          turns: %{},
          session_turns: %{},
          turn_events: %{},
          turn_reviews: %{},
          turn_subscriptions: %{},
          integration_install_sessions: %{},
          integration_project_bindings: %{}
        }
      end,
      name: __MODULE__
    )
  end

  def lookup_instance(instance_id) do
    Agent.get(__MODULE__, fn state ->
      case Map.get(state.instances, instance_id) do
        %{pid: pid} when is_pid(pid) ->
          if Process.alive?(pid), do: {:ok, pid}, else: :error

        _other ->
          :error
      end
    end)
  end

  def put_instance(instance_id, pid, context) when is_pid(pid) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:instances, instance_id], %{pid: pid, context: context})
    end)
  end

  def get_session(instance_id, session_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.sessions, {instance_id, session_id})
    end)
  end

  def put_session(instance_id, session_id, session) when is_map(session) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:sessions, {instance_id, session_id}], session)
    end)
  end

  def update_session(instance_id, session_id, updater) when is_function(updater, 1) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {instance_id, session_id}

      case Map.get(state.sessions, key) do
        nil ->
          {{:error, :session_not_found}, state}

        session ->
          updated = updater.(session)
          {{:ok, updated}, put_in(state, [:sessions, key], updated)}
      end
    end)
  end

  def get_turn(instance_id, session_id, turn_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.turns, {instance_id, session_id, turn_id})
    end)
  end

  def put_turn(instance_id, session_id, turn_id, turn) when is_map(turn) do
    Agent.update(__MODULE__, fn state ->
      key = {instance_id, session_id, turn_id}
      session_key = {instance_id, session_id}
      turn_ids = Map.get(state.session_turns, session_key, [])
      updated_turn_ids = if turn_id in turn_ids, do: turn_ids, else: turn_ids ++ [turn_id]

      state
      |> put_in([:turns, key], turn)
      |> put_in([:session_turns, session_key], updated_turn_ids)
    end)
  end

  def update_turn(instance_id, session_id, turn_id, updater) when is_function(updater, 1) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {instance_id, session_id, turn_id}

      case Map.get(state.turns, key) do
        nil ->
          {{:error, :turn_not_found}, state}

        turn ->
          updated = updater.(turn)
          {{:ok, updated}, put_in(state, [:turns, key], updated)}
      end
    end)
  end

  def list_turns(instance_id, session_id) do
    Agent.get(__MODULE__, fn state ->
      session_key = {instance_id, session_id}

      state.session_turns
      |> Map.get(session_key, [])
      |> Enum.map(fn turn_id ->
        Map.get(state.turns, {instance_id, session_id, turn_id})
      end)
      |> Enum.reject(&is_nil/1)
    end)
  end

  def next_turn_index(instance_id, session_id) do
    Agent.get(__MODULE__, fn state ->
      state.session_turns
      |> Map.get({instance_id, session_id}, [])
      |> length()
      |> Kernel.+(1)
    end)
  end

  def put_turn_events(instance_id, session_id, turn_id, events) when is_list(events) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:turn_events, {instance_id, session_id, turn_id}], events)
    end)
  end

  def append_turn_event(instance_id, session_id, turn_id, event) when is_map(event) do
    Agent.update(__MODULE__, fn state ->
      key = {instance_id, session_id, turn_id}
      events = Map.get(state.turn_events, key, [])
      put_in(state, [:turn_events, key], events ++ [event])
    end)
  end

  def list_turn_events(instance_id, session_id, turn_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.turn_events, {instance_id, session_id, turn_id}, [])
    end)
  end

  def put_turn_review(instance_id, session_id, turn_id, review) when is_map(review) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:turn_reviews, {instance_id, session_id, turn_id}], review)
    end)
  end

  def get_turn_review(instance_id, session_id, turn_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.turn_reviews, {instance_id, session_id, turn_id})
    end)
  end

  def put_turn_subscription(instance_id, session_id, turn_id, subscription_id, subscription)
      when is_binary(subscription_id) and is_map(subscription) do
    Agent.update(__MODULE__, fn state ->
      put_in(
        state,
        [:turn_subscriptions, {instance_id, session_id, turn_id, subscription_id}],
        subscription
      )
    end)
  end

  def get_turn_subscription(instance_id, session_id, turn_id, subscription_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.turn_subscriptions, {instance_id, session_id, turn_id, subscription_id})
    end)
  end

  def delete_turn_subscription(instance_id, session_id, turn_id, subscription_id) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {instance_id, session_id, turn_id, subscription_id}
      {Map.get(state.turn_subscriptions, key), update_in(state.turn_subscriptions, &Map.delete(&1, key))}
    end)
  end

  def put_integration_install_session(instance_id, install_id, session) when is_map(session) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:integration_install_sessions, {instance_id, install_id}], session)
    end)
  end

  def get_integration_install_session(instance_id, install_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.integration_install_sessions, {instance_id, install_id})
    end)
  end

  def put_integration_project_binding(instance_id, project_id, binding_id, binding) when is_map(binding) do
    Agent.update(__MODULE__, fn state ->
      put_in(state, [:integration_project_bindings, {instance_id, project_id, binding_id}], binding)
    end)
  end

  def get_integration_project_binding(instance_id, project_id, binding_id) do
    Agent.get(__MODULE__, fn state ->
      Map.get(state.integration_project_bindings, {instance_id, project_id, binding_id})
    end)
  end

  def update_integration_project_binding(instance_id, project_id, binding_id, updater)
      when is_function(updater, 1) do
    Agent.get_and_update(__MODULE__, fn state ->
      key = {instance_id, project_id, binding_id}

      case Map.get(state.integration_project_bindings, key) do
        nil ->
          {{:error, :integration_project_binding_not_found}, state}

        binding ->
          updated = updater.(binding)
          {{:ok, updated}, put_in(state, [:integration_project_bindings, key], updated)}
      end
    end)
  end

  def list_integration_project_bindings(instance_id, project_id) do
    Agent.get(__MODULE__, fn state ->
      state.integration_project_bindings
      |> Enum.filter(fn
        {{^instance_id, ^project_id, _binding_id}, _binding} -> true
        _other -> false
      end)
      |> Enum.map(fn {_key, binding} -> binding end)
      |> Enum.sort_by(fn binding ->
        {
          Map.get(binding, :provider) || Map.get(binding, "provider"),
          Map.get(binding, :binding_alias) || Map.get(binding, "binding_alias"),
          Map.get(binding, :binding_id) || Map.get(binding, "binding_id")
        }
      end)
    end)
  end
end
