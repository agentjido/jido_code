defmodule JidoCode.Actions.KGQuery do
  @moduledoc """
  Action to query the Knowledge Graph using SPARQL.

  Executes SPARQL queries against the configured KG backend to retrieve
  information about code structure, relationships, and patterns.
  """

  use Jido.Action,
    name: "jido_code_kg_query",
    description: "Query the Knowledge Graph using SPARQL.",
    schema: [
      sparql: [type: :string, required: true],
      limit: [type: :integer, default: 100],
      backend: [type: :atom, default: nil]
    ]

  @impl true
  def run(%{sparql: sparql} = params, _context) do
    backend = get_backend(params[:backend])

    case backend.query(sparql, limit: params[:limit] || 100) do
      {:ok, results} ->
        {:ok, %{results: results, count: length(results)}}

      {:error, reason} ->
        {:error, :query_failed, "KG query failed: #{inspect(reason)}"}
    end
  end

  defp get_backend(nil), do: kg_backend()
  defp get_backend(backend) when is_atom(backend), do: backend

  defp kg_backend do
    Application.get_env(:jido_code, :kg_backend, JidoCode.KG.MemoryBackend)
  end
end
