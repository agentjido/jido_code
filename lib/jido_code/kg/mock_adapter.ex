defmodule JidoCode.KG.MockAdapter do
  @moduledoc """
  Mock KG adapter for testing.

  Provides pre-canned responses for testing without requiring a real KG backend.
  """

  @behaviour JidoCode.KG.Adapter

  def start_link do
    {:ok, %{}}
  end

  def stop_link do
    :ok
  end

  @impl true
  def query(sparql, opts \\ []) do
    case parse_query_type(sparql) do
      :select_all ->
        {:ok, [
          %{file: "lib/jido_code/web/router.ex", type: "module", name: "JidoCodeWeb.Router"},
          %{file: "lib/jido_code/web/router.ex", type: "function", name: "route/2"}
        ]}

      :find_file ->
        file = Keyword.get(opts, :file, "lib/jido_code/web/router.ex")
        {:ok, [
          %{file: file, type: "module", name: "JidoCodeWeb.Router"}
        ]}

      :find_function ->
        file = Keyword.get(opts, :file, "lib/jido_code/web/router.ex")
        {:ok, [
          %{file: file, type: "function", name: "route/2"}
        ]}

      :find_callers ->
        file = Keyword.get(opts, :file, "lib/jido_code/web/router.ex")
        {:ok, [
          %{file: file, type: "function", name: "route/2"}
        ]}

      :find_callees ->
        file = Keyword.get(opts, :file, "lib/jido_code/web/router.ex")
        {:ok, [
          %{file: file, type: "function", name: "route/2"}
        ]}

      :find_module ->
        module_name = Keyword.get(opts, :module, "JidoCodeWeb")
        {:ok, [
          %{file: "lib/jido_code/web/router.ex", type: "module", name: module_name}
        ]}

      :explore ->
        start_node = Keyword.get(opts, :start_node, "lib/jido_code/web/router.ex")
        {:ok, [
          %{from: start_node, relationship: "imports", to: "lib/jido_code/repo.ex"},
          %{from: start_node, relationship: "calls", to: "lib/jido_code/agent_workspace.ex"}
        ]}
    end
  end

  @impl true
  def update(operation, _data, _opts \\ []) do
    # Mock: always succeeds
    case operation do
      :index -> {:ok, %{}, indexed: 0}
      :add_facts -> :ok
      :remove_facts -> :ok
    end
  end

  @impl true
  def explore(_start_node, _opts) do
    {:ok, []}
  end

  # Private helper

  defp parse_query_type(sparql) do
    cond do
      String.contains?(sparql, "*") -> :select_all
      String.contains?(sparql, "file:") -> :find_file
      String.contains?(sparql, "function:") -> :find_function
      String.contains?(sparql, "caller:") -> :find_callers
      String.contains?(sparql, "callee:") -> :find_callees
      String.contains?(sparql, "module:") -> :find_module
      String.contains?(sparql, "explore:") -> :explore
      true -> :select_all
    end
  end
end
