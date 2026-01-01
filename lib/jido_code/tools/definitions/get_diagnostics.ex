defmodule JidoCode.Tools.Definitions.GetDiagnostics do
  @moduledoc """
  Tool definition for the get_diagnostics LSP tool.

  This tool retrieves LSP diagnostics (errors, warnings, info, hints) for a
  specific file or the entire workspace. It integrates with the Expert LSP
  server to provide real-time code analysis feedback.

  ## Usage

      # Register the tool
      :ok = Registry.register(GetDiagnostics.get_diagnostics())

      # Execute via Executor
      Executor.execute(%{
        id: "call_123",
        name: "get_diagnostics",
        arguments: %{"path" => "lib/my_app.ex"}
      }, context: context)

  ## Parameters

  - `path` (optional, string) - File path to get diagnostics for. If omitted,
    returns diagnostics for all open files in the workspace.
  - `severity` (optional, string) - Filter by severity level:
    - `"error"` - Compilation errors
    - `"warning"` - Compiler warnings
    - `"info"` - Informational messages
    - `"hint"` - Code hints and suggestions
  - `limit` (optional, integer) - Maximum number of diagnostics to return.
    Useful when dealing with files that have many issues.

  ## Return Format

  Returns a map with:
  - `diagnostics` - List of diagnostic objects, each containing:
    - `severity` - "error", "warning", "info", or "hint"
    - `file` - Relative file path
    - `line` - Line number (1-indexed)
    - `column` - Column number (1-indexed)
    - `message` - Diagnostic message
    - `code` - Diagnostic code (if available)
    - `source` - Source of the diagnostic (e.g., "elixir", "credo")
  - `count` - Total number of diagnostics returned
  - `truncated` - Boolean indicating if results were limited

  ## Examples

      # Get all diagnostics for a file
      %{"path" => "lib/my_app/user.ex"}
      # => %{diagnostics: [...], count: 5, truncated: false}

      # Get only errors
      %{"path" => "lib/my_app/user.ex", "severity" => "error"}
      # => %{diagnostics: [...], count: 2, truncated: false}

      # Get workspace diagnostics with limit
      %{"limit" => 10}
      # => %{diagnostics: [...], count: 10, truncated: true}
  """

  alias JidoCode.Tools.Handlers.LSP.GetDiagnostics, as: Handler
  alias JidoCode.Tools.Tool

  @valid_severities ["error", "warning", "info", "hint"]

  @doc """
  Returns all tools defined in this module.

  ## Returns

  List of `%Tool{}` structs ready for registration.
  """
  @spec all() :: [Tool.t()]
  def all do
    [get_diagnostics()]
  end

  @doc """
  Returns the get_diagnostics tool definition.

  Retrieves LSP diagnostics (errors, warnings, info, hints) for a file
  or workspace. Useful for understanding compilation issues, warnings,
  and code quality hints.

  ## Returns

  A `%Tool{}` struct ready for registration.
  """
  @spec get_diagnostics() :: Tool.t()
  def get_diagnostics do
    Tool.new!(%{
      name: "get_diagnostics",
      description:
        "Get LSP diagnostics (errors, warnings, info, hints) for a file or workspace. " <>
          "Returns compilation errors, warnings, and code hints from the language server. " <>
          "Use to find and understand issues in your code.",
      handler: Handler,
      parameters: [
        %{
          name: "path",
          type: :string,
          description:
            "File path to get diagnostics for (relative to project root). " <>
              "Omit to get diagnostics for all files.",
          required: false
        },
        %{
          name: "severity",
          type: :string,
          description:
            "Filter by severity: 'error', 'warning', 'info', or 'hint'. " <>
              "Omit to get all severities.",
          required: false,
          enum: @valid_severities
        },
        %{
          name: "limit",
          type: :integer,
          description: "Maximum number of diagnostics to return. Omit for no limit.",
          required: false
        }
      ]
    })
  end

  @doc """
  Returns the list of valid severity values.

  ## Returns

  List of severity strings: `["error", "warning", "info", "hint"]`
  """
  @spec valid_severities() :: [String.t()]
  def valid_severities, do: @valid_severities

  @doc """
  Checks if a severity value is valid.

  ## Parameters

  - `severity` - The severity string to validate

  ## Returns

  `true` if valid, `false` otherwise.

  ## Examples

      iex> GetDiagnostics.valid_severity?("error")
      true

      iex> GetDiagnostics.valid_severity?("critical")
      false
  """
  @spec valid_severity?(String.t()) :: boolean()
  def valid_severity?(severity) when is_binary(severity) do
    severity in @valid_severities
  end

  def valid_severity?(_), do: false
end
