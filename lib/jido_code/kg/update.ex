defmodule JidoCode.Actions.KGUpdate do
  @moduledoc """
  Action to update the Knowledge Graph.

  Supports operations to add or remove facts from the KG, or trigger
  a re-index of the codebase.
  """

  use Jido.Action,
    name: "jido_code_kg_update",
    description: "Update the Knowledge Graph with new information.",
    schema: [
      operation: [
        type: :atom,
        required: true,
        doc: "Operation to perform: :index, :add_facts, :remove_facts"
      ],
      data: [
        type: :any,
        required: false,
        default: [],
        doc: "Data for the operation (list of triples for add/remove)"
      ],
      backend: [
        type: :atom,
        required: false,
        default: nil,
        doc: "KG backend module to use"
      ]
    ]

  @impl true
  def run(%{operation: operation} = params, _context) do
    backend = get_backend(params[:backend])
    data = params[:data] || []

    case backend.update(operation, data, []) do
      :ok ->
        {:ok, %{operation: operation, status: :ok}}

      {:ok, result, extra} when is_map(result) and is_list(extra) ->
        # Handle {:ok, map, keyword} return format
        {:ok, Map.merge(result, %{operation: operation}) |> Map.new()}

      {:ok, result} when is_map(result) ->
        # Handle {:ok, map} return format
        {:ok, Map.put(result, :operation, operation)}

      {:ok, result} when is_list(result) ->
        # Handle {:ok, keyword} return format
        {:ok, result |> Map.new() |> Map.put(:operation, operation)}

      {:error, reason} ->
        {:error, :update_failed, "KG update failed: #{inspect(reason)}"}
    end
  end

  defp get_backend(nil), do: kg_backend()
  defp get_backend(backend) when is_atom(backend), do: backend

  defp kg_backend do
    Application.get_env(:jido_code, :kg_backend, JidoCode.KG.MemoryBackend)
  end
end
