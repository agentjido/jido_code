defmodule JidoCode.Tools.Handlers.FileSystem do
  @moduledoc """
  Handler modules for file system tools.

  This module contains sub-modules that implement the execute/2 callback
  for file system operations, delegating to the Security module for
  sandboxed execution with path validation.

  ## Handler Modules

  - `ReadFile` - Read file contents
  - `WriteFile` - Write/overwrite file
  - `ListDirectory` - List directory contents
  - `FileInfo` - Get file metadata
  - `CreateDirectory` - Create directory
  - `DeleteFile` - Delete file (with confirmation)

  ## Usage

  These handlers are invoked by the Executor when the LLM calls file tools:

      # Via Executor
      Executor.execute(%{
        id: "call_123",
        name: "read_file",
        arguments: %{"path" => "src/main.ex"}
      })

  ## Context

  The context map should contain:
  - `:project_root` - Base directory for operations

  If project_root is not in context, it's fetched from the Manager.
  """

  alias JidoCode.Tools.{HandlerHelpers, Security}

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  def format_error(:enoent, path), do: "File not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"
  def format_error(:eisdir, path), do: "Is a directory: #{path}"
  def format_error(:enotdir, path), do: "Not a directory: #{path}"
  def format_error(:enospc, _path), do: "No space left on device"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(:symlink_escapes_boundary, path),
    do: "Security error: symlink points outside project: #{path}"

  def format_error(reason, path) when is_atom(reason), do: "File error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  # ============================================================================
  # ReadFile Handler
  # ============================================================================

  defmodule ReadFile do
    @moduledoc """
    Handler for the read_file tool.

    Reads the contents of a file within the project boundary.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Reads the contents of a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)

    ## Returns

    - `{:ok, content}` - File contents as string
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root),
           {:ok, content} <- File.read(safe_path) do
        {:ok, content}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "read_file requires a path argument"}
    end
  end

  # ============================================================================
  # WriteFile Handler
  # ============================================================================

  defmodule WriteFile do
    @moduledoc """
    Handler for the write_file tool.

    Writes content to a file, creating parent directories if needed.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Writes content to a file.

    ## Arguments

    - `"path"` - Path to the file (relative to project root)
    - `"content"` - Content to write

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "content" => content}, context)
        when is_binary(path) and is_binary(content) do
      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root),
           :ok <- safe_path |> Path.dirname() |> File.mkdir_p(),
           :ok <- File.write(safe_path, content) do
        {:ok, "File written successfully: #{path}"}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "write_file requires path and content arguments"}
    end
  end

  # ============================================================================
  # ListDirectory Handler
  # ============================================================================

  defmodule ListDirectory do
    @moduledoc """
    Handler for the list_directory tool.

    Lists the contents of a directory with optional recursive listing.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Lists directory contents.

    ## Arguments

    - `"path"` - Path to the directory (relative to project root)
    - `"recursive"` - Whether to list recursively (optional, default false)

    ## Returns

    - `{:ok, entries}` - JSON-encoded list of entries
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path} = args, context) when is_binary(path) do
      recursive = Map.get(args, "recursive", false)

      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root) do
        list_entries(safe_path, project_root, recursive)
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "list_directory requires a path argument"}
    end

    defp list_entries(path, _project_root, false) do
      case File.ls(path) do
        {:ok, entries} ->
          result = entries |> Enum.sort() |> Enum.map(&entry_info(path, &1))
          {:ok, Jason.encode!(result)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    defp list_entries(path, project_root, true) do
      case list_recursive(path, project_root) do
        {:ok, entries} ->
          {:ok, Jason.encode!(entries)}

        {:error, reason} ->
          {:error, FileSystem.format_error(reason, path)}
      end
    end

    defp entry_info(parent_path, entry) do
      full_path = Path.join(parent_path, entry)
      type = if File.dir?(full_path), do: "directory", else: "file"
      %{name: entry, type: type}
    end

    defp list_recursive(path, project_root) do
      case File.ls(path) do
        {:ok, entries} ->
          results = entries |> Enum.sort() |> Enum.flat_map(&expand_entry(path, &1, project_root))
          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end

    defp expand_entry(parent_path, entry, project_root) do
      full_path = Path.join(parent_path, entry)
      relative_path = Path.relative_to(full_path, project_root)

      if File.dir?(full_path) do
        expand_directory(full_path, relative_path, project_root)
      else
        [%{name: relative_path, type: "file"}]
      end
    end

    defp expand_directory(full_path, relative_path, project_root) do
      case list_recursive(full_path, project_root) do
        {:ok, children} ->
          [%{name: relative_path, type: "directory"} | children]

        {:error, _} ->
          [%{name: relative_path, type: "directory", error: "unreadable"}]
      end
    end
  end

  # ============================================================================
  # FileInfo Handler
  # ============================================================================

  defmodule FileInfo do
    @moduledoc """
    Handler for the file_info tool.

    Gets metadata about a file or directory.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Gets file metadata.

    ## Arguments

    - `"path"` - Path to the file/directory (relative to project root)

    ## Returns

    - `{:ok, info}` - JSON-encoded metadata map
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root),
           {:ok, stat} <- File.stat(safe_path) do
        info = %{
          path: path,
          size: stat.size,
          type: Atom.to_string(stat.type),
          access: Atom.to_string(stat.access),
          atime: format_datetime(stat.atime),
          mtime: format_datetime(stat.mtime),
          ctime: format_datetime(stat.ctime)
        }

        {:ok, Jason.encode!(info)}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "file_info requires a path argument"}
    end

    defp format_datetime({{year, month, day}, {hour, min, sec}}) do
      "#{year}-#{pad(month)}-#{pad(day)} #{pad(hour)}:#{pad(min)}:#{pad(sec)}"
    end

    defp format_datetime(_), do: nil

    defp pad(n) when n < 10, do: "0#{n}"
    defp pad(n), do: "#{n}"
  end

  # ============================================================================
  # CreateDirectory Handler
  # ============================================================================

  defmodule CreateDirectory do
    @moduledoc """
    Handler for the create_directory tool.

    Creates a directory, including parent directories.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Creates a directory.

    ## Arguments

    - `"path"` - Path to the directory to create (relative to project root)

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path}, context) when is_binary(path) do
      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root),
           :ok <- File.mkdir_p(safe_path) do
        {:ok, "Directory created successfully: #{path}"}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(_args, _context) do
      {:error, "create_directory requires a path argument"}
    end
  end

  # ============================================================================
  # DeleteFile Handler
  # ============================================================================

  defmodule DeleteFile do
    @moduledoc """
    Handler for the delete_file tool.

    Deletes a file with confirmation requirement for safety.
    """

    alias JidoCode.Tools.Handlers.FileSystem
    alias JidoCode.Tools.Security

    @doc """
    Deletes a file.

    ## Arguments

    - `"path"` - Path to the file to delete (relative to project root)
    - `"confirm"` - Must be true to actually delete

    ## Returns

    - `{:ok, message}` - Success message
    - `{:error, reason}` - Error message
    """
    def execute(%{"path" => path, "confirm" => true}, context) when is_binary(path) do
      with {:ok, project_root} <- FileSystem.get_project_root(context),
           {:ok, safe_path} <- Security.validate_path(path, project_root),
           :ok <- File.rm(safe_path) do
        {:ok, "File deleted successfully: #{path}"}
      else
        {:error, reason} -> {:error, FileSystem.format_error(reason, path)}
      end
    end

    def execute(%{"path" => _path, "confirm" => false}, _context) do
      {:error, "Delete operation requires confirm=true"}
    end

    def execute(%{"path" => _path}, _context) do
      {:error, "delete_file requires confirm parameter set to true"}
    end

    def execute(_args, _context) do
      {:error, "delete_file requires path and confirm arguments"}
    end
  end
end
