defmodule Jido.Os.State do
  @moduledoc false

  use Agent

  def start_link(_opts) do
    Agent.start_link(fn -> %{instances: %{}, sessions: %{}} end, name: __MODULE__)
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
end
