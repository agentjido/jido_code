defmodule JidoCode.TestSupport.CodeServer.ScopeFake do
  @moduledoc false

  @resolve_result_key {__MODULE__, :resolve_result}

  def put_resolve_result(result) do
    Process.put(@resolve_result_key, result)
    :ok
  end

  def clear do
    Process.delete(@resolve_result_key)
    :ok
  end

  def resolve(project_id) do
    case Process.get(@resolve_result_key) do
      nil ->
        normalized_project_id =
          case project_id do
            value when is_binary(value) -> value
            value when is_atom(value) -> Atom.to_string(value)
            value when is_integer(value) -> Integer.to_string(value)
            _other -> "unknown-project"
          end

        {:ok,
         %{
           project_id: normalized_project_id,
           root_path: "/tmp/#{normalized_project_id}",
           project: %{id: normalized_project_id}
         }}

      result when is_function(result, 1) ->
        result.(project_id)

      result ->
        result
    end
  end
end
