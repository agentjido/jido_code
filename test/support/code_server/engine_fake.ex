defmodule JidoCode.TestSupport.CodeServer.EngineFake do
  @moduledoc false

  @responses_key {__MODULE__, :whereis_responses}
  @default_response_key {__MODULE__, :default_whereis_response}
  @calls_key {__MODULE__, :whereis_calls}

  def clear do
    Process.delete(@responses_key)
    Process.delete(@default_response_key)
    Process.delete(@calls_key)
    :ok
  end

  def put_whereis_responses(project_id, responses) when is_list(responses) do
    response_map = Process.get(@responses_key, %{})
    Process.put(@responses_key, Map.put(response_map, project_id, responses))
    :ok
  end

  def put_default_whereis_response(response) do
    Process.put(@default_response_key, response)
    :ok
  end

  def whereis_calls do
    Process.get(@calls_key, []) |> Enum.reverse()
  end

  def whereis_project(project_id) do
    record_whereis_call(project_id)

    response_map = Process.get(@responses_key, %{})

    case Map.get(response_map, project_id, []) do
      [response | rest] ->
        Process.put(@responses_key, Map.put(response_map, project_id, rest))
        response

      [] ->
        Process.get(@default_response_key, {:error, {:project_not_found, project_id}})
    end
  end

  defp record_whereis_call(project_id) do
    Process.put(@calls_key, [project_id | Process.get(@calls_key, [])])
  end
end
