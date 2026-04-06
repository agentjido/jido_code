defmodule JidoCode.KG.Parser do
  @moduledoc """
  Parse Elixir source code and extract structural information.

  Extracts modules, functions, and call relationships from Elixir AST
  to populate the Knowledge Graph.
  """

  @doc """
  Parse an Elixir source file and extract code structure.

  Returns a map containing:
  - modules: list of module names
  - functions: list of function definitions
  - calls: list of function call relationships
  """
  def parse_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        parse_string(content, file_path)

      {:error, reason} ->
        {:error, :file_read_error, reason}
    end
  end

  @doc """
  Parse Elixir source code string and extract structure.
  """
  def parse_string(code, file_path \\ "<unknown>") do
    case Code.string_to_quoted(code, file: file_path, columns: true) do
      {:ok, ast} ->
        extract_structure(ast, file_path)

      {:error, {_location, _mod, msg}} when is_binary(msg) ->
        {:error, :parse_error, msg}

      {:error, _} = error ->
        error
    end
  end

  # Extract structure from AST
  defp extract_structure(ast, file_path) do
    acc = %{
      file: file_path,
      current_module: nil,
      modules: MapSet.new(),
      functions: [],
      calls: []
    }

    acc = traverse(ast, acc)

    {:ok, %{
      file: file_path,
      modules: MapSet.to_list(acc.modules),
      functions: Enum.reverse(acc.functions),
      calls: Enum.reverse(acc.calls)
    }}
  end

  # Traverse AST and extract information
  defp traverse({:defmodule, _meta, args}, acc) do
    [module_alias, body_args] = args

    # Handle both [module, [do: body]] and [module, do: body] formats
    body = case body_args do
      [do: body] -> body
      [[do: body]] -> body
      keyword when is_list(keyword) -> Keyword.get(keyword, :do, nil)
      _ -> body_args
    end

    module_name = extract_module_name(module_alias)

    # Update context with current module
    acc = %{acc | current_module: module_name}
    acc = %{acc | modules: MapSet.put(acc.modules, module_name)}

    # Traverse body
    traverse(body, acc)
  end

  defp traverse({:def, _meta, args}, acc) do
    {function_info, acc} = extract_function_info(:def, args, acc)
    acc = %{acc | functions: [function_info | acc.functions]}

    # Also traverse body for calls
    traverse_body(args, acc)
  end

  defp traverse({:defp, _meta, args}, acc) do
    {function_info, acc} = extract_function_info(:defp, args, acc)
    acc = %{acc | functions: [function_info | acc.functions]}

    # Also traverse body for calls
    traverse_body(args, acc)
  end

  defp traverse({{:., _, [module, function]}, _meta, args}, acc) when is_list(args) do
    # External function call like Module.function()
    call_info = extract_external_call(module, function, length(args), acc)
    acc = if call_info, do: %{acc | calls: [call_info | acc.calls]}, else: acc

    # Recurse into arguments
    Enum.reduce(args, acc, &traverse/2)
  end

  defp traverse({{:., _, [{:__aliases__, _, parts}, function]}, _meta, args}, acc) when is_list(args) do
    # External function call like Alias.function()
    module_name = Enum.map_join(parts, ".", &Atom.to_string/1)
    call_info = %{
      from_module: acc.current_module,
      to_module: module_name,
      to_function: function,
      to_arity: length(args)
    }
    acc = %{acc | calls: [call_info | acc.calls]}

    # Recurse into arguments
    Enum.reduce(args, acc, &traverse/2)
  end

  defp traverse({function, _meta, args}, acc) when is_atom(function) and is_list(args) and length(args) > 0 do
    # Local function call like function()
    call_info = %{
      from_module: acc.current_module,
      to_module: acc.current_module,
      to_function: function,
      to_arity: length(args)
    }
    acc = %{acc | calls: [call_info | acc.calls]}

    # Recurse into arguments
    Enum.reduce(args, acc, &traverse/2)
  end

  defp traverse({left, right}, acc) do
    acc = traverse(left, acc)
    traverse(right, acc)
  end

  defp traverse(list, acc) when is_list(list) do
    Enum.reduce(list, acc, &traverse/2)
  end

  defp traverse(_ast, acc), do: acc

  # Extract function info from def/defp args
  defp extract_function_info(kind, args, acc) do
    {name, arity, line} = case args do
      [{:when, _, [call | _]}, [do: _body]] ->
        {extract_name(call), extract_arity(call), extract_line(call)}

      [{:when, _, [call | _]}, do: _body] ->
        {extract_name(call), extract_arity(call), extract_line(call)}

      [call, [do: _body]] ->
        {extract_name(call), extract_arity(call), extract_line(call)}

      [call, do: _body] ->
        {extract_name(call), extract_arity(call), extract_line(call)}

      _ ->
        {:unknown, 0, 0}
    end

    {%{
      name: name,
      arity: arity,
      kind: kind,
      module: acc.current_module,
      line: line
    }, acc}
  end

  # Traverse function body to extract calls
  defp traverse_body(args, acc) do
    body = case args do
      [{:when, _, [_ | _]}, [do: body]] -> body
      [{:when, _, [_ | _]}, do: body] -> body
      [_call, [do: body]] -> body
      [_call, do: body] -> body
      _ -> nil
    end

    if body, do: traverse(body, acc), else: acc
  end

  # Extract module name from alias
  defp extract_module_name({:__aliases__, _, parts}) do
    Enum.map_join(parts, ".", &Atom.to_string/1)
  end

  defp extract_module_name(atom) when is_atom(atom) do
    Atom.to_string(atom)
  end

  defp extract_module_name(_), do: "Unknown"

  # Extract function name from call AST
  defp extract_name({name, _, _}) when is_atom(name), do: name
  defp extract_name(_), do: :unknown

  # Extract arity from call AST
  defp extract_arity({_, _, args}) when is_list(args), do: length(args)
  defp extract_arity(_), do: 0

  # Extract line number from AST
  defp extract_line(ast) do
    case ast do
      {_, meta, _} when is_list(meta) -> Keyword.get(meta, :line, 0)
      _ -> 0
    end
  end

  # Extract external call info
  defp extract_external_call(module, function, arity, acc) do
    module_name = cond do
      is_atom(module) -> Atom.to_string(module)
      is_tuple(module) -> extract_module_name(module)
      true -> inspect(module)
    end

    %{
      from_module: acc.current_module,
      to_module: module_name,
      to_function: function,
      to_arity: arity
    }
  end
end
