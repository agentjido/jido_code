defmodule JidoCode.TestSupport.Conversations.TurnBridgeRuntimeFake do
  @moduledoc false

  @state __MODULE__.State

  def clear do
    ensure_started()
    Agent.update(@state, fn _state -> %{calls: %{}, owner: nil} end)
  end

  def set_owner(pid) when is_pid(pid) do
    ensure_started()
    Agent.update(@state, &Map.put(&1, :owner, pid))
    :ok
  end

  def calls do
    ensure_started()

    Agent.get(@state, fn state ->
      state.calls
      |> Map.values()
      |> List.flatten()
      |> Enum.reverse()
    end)
  end

  def calls(operation) when is_atom(operation) do
    ensure_started()

    Agent.get(@state, fn state ->
      state.calls
      |> Map.get(operation, [])
      |> Enum.reverse()
    end)
  end

  def start_project(root_path, opts) when is_binary(root_path) and is_list(opts) do
    record_call(:start_project, {root_path, opts})

    project_id =
      opts
      |> Keyword.get(:project_id, "unknown-project")
      |> normalize_project_id()

    {:ok, project_id}
  end

  def start_conversation(project_id, opts) when is_list(opts) do
    record_call(:start_conversation, {project_id, opts})
    {:ok, Keyword.fetch!(opts, :conversation_id)}
  end

  def send_event(project_id, conversation_id, event) when is_map(event) do
    ensure_started()
    normalized_event = normalize_event(event)

    owner =
      Agent.get_and_update(@state, fn state ->
        updated_calls =
          Map.update(
            state.calls,
            :send_event,
            [{project_id, conversation_id, normalized_event}],
            &[{project_id, conversation_id, normalized_event} | &1]
          )

        {state.owner, %{state | calls: updated_calls}}
      end)

    if is_pid(owner) do
      send(owner, {:conversation_event, conversation_id, normalized_event})

      if Map.get(normalized_event, "type") == "assistant.delta" do
        send(owner, {:conversation_delta, conversation_id, normalized_event})
      end
    end

    :ok
  end

  def subscribe_conversation(project_id, conversation_id, pid) when is_pid(pid) do
    record_call(:subscribe_conversation, {project_id, conversation_id, pid})
    :ok
  end

  def unsubscribe_conversation(project_id, conversation_id, pid) when is_pid(pid) do
    record_call(:unsubscribe_conversation, {project_id, conversation_id, pid})
    :ok
  end

  def stop_conversation(project_id, conversation_id) do
    record_call(:stop_conversation, {project_id, conversation_id})
    :ok
  end

  defp ensure_started do
    case Process.whereis(@state) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> %{calls: %{}, owner: nil} end, name: @state)
        :ok

      _pid ->
        :ok
    end
  end

  defp record_call(operation, payload) do
    ensure_started()

    Agent.update(@state, fn state ->
      updated_calls = Map.update(state.calls, operation, [payload], &[payload | &1])
      %{state | calls: updated_calls}
    end)
  end

  defp normalize_event(event) when is_map(event) do
    Enum.reduce(event, %{}, fn {key, value}, acc ->
      normalized_key =
        case key do
          atom when is_atom(atom) -> Atom.to_string(atom)
          binary when is_binary(binary) -> binary
          other -> to_string(other)
        end

      Map.put(acc, normalized_key, normalize_nested_value(value))
    end)
  end

  defp normalize_nested_value(value) when is_map(value), do: normalize_event(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_project_id(value) when is_binary(value), do: value
  defp normalize_project_id(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_project_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_project_id(_value), do: "unknown-project"
end
