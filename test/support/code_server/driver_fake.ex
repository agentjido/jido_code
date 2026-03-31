defmodule JidoCode.TestSupport.CodeServer.DriverFake do
  @moduledoc false

  @calls_key {__MODULE__, :calls}
  @results_key {__MODULE__, :results}

  def clear do
    Process.delete(@calls_key)
    Process.delete(@results_key)
    :ok
  end

  def put_result(operation, result) when is_atom(operation) do
    put_results(operation, [result])
  end

  def put_results(operation, results) when is_atom(operation) and is_list(results) do
    results_map = Process.get(@results_key, %{})
    Process.put(@results_key, Map.put(results_map, operation, results))
    :ok
  end

  def calls(operation) when is_atom(operation) do
    Process.get(@calls_key, %{})
    |> Map.get(operation, [])
    |> Enum.reverse()
  end

  def prepare_conversation(attrs) when is_map(attrs) do
    record_call(:prepare_conversation, attrs)
    next_result(:prepare_conversation, {:ok, attrs}, [attrs])
  end

  def handle_turn(attrs) when is_map(attrs) do
    record_call(:handle_turn, attrs)

    next_result(
      :handle_turn,
      {:ok,
       %{
         context: attrs,
         ingress: %{},
         envelope: %{"payload" => %{"objective" => Map.get(attrs, :content)}},
         events: [
           %{"type" => "assistant.delta", "data" => %{"content" => "Ack: "}},
           %{
             "type" => "assistant.message",
             "data" => %{"content" => "Ack: #{Map.get(attrs, :content)}"}
           }
         ]
       }},
      [attrs]
    )
  end

  defp record_call(operation, payload) do
    calls_map = Process.get(@calls_key, %{})
    Process.put(@calls_key, Map.update(calls_map, operation, [payload], &[payload | &1]))
  end

  defp next_result(operation, default, args) do
    results_map = Process.get(@results_key, %{})

    case Map.get(results_map, operation, []) do
      [result | rest] ->
        Process.put(@results_key, Map.put(results_map, operation, rest))
        resolve_result(result, args)

      [] ->
        default
    end
  end

  defp resolve_result(result, args) when is_function(result, 1), do: result.(args)
  defp resolve_result(result, _args), do: result
end
