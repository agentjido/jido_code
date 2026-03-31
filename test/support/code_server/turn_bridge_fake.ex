defmodule JidoCode.TestSupport.CodeServer.TurnBridgeFake do
  @moduledoc false

  @calls_key {__MODULE__, :calls}
  @results_key {__MODULE__, :results}

  def clear do
    Process.delete(@calls_key)
    Process.delete(@results_key)
    :ok
  end

  def put_result(result) do
    Process.put(@results_key, result)
    :ok
  end

  def calls do
    Process.get(@calls_key, [])
    |> Enum.reverse()
  end

  def start(attrs) when is_map(attrs) do
    Process.put(@calls_key, [attrs | Process.get(@calls_key, [])])

    case Process.get(@results_key, {:ok, self()}) do
      result when is_function(result, 1) -> result.(attrs)
      result -> result
    end
  end
end
