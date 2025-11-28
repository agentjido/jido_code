defmodule JidoCode.Tools.Definitions.FileSystem do
  @moduledoc """
  Tool definitions for file system operations.

  This module defines the tools for file system operations that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `read_file` - Read file contents
  - `write_file` - Write/overwrite file
  - `list_directory` - List directory contents
  - `file_info` - Get file metadata
  - `create_directory` - Create directory
  - `delete_file` - Delete file (with confirmation)

  ## Usage

      # Register all file system tools
      for tool <- FileSystem.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      read_file_tool = FileSystem.read_file()
      :ok = Registry.register(read_file_tool)
  """

  alias JidoCode.Tools.Handlers.FileSystem, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all file system tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      read_file(),
      write_file(),
      list_directory(),
      file_info(),
      create_directory(),
      delete_file()
    ]
  end

  @doc """
  Returns the read_file tool definition.

  Reads the contents of a file within the project boundary.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  """
  @spec read_file() :: Tool.t()
  def read_file do
    Tool.new!(%{
      name: "read_file",
      description: "Read the contents of a file. Returns the file content as a string.",
      handler: Handlers.ReadFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to read (relative to project root)",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the write_file tool definition.

  Writes content to a file, creating parent directories if needed.

  ## Parameters

  - `path` (required, string) - Path to the file relative to project root
  - `content` (required, string) - Content to write to the file
  """
  @spec write_file() :: Tool.t()
  def write_file do
    Tool.new!(%{
      name: "write_file",
      description:
        "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Creates parent directories automatically.",
      handler: Handlers.WriteFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to write (relative to project root)",
          required: true
        },
        %{
          name: "content",
          type: :string,
          description: "Content to write to the file",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the list_directory tool definition.

  Lists the contents of a directory with optional recursive listing.

  ## Parameters

  - `path` (required, string) - Path to the directory relative to project root
  - `recursive` (optional, boolean) - Whether to list recursively (default: false)
  """
  @spec list_directory() :: Tool.t()
  def list_directory do
    Tool.new!(%{
      name: "list_directory",
      description:
        "List the contents of a directory. Returns a JSON array of entries with name and type (file or directory).",
      handler: Handlers.ListDirectory,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the directory to list (relative to project root)",
          required: true
        },
        %{
          name: "recursive",
          type: :boolean,
          description: "Whether to list contents recursively (default: false)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the file_info tool definition.

  Gets metadata about a file or directory.

  ## Parameters

  - `path` (required, string) - Path to the file/directory relative to project root
  """
  @spec file_info() :: Tool.t()
  def file_info do
    Tool.new!(%{
      name: "file_info",
      description:
        "Get metadata about a file or directory. Returns JSON with size, type, access mode, and timestamps.",
      handler: Handlers.FileInfo,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file or directory (relative to project root)",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the create_directory tool definition.

  Creates a directory, including parent directories.

  ## Parameters

  - `path` (required, string) - Path to the directory to create relative to project root
  """
  @spec create_directory() :: Tool.t()
  def create_directory do
    Tool.new!(%{
      name: "create_directory",
      description:
        "Create a directory. Creates parent directories automatically if they don't exist.",
      handler: Handlers.CreateDirectory,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the directory to create (relative to project root)",
          required: true
        }
      ]
    })
  end

  @doc """
  Returns the delete_file tool definition.

  Deletes a file with confirmation requirement for safety.

  ## Parameters

  - `path` (required, string) - Path to the file to delete relative to project root
  - `confirm` (required, boolean) - Must be true to confirm deletion
  """
  @spec delete_file() :: Tool.t()
  def delete_file do
    Tool.new!(%{
      name: "delete_file",
      description:
        "Delete a file. Requires explicit confirmation (confirm=true) to prevent accidental deletions.",
      handler: Handlers.DeleteFile,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "Path to the file to delete (relative to project root)",
          required: true
        },
        %{
          name: "confirm",
          type: :boolean,
          description: "Must be set to true to confirm the deletion",
          required: true
        }
      ]
    })
  end
end
