defmodule JidoCode.Actions.SearchCode do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to search for text within files in the workspace.

  Supports case-sensitive and case-insensitive search with
  regex pattern support.
  """

  use Jido.Action,
    name: "jido_code_search_code",
    description: "Search for text within files in the workspace.",
    schema: [
      query: [type: :string, required: true],
      path: [type: :string, default: "."],
      case_sensitive: [type: :boolean, default: false],
      regex: [type: :boolean, default: false],
      file_pattern: [type: :string, default: nil],
      max_results: [type: :integer, default: 100]
    ]

  @impl true
  def run(params, context) do
    %{
      query: query,
      path: path,
      case_sensitive: case_sensitive,
      regex: regex,
      file_pattern: file_pattern,
      max_results: max_results
    } = params

    with {:ok, workspace_path} <- workspace_path(context),
         full_path = Path.expand(path, workspace_path),
         :ok <- validate_path_within_workspace(full_path, workspace_path) do
      results = search_in_directory(full_path, query, case_sensitive, regex, file_pattern, max_results)

      {:ok,
       %{
         query: query,
         path: path,
         results: results,
         count: length(results),
         truncated?: length(results) >= max_results and max_results > 0
       }}
    else
      {:error, :enoent} -> {:error, :directory_not_found, "Directory not found: #{path}"}
      {:error, :outside_workspace} -> {:error, :invalid_path, "Path outside workspace: #{path}"}
      {:error, reason} -> {:error, reason}
    end
  end

  defp workspace_path(context) do
    path =
      context[:workspace_path] ||
        get_in(context, [:project, :workspace_path]) ||
        get_in(context, [:tool_context, :workspace_path]) ||
        get_in(context, [:tool_context, "workspace_path"])

    if is_binary(path) and String.trim(path) != "" do
      {:ok, path}
    else
      {:error, :missing_workspace_path}
    end
  end

  defp validate_path_within_workspace(path, workspace_path) do
    if File.dir?(path) do
      workspace_expanded = Path.expand(workspace_path)
      path_expanded = Path.expand(path)

      case String.starts_with?(path_expanded, workspace_expanded) do
        true -> :ok
        false -> {:error, :outside_workspace}
      end
    else
      {:error, :enoent}
    end
  end

  defp search_in_directory(dir, query, case_sensitive, regex, file_pattern, max_results) do
    wildcard = if(file_pattern, do: file_pattern, else: "**/*")

    pattern =
      cond do
        regex -> compile_regex(query, case_sensitive)
        true -> :string
      end

    dir
    |> Path.join(wildcard)
    |> Path.wildcard()
    |> Enum.filter(&File.regular?/1)
    |> Enum.flat_map(fn file ->
      search_in_file(file, query, pattern, case_sensitive)
    end)
    |> Enum.take(max_results)
  end

  defp compile_regex(query, case_sensitive) do
    opts = if(case_sensitive, do: [], else: [:caseless])

    case Regex.compile(query, opts) do
      {:ok, regex} -> regex
      _ -> nil
    end
  end

  defp search_in_file(file, query, :string, case_sensitive) do
    search_text = if(case_sensitive, do: query, else: String.downcase(query))

    file
    |> File.stream!([], :line)
    |> Enum.with_index(1)
    |> Enum.filter(fn {line, _line_num} ->
      text = if(case_sensitive, do: line, else: String.downcase(line))
      String.contains?(text, search_text)
    end)
    |> Enum.map(fn {line, line_num} ->
      %{
        file: Path.basename(file),
        file_path: file,
        line: line_num,
        content: String.trim(line)
      }
    end)
  end

  defp search_in_file(_file, _query, nil, _case_sensitive), do: []

  defp search_in_file(file, _query, regex, _case_sensitive) when is_struct(regex, Regex) do
    file
    |> File.read!()
    |> then(fn content ->
      Regex.run(regex, content, return: :index)
    end)
    |> case do
      nil -> []
      matches -> build_match_results(file, matches)
    end
  end

  defp build_match_results(file, matches) do
    {content, _} = File.read(file)

    matches
    |> Enum.map(fn {start, length} ->
      {line, line_content} =
        content
        |> String.split_at(start)
        |> then(fn {before_match, rest} ->
          {line_num_before, _} =
            before_match
            |> String.split("\n")
            |> then(fn lines -> {length(lines) - 1, Enum.join(lines, "\n")} end)

          {line_content, _} = String.split_at(rest, length)

          {line_num_before + 1, String.trim(line_content)}
        end)

      %{
        file: Path.basename(file),
        file_path: file,
        line: line,
        content: line_content
      }
    end)
  end
end
