defmodule JidoCode.Actions.KGExplore do
  @moduledoc """
  Action to explore relationships in the Knowledge Graph.

  Traverses the graph from a starting node to discover connected
  entities and their relationships.
  """

  use Jido.Action,
    name: "jido_code_kg_explore",
    description: "Explore relationships in the Knowledge Graph.",
    schema: [
      start_node: [type: :string, required: true],
      direction: [
        type: :atom,
        default: :both,
        doc: "Direction to explore: :in, :out, or :both"
      ],
      depth: [
        type: :integer,
        default: 3,
        doc: "Maximum depth to explore"
      ],
      backend: [type: :atom, default: nil]
    ]

  @impl true
  def run(%{start_node: start_node} = params, _context) do
    backend = get_backend(params[:backend])

    opts = [
      direction: params[:direction] || :both,
      depth: params[:depth] || 3
    ]

    case backend.explore(start_node, opts) do
      {:ok, results} ->
        {:ok, %{
          start_node: start_node,
          results: results,
          count: length(results)
        }}

      {:error, reason} ->
        {:error, :explore_failed, "KG exploration failed: #{inspect(reason)}"}
    end
  end

  defp get_backend(nil), do: kg_backend()
  defp get_backend(backend) when is_atom(backend), do: backend

  defp kg_backend do
    Application.get_env(:jido_code, :kg_backend, JidoCode.KG.MemoryBackend)
  end
end
