defmodule JidoCode.Tools.Definitions.LSP do
  @moduledoc """
  Tool definitions for Language Server Protocol (LSP) operations.

  This module defines the tools for code intelligence features that can be
  registered with the Registry and used by the LLM agent.

  ## Available Tools

  - `get_hover_info` - Get type info and documentation at cursor position
  - `go_to_definition` - Find where a symbol is defined
  - `find_references` - Find all usages of a symbol
  - `get_diagnostics` - Get LSP diagnostics (errors, warnings, info, hints)

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

  alias JidoCode.Tools.Definitions.GetDiagnostics, as: GetDiagnosticsDefinition
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
      get_hover_info(),
      go_to_definition(),
      find_references(),
      get_diagnostics()
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

  @doc """
  Returns the go_to_definition tool definition.

  Finds where a symbol is defined. Returns the file path and position
  of the definition, allowing navigation to function, module, or variable
  declarations.

  ## Parameters

  - `path` (required, string) - File path to query (relative to project root)
  - `line` (required, integer) - Line number (1-indexed)
  - `character` (required, integer) - Character offset in line (1-indexed)

  ## Returns

  On success, returns a map with:
  - `status` - "found", "not_found", or "lsp_not_configured"
  - `definition` - Map with `path`, `line`, `character` of the definition
  - `definitions` - Array of locations if multiple definitions exist

  On failure, returns an error message.

  ## Examples

      # Find definition of a function call
      %{
        "path" => "lib/my_app/user.ex",
        "line" => 15,
        "character" => 10
      }
  """
  @spec go_to_definition() :: Tool.t()
  def go_to_definition do
    Tool.new!(%{
      name: "go_to_definition",
      description:
        "Find where a symbol is defined. " <>
          "Returns the file path and position of the definition. " <>
          "Use to navigate to function, module, or variable declarations.",
      handler: Handlers.GoToDefinition,
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

  @doc """
  Returns the find_references tool definition.

  Finds all usages of a symbol across the codebase. Returns a list of locations
  where the symbol is referenced, allowing exploration of how functions, modules,
  or variables are used throughout the project.

  ## Parameters

  - `path` (required, string) - File path to query (relative to project root)
  - `line` (required, integer) - Line number (1-indexed)
  - `character` (required, integer) - Character offset in line (1-indexed)
  - `include_declaration` (optional, boolean) - Include the declaration in results (default: false)

  ## Returns

  On success, returns a map with:
  - `status` - "found", "not_found", or "lsp_not_configured"
  - `references` - Array of locations with `path`, `line`, `character`
  - `count` - Number of references found

  On failure, returns an error message.

  ## Examples

      # Find all usages of a function
      %{
        "path" => "lib/my_app/user.ex",
        "line" => 15,
        "character" => 10
      }

      # Include the declaration in results
      %{
        "path" => "lib/my_app/user.ex",
        "line" => 15,
        "character" => 10,
        "include_declaration" => true
      }
  """
  @spec find_references() :: Tool.t()
  def find_references do
    Tool.new!(%{
      name: "find_references",
      description:
        "Find all usages of a symbol. " <>
          "Returns a list of locations where the symbol is used. " <>
          "Use to explore function callers, module dependencies, or variable usage.",
      handler: Handlers.FindReferences,
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
        },
        %{
          name: "include_declaration",
          type: :boolean,
          description: "Include the declaration in results (default: false)",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the get_diagnostics tool definition.

  Delegates to `JidoCode.Tools.Definitions.GetDiagnostics.get_diagnostics/0`.
  See that module for full documentation.
  """
  @spec get_diagnostics() :: Tool.t()
  defdelegate get_diagnostics, to: GetDiagnosticsDefinition
end
