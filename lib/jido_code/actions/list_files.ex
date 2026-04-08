defmodule JidoCode.Actions.ListFiles do
  # covers: architecture.agent_os_integration.actions
  @moduledoc """
  Action to list files in a directory within the workspace.

  Supports filtering by extension and recursive listing.
  """

  use Jido.Action,
    name: "jido_code_list_files",
    description: "List files in a directory within the workspace.",
    schema: [
      path: [type: :string, default: "."],
      recursive: [type: :boolean, default: false],
      extensions: [type: {:list, :string}, default: nil],
      include_hidden: [type: :boolean, default: false],
      max_results: [type: :integer, default: 1000]
    ]

  @impl true
  def run(params, context) do
    %{
      path: path,
      recursive: recursive,
      extensions: extensions,
      include_hidden: include_hidden,
      max_results: max_results
    } = params

    with {:ok, workspace_path} <- workspace_path(context),
         full_path = Path.expand(path, workspace_path),
         :ok <- validate_path_within_workspace(full_path, workspace_path),
         {:ok, files} <- list_directory(full_path, recursive, extensions, include_hidden, max_results) do
      relative_paths = Enum.map(files, &Path.relative_to(&1, full_path))

      {:ok,
       %{
         path: path,
         full_path: full_path,
         files: relative_paths,
         count: length(relative_paths),
         truncated?: length(files) >= max_results and max_results > 0
       }}
    else
      {:error, :enoent} -> {:error, :directory_not_found, "Directory not found: #{path}"}
      {:error, :enotdir} -> {:error, :not_a_directory, "Not a directory: #{path}"}
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
    workspace_expanded = Path.expand(workspace_path)
    path_expanded = Path.expand(path)

    case String.starts_with?(path_expanded, workspace_expanded) do
      true -> :ok
      false -> {:error, :outside_workspace}
    end
  end

  defp list_directory(path, recursive, extensions, include_hidden, max_results) do
    wildcard = if(recursive, do: "**", else: "*")

    files =
      Path.wildcard(Path.join(path, wildcard))
      |> Enum.filter(&File.regular?/1)
      |> Enum.filter(&(include_hidden or not hidden_file?(&1)))
      |> Enum.filter(&extension_match?(&1, extensions))
      |> Enum.take(max_results)

    {:ok, files}
  end

  defp hidden_file?(path) do
    basename = Path.basename(path)
    String.starts_with?(basename, ".")
  end

  defp extension_match?(_path, nil), do: true
  defp extension_match?(_path, []), do: true

  defp extension_match?(path, extensions) when is_list(extensions) do
    ext = Path.extname(path)
    ext in extensions or ext == ""
  end
end
