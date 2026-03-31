defmodule JidoCode.TestSupport.Conversations.TurnBridgeRuntimeFake do
  @moduledoc false

  @state __MODULE__.State

  def clear do
    ensure_started()
    Agent.update(@state, fn _state -> %{calls: [], owner: nil} end)
  end

  def set_owner(pid) when is_pid(pid) do
    ensure_started()
    Agent.update(@state, &Map.put(&1, :owner, pid))
    :ok
  end

  def calls do
    ensure_started()

    Agent.get(@state, fn state ->
      Enum.reverse(state.calls)
    end)
  end

  def send_event(project_id, conversation_id, event) when is_map(event) do
    ensure_started()
    normalized_event = normalize_event(event)

    owner =
      Agent.get_and_update(@state, fn state ->
        updated_calls = [{project_id, conversation_id, normalized_event} | state.calls]
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

  defp ensure_started do
    case Process.whereis(@state) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> %{calls: [], owner: nil} end, name: @state)
        :ok

      _pid ->
        :ok
    end
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
end
