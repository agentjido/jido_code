defmodule JidoCode.Tools.LSP.Protocol do
  @moduledoc """
  LSP (Language Server Protocol) type definitions and constants.

  This module defines typed structs for LSP messages and provides helper
  functions for converting between Elixir structs and LSP JSON formats.

  ## Types

  The LSP specification uses 0-indexed positions, but editors typically
  display 1-indexed positions to users. This module provides conversion
  helpers to handle this difference.

  ## Reference

  - LSP Specification: https://microsoft.github.io/language-server-protocol/
  - Expert: https://github.com/elixir-lang/expert
  """

  # ============================================================================
  # LSP Method Constants
  # ============================================================================

  @doc "LSP method for textDocument/hover"
  def method_hover, do: "textDocument/hover"

  @doc "LSP method for textDocument/definition"
  def method_definition, do: "textDocument/definition"

  @doc "LSP method for textDocument/references"
  def method_references, do: "textDocument/references"

  @doc "LSP method for textDocument/publishDiagnostics"
  def method_publish_diagnostics, do: "textDocument/publishDiagnostics"

  @doc "LSP method for textDocument/didOpen"
  def method_did_open, do: "textDocument/didOpen"

  @doc "LSP method for textDocument/didClose"
  def method_did_close, do: "textDocument/didClose"

  @doc "LSP method for textDocument/didChange"
  def method_did_change, do: "textDocument/didChange"

  @doc "LSP method for textDocument/didSave"
  def method_did_save, do: "textDocument/didSave"

  @doc "LSP method for textDocument/completion"
  def method_completion, do: "textDocument/completion"

  @doc "LSP method for textDocument/signatureHelp"
  def method_signature_help, do: "textDocument/signatureHelp"

  @doc "LSP method for textDocument/documentSymbol"
  def method_document_symbol, do: "textDocument/documentSymbol"

  @doc "LSP method for workspace/symbol"
  def method_workspace_symbol, do: "workspace/symbol"

  # ============================================================================
  # Position Type
  # ============================================================================

  defmodule Position do
    @moduledoc """
    Represents a position in a text document.

    LSP uses 0-indexed line and character positions.

    ## Fields

      * `:line` - Zero-indexed line number
      * `:character` - Zero-indexed character offset (UTF-16 code units)

    ## Examples

        # Create a position (0-indexed)
        pos = Position.new(10, 5)

        # Convert from 1-indexed (editor display)
        pos = Position.from_editor(11, 6)

        # Convert to 1-indexed for display
        {line, char} = Position.to_editor(pos)
    """

    @enforce_keys [:line, :character]
    defstruct [:line, :character]

    @type t :: %__MODULE__{
            line: non_neg_integer(),
            character: non_neg_integer()
          }

    @doc "Creates a new Position with 0-indexed values."
    @spec new(non_neg_integer(), non_neg_integer()) :: t()
    def new(line, character) when is_integer(line) and is_integer(character) do
      %__MODULE__{line: max(0, line), character: max(0, character)}
    end

    @doc "Creates a Position from 1-indexed editor coordinates."
    @spec from_editor(pos_integer(), pos_integer()) :: t()
    def from_editor(line, character)
        when is_integer(line) and is_integer(character) and line >= 1 and character >= 1 do
      %__MODULE__{line: line - 1, character: character - 1}
    end

    @doc "Converts a Position to 1-indexed editor coordinates."
    @spec to_editor(t()) :: {pos_integer(), pos_integer()}
    def to_editor(%__MODULE__{line: line, character: character}) do
      {line + 1, character + 1}
    end

    @doc "Converts a Position to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{line: line, character: character}) do
      %{"line" => line, "character" => character}
    end

    @doc "Parses a Position from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_position}
    def from_lsp(%{"line" => line, "character" => character})
        when is_integer(line) and is_integer(character) do
      {:ok, new(line, character)}
    end

    def from_lsp(_), do: {:error, :invalid_position}
  end

  # ============================================================================
  # Range Type
  # ============================================================================

  defmodule Range do
    @moduledoc """
    Represents a range in a text document.

    A range is defined by a start and end position.

    ## Fields

      * `:start` - Start position (inclusive)
      * `:end` - End position (exclusive)
    """

    alias JidoCode.Tools.LSP.Protocol.Position

    @enforce_keys [:start, :end]
    defstruct [:start, :end]

    @type t :: %__MODULE__{
            start: Position.t(),
            end: Position.t()
          }

    @doc "Creates a new Range."
    @spec new(Position.t(), Position.t()) :: t()
    def new(%Position{} = start_pos, %Position{} = end_pos) do
      %__MODULE__{start: start_pos, end: end_pos}
    end

    @doc "Creates a Range from 1-indexed editor coordinates."
    @spec from_editor(
            {pos_integer(), pos_integer()},
            {pos_integer(), pos_integer()}
          ) :: t()
    def from_editor({start_line, start_char}, {end_line, end_char}) do
      %__MODULE__{
        start: Position.from_editor(start_line, start_char),
        end: Position.from_editor(end_line, end_char)
      }
    end

    @doc "Converts a Range to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{start: start_pos, end: end_pos}) do
      %{
        "start" => Position.to_lsp(start_pos),
        "end" => Position.to_lsp(end_pos)
      }
    end

    @doc "Parses a Range from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_range}
    def from_lsp(%{"start" => start_map, "end" => end_map})
        when is_map(start_map) and is_map(end_map) do
      with {:ok, start_pos} <- Position.from_lsp(start_map),
           {:ok, end_pos} <- Position.from_lsp(end_map) do
        {:ok, new(start_pos, end_pos)}
      else
        _ -> {:error, :invalid_range}
      end
    end

    def from_lsp(_), do: {:error, :invalid_range}
  end

  # ============================================================================
  # Location Type
  # ============================================================================

  defmodule Location do
    @moduledoc """
    Represents a location in a text document.

    A location combines a URI with a range.

    ## Fields

      * `:uri` - Document URI (e.g., "file:///path/to/file.ex")
      * `:range` - Range within the document
    """

    alias JidoCode.Tools.LSP.Protocol.Range

    @enforce_keys [:uri, :range]
    defstruct [:uri, :range]

    @type t :: %__MODULE__{
            uri: String.t(),
            range: Range.t()
          }

    @doc "Creates a new Location."
    @spec new(String.t(), Range.t()) :: t()
    def new(uri, %Range{} = range) when is_binary(uri) do
      %__MODULE__{uri: uri, range: range}
    end

    @doc "Extracts the file path from the URI."
    @spec path(t()) :: {:ok, String.t()} | {:error, :invalid_uri}
    def path(%__MODULE__{uri: uri}) do
      case URI.parse(uri) do
        %URI{scheme: "file", path: path} when is_binary(path) ->
          {:ok, URI.decode(path)}

        _ ->
          {:error, :invalid_uri}
      end
    end

    @doc "Creates a Location from a file path and range."
    @spec from_path(String.t(), Range.t()) :: t()
    def from_path(path, %Range{} = range) when is_binary(path) do
      uri = "file://#{path}"
      %__MODULE__{uri: uri, range: range}
    end

    @doc "Converts a Location to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{uri: uri, range: range}) do
      %{
        "uri" => uri,
        "range" => Range.to_lsp(range)
      }
    end

    @doc "Parses a Location from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_location}
    def from_lsp(%{"uri" => uri, "range" => range_map})
        when is_binary(uri) and is_map(range_map) do
      case Range.from_lsp(range_map) do
        {:ok, range} -> {:ok, new(uri, range)}
        _ -> {:error, :invalid_location}
      end
    end

    def from_lsp(_), do: {:error, :invalid_location}
  end

  # ============================================================================
  # TextDocumentIdentifier Type
  # ============================================================================

  defmodule TextDocumentIdentifier do
    @moduledoc """
    Identifies a text document by its URI.

    ## Fields

      * `:uri` - Document URI
    """

    @enforce_keys [:uri]
    defstruct [:uri]

    @type t :: %__MODULE__{
            uri: String.t()
          }

    @doc "Creates a new TextDocumentIdentifier."
    @spec new(String.t()) :: t()
    def new(uri) when is_binary(uri) do
      %__MODULE__{uri: uri}
    end

    @doc "Creates a TextDocumentIdentifier from a file path."
    @spec from_path(String.t()) :: t()
    def from_path(path) when is_binary(path) do
      %__MODULE__{uri: "file://#{path}"}
    end

    @doc "Converts to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{uri: uri}) do
      %{"uri" => uri}
    end

    @doc "Parses from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_text_document_identifier}
    def from_lsp(%{"uri" => uri}) when is_binary(uri) do
      {:ok, new(uri)}
    end

    def from_lsp(_), do: {:error, :invalid_text_document_identifier}
  end

  # ============================================================================
  # TextDocumentPositionParams Type
  # ============================================================================

  defmodule TextDocumentPositionParams do
    @moduledoc """
    Parameters for requests that need a text document and position.

    Used by hover, definition, references, etc.

    ## Fields

      * `:text_document` - The document identifier
      * `:position` - The position within the document
    """

    alias JidoCode.Tools.LSP.Protocol.{Position, TextDocumentIdentifier}

    @enforce_keys [:text_document, :position]
    defstruct [:text_document, :position]

    @type t :: %__MODULE__{
            text_document: TextDocumentIdentifier.t(),
            position: Position.t()
          }

    @doc "Creates new TextDocumentPositionParams."
    @spec new(TextDocumentIdentifier.t(), Position.t()) :: t()
    def new(%TextDocumentIdentifier{} = text_document, %Position{} = position) do
      %__MODULE__{text_document: text_document, position: position}
    end

    @doc "Creates params from file path and 1-indexed editor position."
    @spec from_editor(String.t(), pos_integer(), pos_integer()) :: t()
    def from_editor(path, line, character)
        when is_binary(path) and is_integer(line) and is_integer(character) do
      %__MODULE__{
        text_document: TextDocumentIdentifier.from_path(path),
        position: Position.from_editor(line, character)
      }
    end

    @doc "Converts to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{text_document: doc, position: pos}) do
      %{
        "textDocument" => TextDocumentIdentifier.to_lsp(doc),
        "position" => Position.to_lsp(pos)
      }
    end
  end

  # ============================================================================
  # Diagnostic Type
  # ============================================================================

  defmodule Diagnostic do
    @moduledoc """
    Represents a diagnostic (error, warning, etc.) in a document.

    ## Fields

      * `:range` - Range where the diagnostic applies
      * `:severity` - Severity level (1=error, 2=warning, 3=info, 4=hint)
      * `:code` - Diagnostic code (optional)
      * `:source` - Source of the diagnostic (e.g., "elixir")
      * `:message` - Diagnostic message
      * `:related_information` - Related diagnostic information (optional)

    ## Severity Levels

      * 1 - Error
      * 2 - Warning
      * 3 - Information
      * 4 - Hint
    """

    alias JidoCode.Tools.LSP.Protocol.Range

    @enforce_keys [:range, :message]
    defstruct [:range, :severity, :code, :source, :message, :related_information]

    @type severity :: 1 | 2 | 3 | 4
    @type t :: %__MODULE__{
            range: Range.t(),
            severity: severity() | nil,
            code: String.t() | integer() | nil,
            source: String.t() | nil,
            message: String.t(),
            related_information: list() | nil
          }

    @severity_error 1
    @severity_warning 2
    @severity_info 3
    @severity_hint 4

    @doc "Returns the severity value for error."
    def severity_error, do: @severity_error

    @doc "Returns the severity value for warning."
    def severity_warning, do: @severity_warning

    @doc "Returns the severity value for info."
    def severity_info, do: @severity_info

    @doc "Returns the severity value for hint."
    def severity_hint, do: @severity_hint

    @doc "Creates a new Diagnostic."
    @spec new(Range.t(), String.t(), keyword()) :: t()
    def new(%Range{} = range, message, opts \\ []) when is_binary(message) do
      %__MODULE__{
        range: range,
        message: message,
        severity: Keyword.get(opts, :severity),
        code: Keyword.get(opts, :code),
        source: Keyword.get(opts, :source),
        related_information: Keyword.get(opts, :related_information)
      }
    end

    @doc "Converts severity integer to atom."
    @spec severity_to_atom(severity() | nil) :: :error | :warning | :info | :hint | nil
    def severity_to_atom(1), do: :error
    def severity_to_atom(2), do: :warning
    def severity_to_atom(3), do: :info
    def severity_to_atom(4), do: :hint
    def severity_to_atom(_), do: nil

    @doc "Converts severity atom to integer."
    @spec severity_from_atom(:error | :warning | :info | :hint) :: severity()
    def severity_from_atom(:error), do: 1
    def severity_from_atom(:warning), do: 2
    def severity_from_atom(:info), do: 3
    def severity_from_atom(:hint), do: 4

    @doc "Parses a Diagnostic from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_diagnostic}
    def from_lsp(%{"range" => range_map, "message" => message} = lsp)
        when is_map(range_map) and is_binary(message) do
      case Range.from_lsp(range_map) do
        {:ok, range} ->
          diagnostic = %__MODULE__{
            range: range,
            message: message,
            severity: Map.get(lsp, "severity"),
            code: Map.get(lsp, "code"),
            source: Map.get(lsp, "source"),
            related_information: Map.get(lsp, "relatedInformation")
          }

          {:ok, diagnostic}

        _ ->
          {:error, :invalid_diagnostic}
      end
    end

    def from_lsp(_), do: {:error, :invalid_diagnostic}

    @doc "Converts a Diagnostic to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{} = diag) do
      base = %{
        "range" => Range.to_lsp(diag.range),
        "message" => diag.message
      }

      base
      |> maybe_put("severity", diag.severity)
      |> maybe_put("code", diag.code)
      |> maybe_put("source", diag.source)
      |> maybe_put("relatedInformation", diag.related_information)
    end

    defp maybe_put(map, _key, nil), do: map
    defp maybe_put(map, key, value), do: Map.put(map, key, value)
  end

  # ============================================================================
  # Hover Type
  # ============================================================================

  defmodule Hover do
    @moduledoc """
    Represents hover information returned by the server.

    ## Fields

      * `:contents` - The hover contents (markdown or plain text)
      * `:range` - Optional range the hover applies to
    """

    alias JidoCode.Tools.LSP.Protocol.Range

    @enforce_keys [:contents]
    defstruct [:contents, :range]

    @type content :: String.t() | %{kind: String.t(), value: String.t()}
    @type t :: %__MODULE__{
            contents: content() | [content()],
            range: Range.t() | nil
          }

    @doc "Creates a new Hover."
    @spec new(content() | [content()], Range.t() | nil) :: t()
    def new(contents, range \\ nil) do
      %__MODULE__{contents: contents, range: range}
    end

    @doc "Extracts plain text content from hover."
    @spec to_text(t()) :: String.t()
    def to_text(%__MODULE__{contents: contents}) do
      extract_text(contents)
    end

    defp extract_text(contents) when is_binary(contents), do: contents

    defp extract_text(%{"value" => value}) when is_binary(value), do: value
    defp extract_text(%{"kind" => _, "value" => value}) when is_binary(value), do: value

    defp extract_text(contents) when is_list(contents) do
      contents
      |> Enum.map(&extract_text/1)
      |> Enum.join("\n\n")
    end

    defp extract_text(_), do: ""

    @doc "Parses a Hover from LSP JSON format."
    @spec from_lsp(map()) :: {:ok, t()} | {:error, :invalid_hover}
    def from_lsp(%{"contents" => contents} = lsp) do
      range =
        case Map.get(lsp, "range") do
          nil -> nil
          range_map -> elem(Range.from_lsp(range_map), 1)
        end

      {:ok, %__MODULE__{contents: contents, range: range}}
    end

    def from_lsp(_), do: {:error, :invalid_hover}

    @doc "Converts a Hover to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{contents: contents, range: nil}) do
      %{"contents" => contents}
    end

    def to_lsp(%__MODULE__{contents: contents, range: range}) do
      %{"contents" => contents, "range" => Range.to_lsp(range)}
    end
  end

  # ============================================================================
  # ReferenceParams Type
  # ============================================================================

  defmodule ReferenceParams do
    @moduledoc """
    Parameters for textDocument/references request.

    Extends TextDocumentPositionParams with reference context.

    ## Fields

      * `:text_document` - The document identifier
      * `:position` - The position within the document
      * `:context` - Reference context (include_declaration)
    """

    alias JidoCode.Tools.LSP.Protocol.{Position, TextDocumentIdentifier}

    @enforce_keys [:text_document, :position, :context]
    defstruct [:text_document, :position, :context]

    @type context :: %{include_declaration: boolean()}
    @type t :: %__MODULE__{
            text_document: TextDocumentIdentifier.t(),
            position: Position.t(),
            context: context()
          }

    @doc "Creates new ReferenceParams."
    @spec new(TextDocumentIdentifier.t(), Position.t(), boolean()) :: t()
    def new(%TextDocumentIdentifier{} = text_document, %Position{} = position, include_declaration \\ false)
        when is_boolean(include_declaration) do
      %__MODULE__{
        text_document: text_document,
        position: position,
        context: %{include_declaration: include_declaration}
      }
    end

    @doc "Creates params from file path and 1-indexed editor position."
    @spec from_editor(String.t(), pos_integer(), pos_integer(), boolean()) :: t()
    def from_editor(path, line, character, include_declaration \\ false)
        when is_binary(path) and is_integer(line) and is_integer(character) do
      new(
        TextDocumentIdentifier.from_path(path),
        Position.from_editor(line, character),
        include_declaration
      )
    end

    @doc "Converts to LSP JSON format."
    @spec to_lsp(t()) :: map()
    def to_lsp(%__MODULE__{text_document: doc, position: pos, context: ctx}) do
      %{
        "textDocument" => TextDocumentIdentifier.to_lsp(doc),
        "position" => Position.to_lsp(pos),
        "context" => %{"includeDeclaration" => ctx.include_declaration}
      }
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Builds LSP parameters for a hover request.

  ## Parameters

    * `path` - File path (will be converted to file:// URI)
    * `line` - 1-indexed line number
    * `character` - 1-indexed character offset

  ## Returns

  A map ready to be sent as LSP request params.
  """
  @spec hover_params(String.t(), pos_integer(), pos_integer()) :: map()
  def hover_params(path, line, character) do
    TextDocumentPositionParams.from_editor(path, line, character)
    |> TextDocumentPositionParams.to_lsp()
  end

  @doc """
  Builds LSP parameters for a definition request.
  """
  @spec definition_params(String.t(), pos_integer(), pos_integer()) :: map()
  def definition_params(path, line, character) do
    TextDocumentPositionParams.from_editor(path, line, character)
    |> TextDocumentPositionParams.to_lsp()
  end

  @doc """
  Builds LSP parameters for a references request.
  """
  @spec references_params(String.t(), pos_integer(), pos_integer(), boolean()) :: map()
  def references_params(path, line, character, include_declaration \\ false) do
    ReferenceParams.from_editor(path, line, character, include_declaration)
    |> ReferenceParams.to_lsp()
  end

  @doc """
  Parses a list of locations from an LSP response.

  Handles both single location and array of locations.
  """
  @spec parse_locations(map() | [map()] | nil) :: [Location.t()]
  def parse_locations(nil), do: []
  def parse_locations([]), do: []

  def parse_locations(locations) when is_list(locations) do
    locations
    |> Enum.map(&Location.from_lsp/1)
    |> Enum.filter(&match?({:ok, _}, &1))
    |> Enum.map(fn {:ok, loc} -> loc end)
  end

  def parse_locations(%{} = location) do
    case Location.from_lsp(location) do
      {:ok, loc} -> [loc]
      _ -> []
    end
  end
end
