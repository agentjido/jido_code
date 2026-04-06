defmodule JidoCode.KG.Indexer do
  @moduledoc """
  Index Elixir code into the Knowledge Graph.

  Traverses source files, parses them with the Parser, and stores
  the extracted structure as triples in the KG.
  """

  require Logger

  @doc """
  Index all Elixir files in a directory.
  """
  def index_directory(dir_path, opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())
    extensions = Keyword.get(opts, :extensions, [".ex"])
    recursive = Keyword.get(opts, :recursive, true)

    files = find_elixir_files(dir_path, extensions, recursive)

    results = Enum.map(files, fn file ->
      index_file(file, backend: backend)
    end)

    indexed = Enum.count(results, fn
      {:ok, _} -> true
      _ -> false
    end)

    {:ok, %{
      total: length(files),
      indexed: indexed,
      failed: length(files) - indexed,
      results: results
    }}
  end

  @doc """
  Index a single file into the KG.
  """
  def index_file(file_path, opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())

    with {:ok, parsed} <- JidoCode.KG.Parser.parse_file(file_path),
         :ok <- store_parsed_data(parsed, backend) do
      {:ok, %{
        file: file_path,
        modules: length(parsed.modules),
        functions: length(parsed.functions),
        calls: length(parsed.calls)
      }}
    end
  end

  @doc """
  Re-index a file (remove existing facts first).
  """
  def reindex_file(file_path, opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())

    # Remove existing facts for this file
    :ok = backend.update(:remove_facts, [{file_path, :_, :_}], [])

    # Index the file fresh
    index_file(file_path, opts)
  end

  @doc """
  Get all indexed files from the KG.
  """
  def indexed_files(opts \\ []) do
    backend = Keyword.get(opts, :backend, default_backend())

    case backend.query("SELECT * WHERE { ?file a :File }", limit: 1000) do
      {:ok, results} ->
        files = results
        |> Enum.map(fn %{file: file} -> file end)
        |> Enum.uniq()

        {:ok, files}

      {:error, _} ->
        {:ok, []}
    end
  end

  # Store parsed data as triples in the KG
  defp store_parsed_data(parsed, backend) do
    triples = build_triples(parsed)
    backend.update(:add_facts, triples, [])
  end

  # Build KG triples from parsed data
  defp build_triples(parsed) do
    module_triples = build_module_triples(parsed)
    function_triples = build_function_triples(parsed)
    call_triples = build_call_triples(parsed)

    module_triples ++ function_triples ++ call_triples
  end

  defp build_module_triples(parsed) do
    Enum.flat_map(parsed.modules, fn module_name ->
      [
        {{parsed.file, :defines, module_name}},
        {{module_name, :type, :module}},
        {{module_name, :in_file, parsed.file}}
      ]
    end)
  end

  defp build_function_triples(parsed) do
    Enum.flat_map(parsed.functions, fn func ->
      function_id = "#{func.module}.#{func.name}/#{func.arity}"
      [
        {{parsed.file, :defines, function_id}},
        {{function_id, :type, :function}},
        {{function_id, :name, func.name}},
        {{function_id, :arity, func.arity}},
        {{function_id, :in_module, func.module}},
        {{function_id, :in_file, parsed.file}}
      ]
    end)
  end

  defp build_call_triples(parsed) do
    Enum.map(parsed.calls, fn call ->
      caller_id = if call.from_function, do: "#{call.from_module}.#{call.from_function}", else: call.from_module
      callee_id = if call.to_module == call.from_module,
        do: call.to_function,
        else: "#{call.to_module}.#{call.to_function}"

      {{caller_id, :calls, callee_id}}
    end)
  end

  # Find all Elixir files in a directory
  defp find_elixir_files(dir, _extensions, recursive) do
    dir
    |> Path.join(if(recursive, do: "**/*.ex", else: "*.ex"))
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      not String.contains?(path, "/test/") and
      not String.contains?(path, "/_build/")
    end)
  end

  defp default_backend do
    Application.get_env(:jido_code, :kg_backend, JidoCode.KG.MemoryBackend)
  end
end
