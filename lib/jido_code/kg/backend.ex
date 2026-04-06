defmodule JidoCode.KG.MemoryBackend do
  @moduledoc """
  In-memory Knowledge Graph backend using ETS for development and testing.

  Stores code knowledge as triples (subject, predicate, object) and supports
  SPARQL-like queries through pattern matching.
  """

  @behaviour JidoCode.KG.Adapter

  @table_name_triples :jido_code_kg_triples
  @table_name_nodes :jido_code_kg_nodes

  def start_link do
    :ets.new(@table_name_triples, [:named_table, :public, :set])
    :ets.new(@table_name_nodes, [:named_table, :public, :set])
    {:ok, self()}
  end

  def stop_link do
    if :ets.whereis(@table_name_triples) != :undefined do
      :ets.delete(@table_name_triples)
    end

    if :ets.whereis(@table_name_nodes) != :undefined do
      :ets.delete(@table_name_nodes)
    end

    :ok
  end

  @impl true
  def query(sparql, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)

    case parse_sparql(sparql) do
      {:select, _patterns, _conditions} ->
        results = query_triples(limit)
        {:ok, results}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def update(operation, data, opts \\ []) do
    case operation do
      :index ->
        # Would trigger a re-index of the codebase
        # For now, this is a no-op
        {:ok, %{}, indexed: 0}

      :add_facts ->
        Enum.each(data, &add_triple/1)
        :ok

      :remove_facts ->
        remove_triples_by_pattern(data)
        :ok
    end
  end

  @impl true
  def explore(start_node, opts \\ []) do
    direction = Keyword.get(opts, :direction, :both)
    depth = Keyword.get(opts, :depth, 3)

    explore_graph(start_node, direction, depth)
  end

  # Private functions

  defp parse_sparql(sparql) do
    cond do
      String.contains?(sparql, "SELECT") ->
        {:select, [], nil}

      String.contains?(sparql, "WHERE") ->
        [_select_part, _where_part] = String.split(sparql, "WHERE", parts: 2)
        {:select, [], nil}

      true ->
        {:error, :unsupported_query}
    end
  end

  defp query_triples(limit) do
    # Match triples against patterns
    # For now, return placeholder results
    results = [
      %{file: "lib/jido_code/web/router.ex", type: "module", name: "JidoCodeWeb.Router"},
      %{file: "lib/jido_code/web/router.ex", type: "function", name: "route/2"}
    ]

    Enum.take(results, limit)
  end

  defp add_triple({subject, predicate, object}) do
    :ets.insert(@table_name_triples, {subject, predicate, object})
  end

  defp remove_triples_by_pattern(_patterns) do
    # TODO: Implement pattern-based removal
    :ok
  end

  defp explore_graph(start_node, direction, depth) when depth > 0 do
    # Start from start_node and traverse relationships
    # For now, return placeholder results
    results = [
      %{from: start_node, relationship: "imports", to: "lib/jido_code/repo.ex"},
      %{from: start_node, relationship: "calls", to: "lib/jido_code/agent_workspace.ex"}
    ]

    expanded =
      if direction == :both do
        results ++
          [
            %{from: "lib/jido_code/repo.ex", relationship: "imported_by", to: start_node},
            %{from: "lib/jido_code/agent_workspace.ex", relationship: "called_by", to: start_node}
          ]
      else
        results
      end

    {:ok, expanded}
  end

  defp explore_graph(_start_node, _direction, _depth) do
    {:ok, []}
  end
end
