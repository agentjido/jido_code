defmodule JidoCode.TestSupport.CodeServer.RuntimeFake do
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

  def start_project(root_path, opts) when is_binary(root_path) and is_list(opts) do
    record_call(:start_project, {root_path, opts})

    project_id =
      opts
      |> Keyword.get(:project_id, "unknown-project")
      |> normalize_project_id()

    next_result(:start_project, {:ok, project_id}, [root_path, opts])
  end

  def start_conversation(project_id, opts) when is_list(opts) do
    record_call(:start_conversation, {project_id, opts})
    next_result(:start_conversation, {:ok, "conversation-1"}, [project_id, opts])
  end

  def send_event(project_id, conversation_id, event) when is_map(event) do
    record_call(:send_event, {project_id, conversation_id, event})
    emit_conversation_events(conversation_id, event)
    next_result(:send_event, :ok, [project_id, conversation_id, event])
  end

  def subscribe_conversation(project_id, conversation_id, pid) when is_pid(pid) do
    record_call(:subscribe_conversation, {project_id, conversation_id, pid})
    next_result(:subscribe_conversation, :ok, [project_id, conversation_id, pid])
  end

  def unsubscribe_conversation(project_id, conversation_id, pid) when is_pid(pid) do
    record_call(:unsubscribe_conversation, {project_id, conversation_id, pid})
    next_result(:unsubscribe_conversation, :ok, [project_id, conversation_id, pid])
  end

  def stop_conversation(project_id, conversation_id) do
    record_call(:stop_conversation, {project_id, conversation_id})
    next_result(:stop_conversation, :ok, [project_id, conversation_id])
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

  defp emit_conversation_events(conversation_id, event) do
    normalized_event = normalize_event(event)

    if is_binary(Map.get(normalized_event, "type")) do
      send(self(), {:conversation_event, conversation_id, normalized_event})

      if Map.get(normalized_event, "type") == "assistant.delta" do
        send(self(), {:conversation_delta, conversation_id, normalized_event})
      end
    end

    :ok
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

  defp normalize_event(_value), do: %{}

  defp normalize_nested_value(value) when is_map(value), do: normalize_event(value)
  defp normalize_nested_value(value) when is_list(value), do: Enum.map(value, &normalize_nested_value/1)
  defp normalize_nested_value(value), do: value

  defp normalize_project_id(value) when is_binary(value), do: value
  defp normalize_project_id(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_project_id(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_project_id(_value), do: "unknown-project"
end
