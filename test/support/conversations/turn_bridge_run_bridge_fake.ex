defmodule JidoCode.TestSupport.Conversations.TurnBridgeRunBridgeFake do
  @moduledoc false

  @state __MODULE__.State

  def clear do
    ensure_started()
    Agent.update(@state, fn _state -> %{calls: [], result: {:ok, %{}}} end)
    :ok
  end

  def put_result(result) do
    ensure_started()
    Agent.update(@state, &Map.put(&1, :result, result))
    :ok
  end

  def calls do
    ensure_started()
    Agent.get(@state, fn state -> Enum.reverse(state.calls) end)
  end

  def materialize_turn(attrs) when is_map(attrs) do
    ensure_started()

    Agent.get_and_update(@state, fn state ->
      updated_state = %{state | calls: [attrs | state.calls]}
      {state.result, updated_state}
    end)
  end

  defp ensure_started do
    case Process.whereis(@state) do
      nil ->
        {:ok, _pid} = Agent.start_link(fn -> %{calls: [], result: {:ok, %{}}} end, name: @state)
        :ok

      _pid ->
        :ok
    end
  end
end
