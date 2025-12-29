defmodule JidoCode.Tools.Handlers.LSP do
  @moduledoc """
  Handler modules for LSP (Language Server Protocol) tools.

  This module contains handlers for code intelligence operations:
  - `GetHoverInfo` - Get type info and documentation at cursor position
  - `GoToDefinition` - Find where a symbol is defined

  ## Session Context

  Handlers use `HandlerHelpers.validate_path/2` for session-aware path validation:

  1. `session_id` present → Uses `Session.Manager.validate_path/2`
  2. `project_root` present → Uses `Security.validate_path/3`
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## LSP Server Requirement

  These handlers require an LSP server to be running (e.g., ElixirLS, Lexical).
  If no LSP server is available, handlers return appropriate error messages.

  ## Usage

  These handlers are invoked by the Executor when the LLM calls LSP tools:

      # Via Executor with session context
      {:ok, context} = Executor.build_context(session_id)
      Executor.execute(%{
        id: "call_123",
        name: "get_hover_info",
        arguments: %{"path" => "lib/my_app.ex", "line" => 10, "character" => 5}
      }, context: context)
  """

  require Logger

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Module Attributes (compile-time constants)
  # ============================================================================

  # Supported Elixir file extensions
  @elixir_extensions [".ex", ".exs"]

  # Regex patterns for detecting Elixir stdlib paths (compiled at module load time)
  @elixir_stdlib_patterns [
    ~r{/elixir/[^/]+/lib/elixir/},
    ~r{/lib/elixir/lib/},
    ~r{\.asdf/installs/elixir/},
    ~r{\.kiex/elixirs/},
    ~r{/elixir-[0-9]+\.[0-9]+},
    # mise (formerly rtx) installs
    ~r{\.local/share/mise/installs/elixir/},
    ~r{\.local/share/rtx/installs/elixir/},
    # Nix installations
    ~r{/nix/store/[^/]+-elixir-},
    # Homebrew on macOS
    ~r{/opt/homebrew/Cellar/elixir/},
    ~r{/usr/local/Cellar/elixir/}
  ]

  # Regex patterns for detecting Erlang/OTP paths (compiled at module load time)
  @erlang_otp_patterns [
    ~r{/erlang/[^/]+/lib/},
    ~r{/lib/erlang/lib/},
    ~r{\.asdf/installs/erlang/},
    ~r{/otp[_-]?[0-9]+},
    # mise (formerly rtx) installs
    ~r{\.local/share/mise/installs/erlang/},
    ~r{\.local/share/rtx/installs/erlang/},
    # Nix installations
    ~r{/nix/store/[^/]+-erlang-},
    # Docker/system paths
    ~r{/usr/local/lib/erlang/},
    # Homebrew on macOS
    ~r{/opt/homebrew/Cellar/erlang/},
    ~r{/usr/local/Cellar/erlang/}
  ]

  # Regex for extracting module name from stdlib paths
  @elixir_module_regex ~r{lib/([^/]+)\.ex$}
  @erlang_app_module_regex ~r{/([^/]+)/src/([^/]+)\.erl$}
  @erlang_module_regex ~r{/([^/]+)\.erl$}

  # ============================================================================
  # Shared Helpers (delegated)
  # ============================================================================

  @doc false
  @spec get_project_root(map()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_session_id | String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  @spec validate_path(String.t(), map()) :: {:ok, String.t()} | {:error, atom()}
  defdelegate validate_path(path, context), to: HandlerHelpers

  # ============================================================================
  # Shared Parameter Extraction (used by all LSP handlers)
  # ============================================================================

  @doc false
  @spec extract_path(map()) :: {:ok, String.t()} | {:error, String.t()}
  def extract_path(%{"path" => path}) when is_binary(path) and byte_size(path) > 0 do
    {:ok, path}
  end

  def extract_path(_), do: {:error, "path is required and must be a non-empty string"}

  @doc false
  @spec extract_line(map()) :: {:ok, pos_integer()} | {:error, String.t()}
  def extract_line(%{"line" => line}) when is_integer(line) and line >= 1 do
    {:ok, line}
  end

  def extract_line(%{"line" => line}) when is_binary(line) do
    case Integer.parse(line) do
      {n, ""} when n >= 1 -> {:ok, n}
      _ -> {:error, "line must be a positive integer (1-indexed)"}
    end
  end

  def extract_line(_), do: {:error, "line is required and must be a positive integer (1-indexed)"}

  @doc false
  @spec extract_character(map()) :: {:ok, pos_integer()} | {:error, String.t()}
  def extract_character(%{"character" => character})
      when is_integer(character) and character >= 1 do
    {:ok, character}
  end

  def extract_character(%{"character" => character}) when is_binary(character) do
    case Integer.parse(character) do
      {n, ""} when n >= 1 -> {:ok, n}
      _ -> {:error, "character must be a positive integer (1-indexed)"}
    end
  end

  def extract_character(_),
    do: {:error, "character is required and must be a positive integer (1-indexed)"}

  # ============================================================================
  # Shared File Validation
  # ============================================================================

  @doc false
  @spec validate_file_exists(String.t()) :: :ok | {:error, :enoent}
  def validate_file_exists(path) do
    if File.exists?(path), do: :ok, else: {:error, :enoent}
  end

  @doc false
  @spec elixir_file?(String.t()) :: boolean()
  def elixir_file?(path) do
    ext = path |> Path.extname() |> String.downcase()
    ext in @elixir_extensions
  end

  # ============================================================================
  # Error Formatting
  # ============================================================================

  @doc false
  @spec format_error(atom() | String.t(), String.t()) :: String.t()
  def format_error(:enoent, path), do: "File not found: #{path}"
  def format_error(:eacces, path), do: "Permission denied: #{path}"

  def format_error(:path_escapes_boundary, path),
    do: "Security error: path escapes project boundary: #{path}"

  def format_error(:path_outside_boundary, path),
    do: "Security error: path is outside project: #{path}"

  def format_error(:symlink_escapes_boundary, path),
    do: "Security error: symlink points outside project: #{path}"

  def format_error(:lsp_not_available, _path),
    do: "LSP server is not available. Ensure ElixirLS or another LSP server is running."

  def format_error(:lsp_timeout, path),
    do: "LSP request timed out for: #{path}"

  def format_error(:no_hover_info, path),
    do: "No hover information available at this position in: #{path}"

  def format_error(:definition_not_found, path),
    do: "No definition found at this position in: #{path}"

  def format_error(reason, path) when is_atom(reason), do: "Error (#{reason}): #{path}"
  def format_error(reason, _path) when is_binary(reason), do: reason
  def format_error(reason, path), do: "Error (#{inspect(reason)}): #{path}"

  # ============================================================================
  # Telemetry
  # ============================================================================

  @doc false
  @spec emit_lsp_telemetry(atom(), integer(), String.t(), map(), atom()) :: :ok
  def emit_lsp_telemetry(operation, start_time, path, context, status) do
    duration = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      [:jido_code, :lsp, operation],
      %{duration: duration},
      %{
        path: sanitize_path_for_telemetry(path),
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end

  defp sanitize_path_for_telemetry(path) when is_binary(path) do
    if String.length(path) > 100 do
      String.slice(path, 0, 97) <> "..."
    else
      path
    end
  end

  defp sanitize_path_for_telemetry(_), do: "<unknown>"

  # ============================================================================
  # Output Path Validation (Security)
  # ============================================================================

  @doc """
  Validates and sanitizes an output path from an LSP response.

  This function ensures that paths returned by the LSP server are safe to expose
  to the LLM agent. It applies the following rules:

  1. **Within project_root** - Returns relative path
  2. **In deps/ or _build/** - Returns relative path (read-only access allowed)
  3. **In stdlib/OTP** - Returns sanitized indicator (e.g., "elixir:File")
  4. **Outside all boundaries** - Returns error without revealing actual path

  ## Parameters

  - `path` - The absolute path returned by the LSP server
  - `context` - Execution context with project_root

  ## Returns

  - `{:ok, sanitized_path}` - Safe path to return to LLM
  - `{:error, :external_path}` - Path is outside allowed boundaries

  ## Examples

      iex> validate_output_path("/project/lib/foo.ex", %{project_root: "/project"})
      {:ok, "lib/foo.ex"}

      iex> validate_output_path("/project/deps/jason/lib/jason.ex", %{project_root: "/project"})
      {:ok, "deps/jason/lib/jason.ex"}

      iex> validate_output_path("/usr/lib/elixir/lib/elixir/lib/file.ex", %{project_root: "/project"})
      {:ok, "elixir:File"}

      iex> validate_output_path("/home/user/secret.ex", %{project_root: "/project"})
      {:error, :external_path}
  """
  @spec validate_output_path(String.t(), map()) :: {:ok, String.t()} | {:error, :external_path}
  def validate_output_path(path, context) when is_binary(path) do
    with {:ok, project_root} <- get_project_root(context) do
      cond do
        # Check if path is within project (including deps/ and _build/)
        path_within_project?(path, project_root) ->
          {:ok, Path.relative_to(path, project_root)}

        # Check if path is in Elixir stdlib
        elixir_stdlib_path?(path) ->
          {:ok, sanitize_stdlib_path(path, :elixir)}

        # Check if path is in Erlang/OTP
        erlang_otp_path?(path) ->
          {:ok, sanitize_stdlib_path(path, :erlang)}

        # Path is outside all allowed boundaries
        true ->
          Logger.warning("LSP returned external path (not exposed)",
            path_hash: hash_path_for_logging(path)
          )

          {:error, :external_path}
      end
    else
      {:error, _reason} ->
        # Without project_root, we can't validate - treat as external
        {:error, :external_path}
    end
  end

  def validate_output_path(nil, _context), do: {:error, :external_path}

  @doc """
  Validates multiple output paths from an LSP response (for multiple definitions).

  Filters out any paths that fail validation and returns only safe paths.
  If all paths are filtered out, returns an empty list (not an error).
  """
  @spec validate_output_paths([String.t()], map()) :: {:ok, [String.t()]}
  def validate_output_paths(paths, context) when is_list(paths) do
    validated =
      for path <- paths,
          {:ok, safe_path} <- [validate_output_path(path, context)] do
        safe_path
      end

    {:ok, validated}
  end

  # Check if path is within project directory
  defp path_within_project?(path, project_root) do
    # Normalize both paths for comparison
    normalized_path = Path.expand(path)
    normalized_root = Path.expand(project_root)

    String.starts_with?(normalized_path, normalized_root <> "/") or
      normalized_path == normalized_root
  end

  # Check if path is in Elixir stdlib (uses module attribute patterns)
  defp elixir_stdlib_path?(path) do
    Enum.any?(@elixir_stdlib_patterns, &Regex.match?(&1, path))
  end

  # Check if path is in Erlang/OTP (uses module attribute patterns)
  defp erlang_otp_path?(path) do
    Enum.any?(@erlang_otp_patterns, &Regex.match?(&1, path))
  end

  # Sanitize stdlib path to a safe indicator
  # e.g., "/usr/lib/elixir/lib/elixir/lib/file.ex" -> "elixir:File"
  defp sanitize_stdlib_path(path, :elixir) do
    case Regex.run(@elixir_module_regex, path) do
      [_, module_name] ->
        # Convert file name to module name (e.g., "file" -> "File")
        module = Macro.camelize(module_name)
        "elixir:#{module}"

      nil ->
        # Fallback for non-standard paths
        "elixir:stdlib"
    end
  end

  defp sanitize_stdlib_path(path, :erlang) do
    case Regex.run(@erlang_app_module_regex, path) do
      [_, _app, module_name] ->
        "erlang:#{module_name}"

      nil ->
        case Regex.run(@erlang_module_regex, path) do
          [_, module_name] -> "erlang:#{module_name}"
          nil -> "erlang:otp"
        end
    end
  end

  # Hash path for secure logging (doesn't reveal path structure)
  defp hash_path_for_logging(path) when is_binary(path) do
    ext = Path.extname(path)
    hash = :erlang.phash2(path, 100_000)
    "external:#{hash}#{ext}"
  end

  defp hash_path_for_logging(_), do: "external:unknown"

  # ============================================================================
  # URI Handling
  # ============================================================================

  @doc """
  Converts a file:// URI to a filesystem path.

  Handles case-insensitive matching for the file:// scheme and URL decoding.
  """
  @spec uri_to_path(String.t()) :: String.t()
  def uri_to_path(uri) when is_binary(uri) do
    # Case-insensitive check for file:// prefix
    if String.downcase(String.slice(uri, 0, 7)) == "file://" do
      uri
      |> String.slice(7..-1//1)
      |> URI.decode()
    else
      uri
    end
  end

  def uri_to_path(uri), do: to_string(uri)
end

defmodule JidoCode.Tools.Handlers.LSP.GetHoverInfo do
  @moduledoc """
  Handler for the get_hover_info tool.

  Gets type information and documentation at a specific cursor position
  in a file using the Language Server Protocol (LSP).

  ## Parameters

  - `path` (required) - File path to query
  - `line` (required) - Line number (1-indexed)
  - `character` (required) - Character offset (1-indexed)

  ## Returns

  - `{:ok, result}` - Map with hover information (type, docs, module)
  - `{:error, reason}` - Error message string

  ## LSP Integration

  This handler is designed to integrate with an LSP client (e.g., ElixirLS, Lexical).
  Until the LSP client infrastructure is implemented (Phase 3.6), this handler
  returns a placeholder response indicating LSP is not yet configured.
  """

  require Logger

  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers

  @doc """
  Executes the get_hover_info operation.

  ## Arguments

  - `params` - Map with "path", "line", and "character" keys
  - `context` - Execution context with session_id or project_root

  ## Returns

  - `{:ok, result}` on success with hover information
  - `{:error, reason}` on failure
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(params, context) do
    start_time = System.monotonic_time(:microsecond)

    with {:ok, path} <- LSPHandlers.extract_path(params),
         {:ok, line} <- LSPHandlers.extract_line(params),
         {:ok, character} <- LSPHandlers.extract_character(params),
         {:ok, safe_path} <- LSPHandlers.validate_path(path, context),
         :ok <- LSPHandlers.validate_file_exists(safe_path) do
      result = get_hover_info(safe_path, line, character, context)
      LSPHandlers.emit_lsp_telemetry(:get_hover_info, start_time, path, context, :success)
      result
    else
      {:error, reason} ->
        path = Map.get(params, "path", "<unknown>")
        LSPHandlers.emit_lsp_telemetry(:get_hover_info, start_time, path, context, :error)
        {:error, LSPHandlers.format_error(reason, path)}
    end
  end

  # ============================================================================
  # LSP Integration
  # ============================================================================

  # Get hover information from LSP server
  # Currently returns a placeholder until LSP client infrastructure is implemented
  defp get_hover_info(path, line, character, _context) do
    # TODO: Integrate with LSP client once Phase 3.6 is implemented
    # For now, check if the file is an Elixir file and return helpful info
    if LSPHandlers.elixir_file?(path) do
      Logger.debug(
        "LSP get_hover_info requested for #{path}:#{line}:#{character} - LSP client not yet implemented"
      )

      # Return a structured response indicating LSP is not yet available
      {:ok,
       %{
         "status" => "lsp_not_configured",
         "message" =>
           "LSP integration is not yet configured. " <>
             "Hover info will be available once an LSP server (ElixirLS, Lexical) is connected.",
         "position" => %{
           "path" => path,
           "line" => line,
           "character" => character
         },
         "hint" =>
           "To enable LSP features, ensure you have ElixirLS or Lexical running " <>
             "and the LSP client is configured in Phase 3.6."
       }}
    else
      {:ok,
       %{
         "status" => "unsupported_file_type",
         "message" => "Hover info is only available for Elixir files (.ex, .exs)",
         "path" => path
       }}
    end
  end
end

defmodule JidoCode.Tools.Handlers.LSP.GoToDefinition do
  @moduledoc """
  Handler for the go_to_definition tool.

  Finds where a symbol is defined using the Language Server Protocol (LSP).
  Returns the file path and position of the definition.

  ## Parameters

  - `path` (required) - File path to query
  - `line` (required) - Line number (1-indexed)
  - `character` (required) - Character offset (1-indexed)

  ## Returns

  - `{:ok, result}` - Map with definition location(s)
  - `{:error, reason}` - Error message string

  ## Response Format

  When LSP is configured, returns one of:

  ### Single Definition
  ```elixir
  %{
    "status" => "found",
    "definition" => %{
      "path" => "lib/my_module.ex",
      "line" => 15,
      "character" => 3
    }
  }
  ```

  ### Multiple Definitions (e.g., protocol implementations)
  ```elixir
  %{
    "status" => "found",
    "definitions" => [
      %{"path" => "lib/impl_a.ex", "line" => 10, "character" => 3},
      %{"path" => "lib/impl_b.ex", "line" => 20, "character" => 3}
    ]
  }
  ```

  ### Stdlib Definition
  ```elixir
  %{
    "status" => "found",
    "definition" => %{
      "path" => "elixir:File",
      "line" => nil,
      "character" => nil
    },
    "note" => "Definition is in Elixir standard library"
  }
  ```

  ## Output Path Security

  All paths returned by the LSP server are validated and sanitized:
  - Project paths: Returned as relative paths
  - Dependency paths: Returned as relative paths (deps/*, _build/*)
  - Stdlib paths: Returned as "elixir:Module" or "erlang:module"
  - External paths: Filtered out (not exposed to LLM)

  ## LSP Integration

  This handler is designed to integrate with an LSP client (e.g., ElixirLS, Lexical).
  Until the LSP client infrastructure is implemented (Phase 3.6), this handler
  returns a placeholder response indicating LSP is not yet configured.
  """

  require Logger

  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers

  @doc """
  Executes the go_to_definition operation.

  ## Arguments

  - `params` - Map with "path", "line", and "character" keys
  - `context` - Execution context with session_id or project_root

  ## Returns

  - `{:ok, result}` on success with definition location
  - `{:error, reason}` on failure
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(params, context) do
    start_time = System.monotonic_time(:microsecond)

    with {:ok, path} <- LSPHandlers.extract_path(params),
         {:ok, line} <- LSPHandlers.extract_line(params),
         {:ok, character} <- LSPHandlers.extract_character(params),
         {:ok, safe_path} <- LSPHandlers.validate_path(path, context),
         :ok <- LSPHandlers.validate_file_exists(safe_path) do
      result = go_to_definition(safe_path, line, character, context)
      LSPHandlers.emit_lsp_telemetry(:go_to_definition, start_time, path, context, :success)
      result
    else
      {:error, reason} ->
        path = Map.get(params, "path", "<unknown>")
        LSPHandlers.emit_lsp_telemetry(:go_to_definition, start_time, path, context, :error)
        {:error, LSPHandlers.format_error(reason, path)}
    end
  end

  # ============================================================================
  # LSP Integration
  # ============================================================================

  # Go to definition using LSP server
  # Currently returns a placeholder until LSP client infrastructure is implemented
  defp go_to_definition(path, line, character, _context) do
    # TODO: Integrate with LSP client once Phase 3.6 is implemented
    # For now, check if the file is an Elixir file and return helpful info
    if LSPHandlers.elixir_file?(path) do
      Logger.debug(
        "LSP go_to_definition requested for #{path}:#{line}:#{character} - LSP client not yet implemented"
      )

      # Return a structured response indicating LSP is not yet available
      {:ok,
       %{
         "status" => "lsp_not_configured",
         "message" =>
           "LSP integration is not yet configured. " <>
             "Definition navigation will be available once an LSP server (ElixirLS, Lexical) is connected.",
         "position" => %{
           "path" => path,
           "line" => line,
           "character" => character
         },
         "hint" =>
           "To enable LSP features, ensure you have ElixirLS or Lexical running " <>
             "and the LSP client is configured in Phase 3.6."
       }}
    else
      {:ok,
       %{
         "status" => "unsupported_file_type",
         "message" => "Go to definition is only available for Elixir files (.ex, .exs)",
         "path" => path
       }}
    end
  end

  # ============================================================================
  # LSP Response Processing (for Phase 3.6 integration)
  # ============================================================================

  @doc """
  Processes an LSP definition response, validating and sanitizing output paths.

  This function will be called when the LSP client is integrated (Phase 3.6).
  It handles both single and multiple definition responses from the LSP server.

  ## Parameters

  - `lsp_response` - Raw response from LSP server (single Location or array)
  - `context` - Execution context with project_root

  ## Returns

  - `{:ok, result}` - Processed result with sanitized paths
  - `{:error, :definition_not_found}` - No valid definitions found
  """
  @spec process_lsp_definition_response(map() | [map()] | nil, map()) ::
          {:ok, map()} | {:error, :definition_not_found}
  def process_lsp_definition_response(nil, _context), do: {:error, :definition_not_found}

  def process_lsp_definition_response([], _context), do: {:error, :definition_not_found}

  # Single definition (LSP Location)
  def process_lsp_definition_response(%{"uri" => _uri} = location, context) do
    process_lsp_definition_response([location], context)
  end

  # Multiple definitions (array of LSP Locations)
  def process_lsp_definition_response(locations, context) when is_list(locations) do
    # Use for comprehension for cleaner filtering
    processed =
      for location <- locations,
          {:ok, definition} <- [process_single_location(location, context)] do
        definition
      end

    case processed do
      [] ->
        {:error, :definition_not_found}

      [single] ->
        {:ok,
         %{
           "status" => "found",
           "definition" => single
         }}

      multiple ->
        {:ok,
         %{
           "status" => "found",
           "definitions" => multiple
         }}
    end
  end

  # Process a single LSP Location
  defp process_single_location(%{"uri" => uri} = location, context) do
    # Convert file:// URI to path (case-insensitive)
    path = LSPHandlers.uri_to_path(uri)

    case LSPHandlers.validate_output_path(path, context) do
      {:ok, safe_path} ->
        # Check if it's a stdlib reference
        is_stdlib =
          String.starts_with?(safe_path, "elixir:") or
            String.starts_with?(safe_path, "erlang:")

        definition =
          if is_stdlib do
            %{
              "path" => safe_path,
              "line" => nil,
              "character" => nil,
              "note" => "Definition is in standard library"
            }
          else
            %{
              "path" => safe_path,
              # LSP uses 0-indexed positions, we convert to 1-indexed (editor convention)
              "line" => get_line_from_location(location),
              "character" => get_character_from_location(location)
            }
          end

        {:ok, definition}

      {:error, :external_path} ->
        # Path is outside allowed boundaries - skip this location
        {:error, :external_path}
    end
  end

  defp process_single_location(_, _context), do: {:error, :invalid_location}

  # Extract line number from LSP Location (convert 0-indexed to 1-indexed)
  defp get_line_from_location(%{"range" => %{"start" => %{"line" => line}}})
       when is_integer(line) do
    line + 1
  end

  defp get_line_from_location(_), do: 1

  # Extract character from LSP Location (convert 0-indexed to 1-indexed)
  defp get_character_from_location(%{"range" => %{"start" => %{"character" => char}}})
       when is_integer(char) do
    char + 1
  end

  defp get_character_from_location(_), do: 1
end
