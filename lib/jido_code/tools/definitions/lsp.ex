defmodule JidoCode.Tools.Definitions.LSP do
  @moduledoc """
  Tool definitions for Language Server Protocol (LSP) operations.

  This module defines the tools for code intelligence features that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `get_hover_info` - Get type info and documentation at cursor position

  ## Usage

      # Register all LSP tools
      for tool <- LSP.all() do
        :ok = Registry.register(tool)
      end

      # Or get a specific tool
      hover_tool = LSP.get_hover_info()
      :ok = Registry.register(hover_tool)

  ## Note

  These tools require an LSP server to be running. If no LSP server is
  available, the tools will return appropriate error messages.
  """

  alias JidoCode.Tools.Handlers.LSP, as: Handlers
  alias JidoCode.Tools.Tool

  @doc """
  Returns all LSP tools.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [
      get_hover_info()
    ]
  end

  @doc """
  Returns the get_hover_info tool definition.

  Gets type information and documentation at a specific cursor position
  in a file. Useful for understanding function signatures, module docs,
  and type specifications.

  ## Parameters

  - `path` (required, string) - File path to query
  - `line` (required, integer) - Line number (1-indexed)
  - `character` (required, integer) - Character offset in line (1-indexed)

  ## Returns

  On success, returns a map with:
  - `type` - Type signature if available
  - `docs` - Documentation if available
  - `module` - Module information if available

  On failure, returns an error message.

  ## Examples

      # Get hover info for a function call
      %{
        "path" => "lib/my_app/user.ex",
        "line" => 15,
        "character" => 10
      }
  """
  @spec get_hover_info() :: Tool.t()
  def get_hover_info do
    Tool.new!(%{
      name: "get_hover_info",
      description:
        "Get type information and documentation at a cursor position. " <>
          "Returns function signatures, module docs, and type specs. " <>
          "Use to understand code, check function parameters, or explore module APIs.",
      handler: Handlers.GetHoverInfo,
      parameters: [
        %{
          name: "path",
          type: :string,
          description: "File path to query (relative to project root)",
          required: true
        },
        %{
          name: "line",
          type: :integer,
          description: "Line number (1-indexed, as shown in editors)",
          required: true
        },
        %{
          name: "character",
          type: :integer,
          description: "Character offset in the line (1-indexed, as shown in editors)",
          required: true
        }
      ]
    })
  end
end
