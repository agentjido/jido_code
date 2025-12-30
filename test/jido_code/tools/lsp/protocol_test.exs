defmodule JidoCode.Tools.LSP.ProtocolTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.LSP.Protocol
  alias Protocol.{Position, Range, Location, TextDocumentIdentifier}
  alias Protocol.{TextDocumentPositionParams, Diagnostic, Hover, ReferenceParams}

  # ============================================================================
  # LSP Method Constants Tests
  # ============================================================================

  describe "LSP method constants" do
    test "hover method" do
      assert Protocol.method_hover() == "textDocument/hover"
    end

    test "definition method" do
      assert Protocol.method_definition() == "textDocument/definition"
    end

    test "references method" do
      assert Protocol.method_references() == "textDocument/references"
    end

    test "publishDiagnostics method" do
      assert Protocol.method_publish_diagnostics() == "textDocument/publishDiagnostics"
    end

    test "didOpen method" do
      assert Protocol.method_did_open() == "textDocument/didOpen"
    end

    test "didClose method" do
      assert Protocol.method_did_close() == "textDocument/didClose"
    end

    test "didChange method" do
      assert Protocol.method_did_change() == "textDocument/didChange"
    end

    test "didSave method" do
      assert Protocol.method_did_save() == "textDocument/didSave"
    end

    test "completion method" do
      assert Protocol.method_completion() == "textDocument/completion"
    end

    test "signatureHelp method" do
      assert Protocol.method_signature_help() == "textDocument/signatureHelp"
    end

    test "documentSymbol method" do
      assert Protocol.method_document_symbol() == "textDocument/documentSymbol"
    end

    test "workspaceSymbol method" do
      assert Protocol.method_workspace_symbol() == "workspace/symbol"
    end
  end

  # ============================================================================
  # Position Tests
  # ============================================================================

  describe "Position" do
    test "new/2 creates 0-indexed position" do
      pos = Position.new(10, 5)
      assert pos.line == 10
      assert pos.character == 5
    end

    test "new/2 clamps negative values to 0" do
      pos = Position.new(-1, -5)
      assert pos.line == 0
      assert pos.character == 0
    end

    test "from_editor/2 converts 1-indexed to 0-indexed" do
      pos = Position.from_editor(11, 6)
      assert pos.line == 10
      assert pos.character == 5
    end

    test "to_editor/1 converts 0-indexed to 1-indexed" do
      pos = Position.new(10, 5)
      assert Position.to_editor(pos) == {11, 6}
    end

    test "to_lsp/1 converts to LSP JSON format" do
      pos = Position.new(10, 5)
      assert Position.to_lsp(pos) == %{"line" => 10, "character" => 5}
    end

    test "from_lsp/1 parses LSP JSON format" do
      assert {:ok, pos} = Position.from_lsp(%{"line" => 10, "character" => 5})
      assert pos.line == 10
      assert pos.character == 5
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_position} = Position.from_lsp(%{})
      assert {:error, :invalid_position} = Position.from_lsp(%{"line" => "10"})
      assert {:error, :invalid_position} = Position.from_lsp(nil)
    end

    test "roundtrip: editor -> LSP -> editor" do
      pos = Position.from_editor(15, 20)
      lsp = Position.to_lsp(pos)
      {:ok, parsed} = Position.from_lsp(lsp)
      assert Position.to_editor(parsed) == {15, 20}
    end
  end

  # ============================================================================
  # Range Tests
  # ============================================================================

  describe "Range" do
    test "new/2 creates range from positions" do
      start_pos = Position.new(10, 0)
      end_pos = Position.new(10, 15)
      range = Range.new(start_pos, end_pos)

      assert range.start == start_pos
      assert range.end == end_pos
    end

    test "from_editor/2 creates range from 1-indexed tuples" do
      range = Range.from_editor({11, 1}, {11, 16})
      assert range.start.line == 10
      assert range.start.character == 0
      assert range.end.line == 10
      assert range.end.character == 15
    end

    test "to_lsp/1 converts to LSP JSON format" do
      range = Range.from_editor({1, 1}, {1, 10})
      lsp = Range.to_lsp(range)

      assert lsp == %{
               "start" => %{"line" => 0, "character" => 0},
               "end" => %{"line" => 0, "character" => 9}
             }
    end

    test "from_lsp/1 parses LSP JSON format" do
      lsp = %{
        "start" => %{"line" => 5, "character" => 10},
        "end" => %{"line" => 5, "character" => 20}
      }

      assert {:ok, range} = Range.from_lsp(lsp)
      assert range.start.line == 5
      assert range.start.character == 10
      assert range.end.line == 5
      assert range.end.character == 20
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_range} = Range.from_lsp(%{})
      assert {:error, :invalid_range} = Range.from_lsp(%{"start" => %{}})
      assert {:error, :invalid_range} = Range.from_lsp(nil)
    end
  end

  # ============================================================================
  # Location Tests
  # ============================================================================

  describe "Location" do
    test "new/2 creates location" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.new("file:///path/to/file.ex", range)

      assert loc.uri == "file:///path/to/file.ex"
      assert loc.range == range
    end

    test "from_path/2 creates location from path" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.from_path("/path/to/file.ex", range)

      assert loc.uri == "file:///path/to/file.ex"
    end

    test "path/1 extracts file path from URI" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.new("file:///path/to/file.ex", range)

      assert {:ok, "/path/to/file.ex"} = Location.path(loc)
    end

    test "path/1 handles URL-encoded paths" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.new("file:///path/to/my%20file.ex", range)

      assert {:ok, "/path/to/my file.ex"} = Location.path(loc)
    end

    test "path/1 returns error for non-file URIs" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.new("https://example.com/file.ex", range)

      assert {:error, :invalid_uri} = Location.path(loc)
    end

    test "to_lsp/1 converts to LSP JSON format" do
      range = Range.from_editor({1, 1}, {1, 10})
      loc = Location.from_path("/path/to/file.ex", range)
      lsp = Location.to_lsp(loc)

      assert lsp["uri"] == "file:///path/to/file.ex"
      assert is_map(lsp["range"])
    end

    test "from_lsp/1 parses LSP JSON format" do
      lsp = %{
        "uri" => "file:///path/to/file.ex",
        "range" => %{
          "start" => %{"line" => 0, "character" => 0},
          "end" => %{"line" => 0, "character" => 10}
        }
      }

      assert {:ok, loc} = Location.from_lsp(lsp)
      assert loc.uri == "file:///path/to/file.ex"
      assert loc.range.start.line == 0
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_location} = Location.from_lsp(%{})
      assert {:error, :invalid_location} = Location.from_lsp(%{"uri" => 123})
      assert {:error, :invalid_location} = Location.from_lsp(nil)
    end
  end

  # ============================================================================
  # TextDocumentIdentifier Tests
  # ============================================================================

  describe "TextDocumentIdentifier" do
    test "new/1 creates identifier" do
      id = TextDocumentIdentifier.new("file:///path/to/file.ex")
      assert id.uri == "file:///path/to/file.ex"
    end

    test "from_path/1 creates identifier from path" do
      id = TextDocumentIdentifier.from_path("/path/to/file.ex")
      assert id.uri == "file:///path/to/file.ex"
    end

    test "to_lsp/1 converts to LSP JSON format" do
      id = TextDocumentIdentifier.from_path("/path/to/file.ex")
      assert TextDocumentIdentifier.to_lsp(id) == %{"uri" => "file:///path/to/file.ex"}
    end

    test "from_lsp/1 parses LSP JSON format" do
      assert {:ok, id} = TextDocumentIdentifier.from_lsp(%{"uri" => "file:///test.ex"})
      assert id.uri == "file:///test.ex"
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_text_document_identifier} = TextDocumentIdentifier.from_lsp(%{})
      assert {:error, :invalid_text_document_identifier} = TextDocumentIdentifier.from_lsp(nil)
    end
  end

  # ============================================================================
  # TextDocumentPositionParams Tests
  # ============================================================================

  describe "TextDocumentPositionParams" do
    test "new/2 creates params" do
      doc = TextDocumentIdentifier.from_path("/test.ex")
      pos = Position.new(5, 10)
      params = TextDocumentPositionParams.new(doc, pos)

      assert params.text_document == doc
      assert params.position == pos
    end

    test "from_editor/3 creates params from editor values" do
      params = TextDocumentPositionParams.from_editor("/test.ex", 10, 5)

      assert params.text_document.uri == "file:///test.ex"
      assert params.position.line == 9
      assert params.position.character == 4
    end

    test "to_lsp/1 converts to LSP JSON format" do
      params = TextDocumentPositionParams.from_editor("/test.ex", 10, 5)
      lsp = TextDocumentPositionParams.to_lsp(params)

      assert lsp == %{
               "textDocument" => %{"uri" => "file:///test.ex"},
               "position" => %{"line" => 9, "character" => 4}
             }
    end
  end

  # ============================================================================
  # Diagnostic Tests
  # ============================================================================

  describe "Diagnostic" do
    test "new/2 creates diagnostic with required fields" do
      range = Range.from_editor({1, 1}, {1, 10})
      diag = Diagnostic.new(range, "Something went wrong")

      assert diag.range == range
      assert diag.message == "Something went wrong"
      assert diag.severity == nil
    end

    test "new/3 creates diagnostic with options" do
      range = Range.from_editor({1, 1}, {1, 10})

      diag =
        Diagnostic.new(range, "Error message",
          severity: 1,
          code: "E001",
          source: "elixir"
        )

      assert diag.severity == 1
      assert diag.code == "E001"
      assert diag.source == "elixir"
    end

    test "severity constants" do
      assert Diagnostic.severity_error() == 1
      assert Diagnostic.severity_warning() == 2
      assert Diagnostic.severity_info() == 3
      assert Diagnostic.severity_hint() == 4
    end

    test "severity_to_atom/1 converts integer to atom" do
      assert Diagnostic.severity_to_atom(1) == :error
      assert Diagnostic.severity_to_atom(2) == :warning
      assert Diagnostic.severity_to_atom(3) == :info
      assert Diagnostic.severity_to_atom(4) == :hint
      assert Diagnostic.severity_to_atom(nil) == nil
    end

    test "severity_from_atom/1 converts atom to integer" do
      assert Diagnostic.severity_from_atom(:error) == 1
      assert Diagnostic.severity_from_atom(:warning) == 2
      assert Diagnostic.severity_from_atom(:info) == 3
      assert Diagnostic.severity_from_atom(:hint) == 4
    end

    test "from_lsp/1 parses LSP JSON format" do
      lsp = %{
        "range" => %{
          "start" => %{"line" => 5, "character" => 0},
          "end" => %{"line" => 5, "character" => 10}
        },
        "message" => "Undefined function",
        "severity" => 1,
        "source" => "elixir"
      }

      assert {:ok, diag} = Diagnostic.from_lsp(lsp)
      assert diag.message == "Undefined function"
      assert diag.severity == 1
      assert diag.source == "elixir"
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_diagnostic} = Diagnostic.from_lsp(%{})
      assert {:error, :invalid_diagnostic} = Diagnostic.from_lsp(%{"message" => "test"})
    end

    test "to_lsp/1 converts to LSP JSON format" do
      range = Range.from_editor({1, 1}, {1, 10})
      diag = Diagnostic.new(range, "Error", severity: 1, source: "test")
      lsp = Diagnostic.to_lsp(diag)

      assert lsp["message"] == "Error"
      assert lsp["severity"] == 1
      assert lsp["source"] == "test"
      assert is_map(lsp["range"])
    end

    test "to_lsp/1 omits nil optional fields" do
      range = Range.from_editor({1, 1}, {1, 10})
      diag = Diagnostic.new(range, "Error")
      lsp = Diagnostic.to_lsp(diag)

      refute Map.has_key?(lsp, "severity")
      refute Map.has_key?(lsp, "code")
      refute Map.has_key?(lsp, "source")
    end
  end

  # ============================================================================
  # Hover Tests
  # ============================================================================

  describe "Hover" do
    test "new/1 creates hover with string content" do
      hover = Hover.new("Hello, world!")
      assert hover.contents == "Hello, world!"
      assert hover.range == nil
    end

    test "new/2 creates hover with range" do
      range = Range.from_editor({1, 1}, {1, 10})
      hover = Hover.new("Hello", range)
      assert hover.range == range
    end

    test "to_text/1 extracts text from string content" do
      hover = Hover.new("Simple text")
      assert Hover.to_text(hover) == "Simple text"
    end

    test "to_text/1 extracts text from MarkupContent" do
      hover = Hover.new(%{"kind" => "markdown", "value" => "# Header"})
      assert Hover.to_text(hover) == "# Header"
    end

    test "to_text/1 extracts text from array content" do
      hover = Hover.new(["First", %{"value" => "Second"}])
      assert Hover.to_text(hover) == "First\n\nSecond"
    end

    test "from_lsp/1 parses LSP JSON format" do
      lsp = %{
        "contents" => %{"kind" => "markdown", "value" => "# Docs"},
        "range" => %{
          "start" => %{"line" => 0, "character" => 0},
          "end" => %{"line" => 0, "character" => 5}
        }
      }

      assert {:ok, hover} = Hover.from_lsp(lsp)
      assert hover.contents == %{"kind" => "markdown", "value" => "# Docs"}
      assert hover.range != nil
    end

    test "from_lsp/1 parses hover without range" do
      assert {:ok, hover} = Hover.from_lsp(%{"contents" => "text"})
      assert hover.contents == "text"
      assert hover.range == nil
    end

    test "from_lsp/1 returns error for invalid format" do
      assert {:error, :invalid_hover} = Hover.from_lsp(%{})
      assert {:error, :invalid_hover} = Hover.from_lsp(nil)
    end

    test "to_lsp/1 converts to LSP JSON format" do
      hover = Hover.new("content")
      assert Hover.to_lsp(hover) == %{"contents" => "content"}
    end

    test "to_lsp/1 includes range when present" do
      range = Range.from_editor({1, 1}, {1, 10})
      hover = Hover.new("content", range)
      lsp = Hover.to_lsp(hover)

      assert Map.has_key?(lsp, "range")
    end
  end

  # ============================================================================
  # ReferenceParams Tests
  # ============================================================================

  describe "ReferenceParams" do
    test "new/3 creates params with include_declaration false by default" do
      doc = TextDocumentIdentifier.from_path("/test.ex")
      pos = Position.new(5, 10)
      params = ReferenceParams.new(doc, pos)

      assert params.context.include_declaration == false
    end

    test "new/3 creates params with include_declaration true" do
      doc = TextDocumentIdentifier.from_path("/test.ex")
      pos = Position.new(5, 10)
      params = ReferenceParams.new(doc, pos, true)

      assert params.context.include_declaration == true
    end

    test "from_editor/4 creates params from editor values" do
      params = ReferenceParams.from_editor("/test.ex", 10, 5, true)

      assert params.text_document.uri == "file:///test.ex"
      assert params.position.line == 9
      assert params.position.character == 4
      assert params.context.include_declaration == true
    end

    test "to_lsp/1 converts to LSP JSON format" do
      params = ReferenceParams.from_editor("/test.ex", 10, 5, true)
      lsp = ReferenceParams.to_lsp(params)

      assert lsp == %{
               "textDocument" => %{"uri" => "file:///test.ex"},
               "position" => %{"line" => 9, "character" => 4},
               "context" => %{"includeDeclaration" => true}
             }
    end
  end

  # ============================================================================
  # Helper Function Tests
  # ============================================================================

  describe "hover_params/3" do
    test "builds LSP hover request params" do
      params = Protocol.hover_params("/path/to/file.ex", 10, 5)

      assert params == %{
               "textDocument" => %{"uri" => "file:///path/to/file.ex"},
               "position" => %{"line" => 9, "character" => 4}
             }
    end
  end

  describe "definition_params/3" do
    test "builds LSP definition request params" do
      params = Protocol.definition_params("/path/to/file.ex", 10, 5)

      assert params == %{
               "textDocument" => %{"uri" => "file:///path/to/file.ex"},
               "position" => %{"line" => 9, "character" => 4}
             }
    end
  end

  describe "references_params/4" do
    test "builds LSP references request params" do
      params = Protocol.references_params("/path/to/file.ex", 10, 5, true)

      assert params == %{
               "textDocument" => %{"uri" => "file:///path/to/file.ex"},
               "position" => %{"line" => 9, "character" => 4},
               "context" => %{"includeDeclaration" => true}
             }
    end

    test "defaults include_declaration to false" do
      params = Protocol.references_params("/path/to/file.ex", 10, 5)
      assert params["context"]["includeDeclaration"] == false
    end
  end

  describe "parse_locations/1" do
    test "parses nil as empty list" do
      assert Protocol.parse_locations(nil) == []
    end

    test "parses empty list" do
      assert Protocol.parse_locations([]) == []
    end

    test "parses single location map" do
      loc = %{
        "uri" => "file:///test.ex",
        "range" => %{
          "start" => %{"line" => 0, "character" => 0},
          "end" => %{"line" => 0, "character" => 5}
        }
      }

      result = Protocol.parse_locations(loc)
      assert length(result) == 1
      assert hd(result).uri == "file:///test.ex"
    end

    test "parses list of locations" do
      locs = [
        %{
          "uri" => "file:///a.ex",
          "range" => %{
            "start" => %{"line" => 0, "character" => 0},
            "end" => %{"line" => 0, "character" => 5}
          }
        },
        %{
          "uri" => "file:///b.ex",
          "range" => %{
            "start" => %{"line" => 5, "character" => 0},
            "end" => %{"line" => 5, "character" => 10}
          }
        }
      ]

      result = Protocol.parse_locations(locs)
      assert length(result) == 2
    end

    test "filters out invalid locations" do
      locs = [
        %{
          "uri" => "file:///valid.ex",
          "range" => %{
            "start" => %{"line" => 0, "character" => 0},
            "end" => %{"line" => 0, "character" => 5}
          }
        },
        %{"invalid" => true},
        nil
      ]

      result = Protocol.parse_locations(locs)
      assert length(result) == 1
      assert hd(result).uri == "file:///valid.ex"
    end
  end
end
