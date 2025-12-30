# Task 3.6.2 LSP Protocol Types

**Status**: Complete
**Branch**: `feature/3.6.2-lsp-protocol-types`
**Planning Reference**: `notes/planning/tooling/phase-03-tools.md` Section 3.6.2

## Summary

This task implements typed structs and helper functions for LSP (Language Server Protocol) messages. These types provide a clean interface between the Expert LSP client and the existing LSP handlers.

## Implementation

### New Files

| File | Purpose |
|------|---------|
| `lib/jido_code/tools/lsp/protocol.ex` | LSP type definitions and helpers |
| `test/jido_code/tools/lsp/protocol_test.exs` | Unit tests (73 tests) |

### Types Defined

| Type | Purpose |
|------|---------|
| `Position` | 0-indexed line/character position |
| `Range` | Start and end positions |
| `Location` | URI + Range (for definition/reference results) |
| `TextDocumentIdentifier` | Document URI wrapper |
| `TextDocumentPositionParams` | Document + position for requests |
| `Diagnostic` | Error/warning with range, severity, message |
| `Hover` | Hover content with optional range |
| `ReferenceParams` | References request with include_declaration |

### LSP Method Constants

```elixir
Protocol.method_hover()              # "textDocument/hover"
Protocol.method_definition()         # "textDocument/definition"
Protocol.method_references()         # "textDocument/references"
Protocol.method_publish_diagnostics()# "textDocument/publishDiagnostics"
Protocol.method_did_open()           # "textDocument/didOpen"
Protocol.method_did_close()          # "textDocument/didClose"
Protocol.method_did_change()         # "textDocument/didChange"
Protocol.method_did_save()           # "textDocument/didSave"
Protocol.method_completion()         # "textDocument/completion"
Protocol.method_signature_help()     # "textDocument/signatureHelp"
Protocol.method_document_symbol()    # "textDocument/documentSymbol"
Protocol.method_workspace_symbol()   # "workspace/symbol"
```

### Key Features

#### 1. Position Indexing Conversion
LSP uses 0-indexed positions, editors display 1-indexed. The `Position` type handles this:

```elixir
# From editor (1-indexed) to LSP (0-indexed)
pos = Position.from_editor(10, 5)  # line=9, char=4

# From LSP (0-indexed) to editor (1-indexed)
{line, char} = Position.to_editor(pos)  # {10, 5}
```

#### 2. LSP JSON Serialization
All types support bidirectional conversion:

```elixir
# To LSP JSON format
Position.to_lsp(pos)     # %{"line" => 9, "character" => 4}
Range.to_lsp(range)      # %{"start" => ..., "end" => ...}
Location.to_lsp(loc)     # %{"uri" => "file://...", "range" => ...}

# From LSP JSON format
{:ok, pos} = Position.from_lsp(%{"line" => 9, "character" => 4})
{:ok, range} = Range.from_lsp(range_map)
{:ok, loc} = Location.from_lsp(location_map)
```

#### 3. Helper Functions for Handlers
Convenience functions for building LSP request params:

```elixir
# Build hover request params (1-indexed input → 0-indexed output)
Protocol.hover_params("/path/to/file.ex", 10, 5)
# => %{"textDocument" => %{"uri" => "file://..."}, "position" => %{"line" => 9, ...}}

# Build definition request params
Protocol.definition_params("/path/to/file.ex", 10, 5)

# Build references request params
Protocol.references_params("/path/to/file.ex", 10, 5, include_declaration: true)

# Parse locations from response
Protocol.parse_locations(lsp_response)
# => [%Location{}, ...]
```

#### 4. Diagnostic Severity Constants
```elixir
Diagnostic.severity_error()   # 1
Diagnostic.severity_warning() # 2
Diagnostic.severity_info()    # 3
Diagnostic.severity_hint()    # 4

Diagnostic.severity_to_atom(1)    # :error
Diagnostic.severity_from_atom(:warning)  # 2
```

## Test Coverage

| Category | Tests | Status |
|----------|-------|--------|
| LSP method constants | 12 | Pass |
| Position | 8 | Pass |
| Range | 5 | Pass |
| Location | 9 | Pass |
| TextDocumentIdentifier | 5 | Pass |
| TextDocumentPositionParams | 3 | Pass |
| Diagnostic | 10 | Pass |
| Hover | 9 | Pass |
| ReferenceParams | 4 | Pass |
| Helper functions | 8 | Pass |
| **Total** | **73** | **All Pass** |

## Architecture Notes

### Module Structure

```
JidoCode.Tools.LSP.Protocol
├── method_* functions (constants)
├── Position (nested module)
├── Range (nested module)
├── Location (nested module)
├── TextDocumentIdentifier (nested module)
├── TextDocumentPositionParams (nested module)
├── Diagnostic (nested module)
├── Hover (nested module)
├── ReferenceParams (nested module)
└── Helper functions (hover_params, definition_params, etc.)
```

### Integration with Client

The protocol types are designed to work with the Expert client from 3.6.1:

```elixir
# Handler builds params using protocol types
params = Protocol.hover_params(path, line, character)

# Client sends request
{:ok, response} = Client.request(client, Protocol.method_hover(), params)

# Parse response using protocol types
{:ok, hover} = Hover.from_lsp(response)
text = Hover.to_text(hover)
```

## Next Steps

Section 3.6.3 (Handler Integration) will:
- Update GetHoverInfo, GoToDefinition, FindReferences to use these types
- Connect handlers to the Expert client
- Use protocol types for request/response handling

## Reference

- LSP Specification: https://microsoft.github.io/language-server-protocol/
- Expert: https://github.com/elixir-lang/expert
