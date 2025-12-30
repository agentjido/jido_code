defmodule JidoCode.Tools.Handlers.LSP do
  @moduledoc """
  Handler modules for LSP (Language Server Protocol) tools.

  This module contains handlers for code intelligence operations:
  - `GetHoverInfo` - Get type info and documentation at cursor position
  - `GoToDefinition` - Find where a symbol is defined
  - `FindReferences` - Find all usages of a symbol

  ## Expert Integration

  Handlers connect to Expert (the official Elixir LSP) via the LSP.Client module.
  Each project gets its own LSP client managed by LSP.Supervisor.

  ## Session Context

  Handlers use `HandlerHelpers.validate_path/2` for session-aware path validation:

  1. `session_id` present → Uses `Session.Manager.validate_path/2`
  2. `project_root` present → Uses `Security.validate_path/3`
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

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
  alias JidoCode.Tools.LSP.{Client, Protocol, Supervisor}

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

  def format_error(:no_references_found, path),
    do: "No references found for symbol at this position in: #{path}"

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

  # ============================================================================
  # Shared LSP Location Helpers (used by GoToDefinition and FindReferences)
  # ============================================================================

  @doc """
  Checks if a sanitized path represents a stdlib (Elixir or Erlang) location.

  Stdlib paths are sanitized to "elixir:Module" or "erlang:module" format.
  """
  @spec stdlib_path?(String.t()) :: boolean()
  def stdlib_path?(path) when is_binary(path) do
    String.starts_with?(path, "elixir:") or String.starts_with?(path, "erlang:")
  end

  def stdlib_path?(_), do: false

  @doc """
  Extracts line number from LSP Location, converting from 0-indexed to 1-indexed.

  LSP uses 0-indexed positions, but editors display 1-indexed positions.
  Returns 1 as fallback if the location structure is invalid.
  """
  @spec get_line_from_location(map()) :: pos_integer()
  def get_line_from_location(%{"range" => %{"start" => %{"line" => line}}})
      when is_integer(line) do
    line + 1
  end

  def get_line_from_location(_), do: 1

  @doc """
  Extracts character offset from LSP Location, converting from 0-indexed to 1-indexed.

  LSP uses 0-indexed positions, but editors display 1-indexed positions.
  Returns 1 as fallback if the location structure is invalid.
  """
  @spec get_character_from_location(map()) :: pos_integer()
  def get_character_from_location(%{"range" => %{"start" => %{"character" => char}}})
      when is_integer(char) do
    char + 1
  end

  def get_character_from_location(_), do: 1

  # ============================================================================
  # LSP Client Access
  # ============================================================================

  @doc """
  Gets the LSP client for the given context.

  Returns the client pid if Expert is available and initialized,
  or an error if the client cannot be obtained.

  ## Parameters

  - `context` - Execution context with project_root

  ## Returns

  - `{:ok, client_pid}` - The LSP client process
  - `{:error, :lsp_not_available}` - Expert is not installed or client failed
  """
  @spec get_lsp_client(map()) :: {:ok, pid()} | {:error, :lsp_not_available}
  def get_lsp_client(context) do
    with {:ok, project_root} <- get_project_root(context),
         {:ok, client} <- Supervisor.get_or_start_client(project_root) do
      # Check if client is initialized
      case Client.status(client) do
        %{initialized: true} ->
          {:ok, client}

        %{initialized: false} ->
          # Client exists but not yet initialized - wait a bit
          Process.sleep(500)

          case Client.status(client) do
            %{initialized: true} -> {:ok, client}
            _ -> {:error, :lsp_not_available}
          end
      end
    else
      {:error, :expert_not_available} ->
        {:error, :lsp_not_available}

      {:error, _reason} ->
        {:error, :lsp_not_available}
    end
  end

  @doc """
  Checks if Expert LSP is available for the given context.
  """
  @spec lsp_available?(map()) :: boolean()
  def lsp_available?(context) do
    case get_lsp_client(context) do
      {:ok, _client} -> true
      {:error, _} -> false
    end
  end

  # ============================================================================
  # Shared Execute Helper (reduces duplication across LSP handlers)
  # ============================================================================

  @doc """
  Executes an LSP operation with common parameter extraction, validation, and telemetry.

  This helper reduces code duplication across GetHoverInfo, GoToDefinition, and
  FindReferences handlers by providing a common execution pattern.

  ## Parameters

  - `params` - Map with "path", "line", and "character" keys
  - `context` - Execution context with session_id or project_root
  - `operation` - Atom identifying the operation (e.g., :get_hover_info)
  - `handler_fn` - Function to call with (safe_path, line, character, context)

  ## Returns

  - `{:ok, result}` on success from handler_fn
  - `{:error, reason}` on validation or handler failure
  """
  @spec execute_lsp_operation(map(), map(), atom(), function()) ::
          {:ok, map()} | {:error, String.t()}
  def execute_lsp_operation(params, context, operation, handler_fn) do
    start_time = System.monotonic_time(:microsecond)

    with {:ok, path} <- extract_path(params),
         {:ok, line} <- extract_line(params),
         {:ok, character} <- extract_character(params),
         {:ok, safe_path} <- validate_path(path, context),
         :ok <- validate_file_exists(safe_path) do
      result = handler_fn.(safe_path, line, character, context)
      emit_lsp_telemetry(operation, start_time, path, context, :success)
      result
    else
      {:error, reason} ->
        path = Map.get(params, "path", "<unknown>")
        emit_lsp_telemetry(operation, start_time, path, context, :error)
        {:error, format_error(reason, path)}
    end
  end
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

  ## Expert Integration

  This handler connects to Expert (the official Elixir LSP) when available.
  If Expert is not installed, returns a helpful message indicating LSP is not available.
  """

  require Logger

  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers
  alias JidoCode.Tools.LSP.{Client, Protocol}

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
    LSPHandlers.execute_lsp_operation(params, context, :get_hover_info, &get_hover_info/4)
  end

  # ============================================================================
  # LSP Integration
  # ============================================================================

  # Get hover information from Expert LSP server
  defp get_hover_info(path, line, character, context) do
    if LSPHandlers.elixir_file?(path) do
      case LSPHandlers.get_lsp_client(context) do
        {:ok, client} ->
          request_hover_from_expert(client, path, line, character)

        {:error, :lsp_not_available} ->
          lsp_not_available_response(path, line, character)
      end
    else
      {:ok,
       %{
         "status" => "unsupported_file_type",
         "message" => "Hover info is only available for Elixir files (.ex, .exs)",
         "path" => path
       }}
    end
  end

  # Request hover information from Expert
  defp request_hover_from_expert(client, path, line, character) do
    # Build LSP params using protocol types (converts 1-indexed to 0-indexed)
    params = Protocol.hover_params(path, line, character)

    Logger.debug("Requesting hover info from Expert for #{path}:#{line}:#{character}")

    case Client.request(client, Protocol.method_hover(), params) do
      {:ok, nil} ->
        {:ok,
         %{
           "status" => "no_info",
           "message" => "No hover information available at this position",
           "position" => %{"path" => path, "line" => line, "character" => character}
         }}

      {:ok, hover_result} ->
        process_hover_response(hover_result, path, line, character)

      {:error, :timeout} ->
        {:error, LSPHandlers.format_error(:lsp_timeout, path)}

      {:error, reason} ->
        Logger.warning("Expert hover request failed: #{inspect(reason)}")
        {:error, LSPHandlers.format_error(:lsp_not_available, path)}
    end
  end

  # Process hover response from Expert
  defp process_hover_response(hover_result, path, line, character) do
    case Protocol.Hover.from_lsp(hover_result) do
      {:ok, hover} ->
        {:ok,
         %{
           "status" => "found",
           "contents" => Protocol.Hover.to_text(hover),
           "position" => %{"path" => path, "line" => line, "character" => character}
         }}

      {:error, _} ->
        {:ok,
         %{
           "status" => "no_info",
           "message" => "No hover information available at this position",
           "position" => %{"path" => path, "line" => line, "character" => character}
         }}
    end
  end

  # Response when Expert is not available
  defp lsp_not_available_response(path, line, character) do
    Logger.debug("Expert not available for hover request at #{path}:#{line}:#{character}")

    {:ok,
     %{
       "status" => "lsp_not_available",
       "message" =>
         "Expert LSP is not available. " <>
           "Install Expert (https://github.com/elixir-lang/expert) to enable code intelligence.",
       "position" => %{
         "path" => path,
         "line" => line,
         "character" => character
       }
     }}
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

  ## Expert Integration

  This handler connects to Expert (the official Elixir LSP) when available.
  If Expert is not installed, returns a helpful message indicating LSP is not available.
  """

  require Logger

  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers
  alias JidoCode.Tools.LSP.{Client, Protocol}

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
    LSPHandlers.execute_lsp_operation(params, context, :go_to_definition, &go_to_definition/4)
  end

  # ============================================================================
  # LSP Integration
  # ============================================================================

  # Go to definition using Expert LSP server
  defp go_to_definition(path, line, character, context) do
    if LSPHandlers.elixir_file?(path) do
      case LSPHandlers.get_lsp_client(context) do
        {:ok, client} ->
          request_definition_from_expert(client, path, line, character, context)

        {:error, :lsp_not_available} ->
          lsp_not_available_response(path, line, character)
      end
    else
      {:ok,
       %{
         "status" => "unsupported_file_type",
         "message" => "Go to definition is only available for Elixir files (.ex, .exs)",
         "path" => path
       }}
    end
  end

  # Request definition from Expert
  defp request_definition_from_expert(client, path, line, character, context) do
    # Build LSP params using protocol types (converts 1-indexed to 0-indexed)
    params = Protocol.definition_params(path, line, character)

    Logger.debug("Requesting definition from Expert for #{path}:#{line}:#{character}")

    case Client.request(client, Protocol.method_definition(), params) do
      {:ok, nil} ->
        {:error, LSPHandlers.format_error(:definition_not_found, path)}

      {:ok, []} ->
        {:error, LSPHandlers.format_error(:definition_not_found, path)}

      {:ok, locations} ->
        process_lsp_definition_response(locations, context)

      {:error, :timeout} ->
        {:error, LSPHandlers.format_error(:lsp_timeout, path)}

      {:error, reason} ->
        Logger.warning("Expert definition request failed: #{inspect(reason)}")
        {:error, LSPHandlers.format_error(:lsp_not_available, path)}
    end
  end

  # Response when Expert is not available
  defp lsp_not_available_response(path, line, character) do
    Logger.debug("Expert not available for definition request at #{path}:#{line}:#{character}")

    {:ok,
     %{
       "status" => "lsp_not_available",
       "message" =>
         "Expert LSP is not available. " <>
           "Install Expert (https://github.com/elixir-lang/expert) to enable code intelligence.",
       "position" => %{
         "path" => path,
         "line" => line,
         "character" => character
       }
     }}
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
        definition =
          if LSPHandlers.stdlib_path?(safe_path) do
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
              "line" => LSPHandlers.get_line_from_location(location),
              "character" => LSPHandlers.get_character_from_location(location)
            }
          end

        {:ok, definition}

      {:error, :external_path} ->
        # Path is outside allowed boundaries - skip this location
        {:error, :external_path}
    end
  end

  defp process_single_location(_, _context), do: {:error, :invalid_location}
end

defmodule JidoCode.Tools.Handlers.LSP.FindReferences do
  @moduledoc """
  Handler for the find_references tool.

  Finds all usages of a symbol using the Language Server Protocol (LSP).
  Returns a list of locations where the symbol is referenced.

  ## Parameters

  - `path` (required) - File path to query
  - `line` (required) - Line number (1-indexed)
  - `character` (required) - Character offset (1-indexed)
  - `include_declaration` (optional) - Include the declaration in results (default: false)

  ## Returns

  - `{:ok, result}` - Map with reference locations
  - `{:error, reason}` - Error message string

  ## Response Format

  ```elixir
  %{
    "status" => "found",
    "references" => [
      %{"path" => "lib/caller_a.ex", "line" => 10, "character" => 5},
      %{"path" => "lib/caller_b.ex", "line" => 22, "character" => 15}
    ],
    "count" => 2
  }
  ```

  ## Output Path Security

  All paths returned by the LSP server are validated and filtered:
  - Project paths: Returned as relative paths
  - Dependency paths: Returned as relative paths (deps/*, _build/*)
  - Stdlib/OTP paths: Filtered out (not exposed to LLM)
  - External paths: Filtered out (not exposed to LLM)

  ## Expert Integration

  This handler connects to Expert (the official Elixir LSP) when available.
  If Expert is not installed, returns a helpful message indicating LSP is not available.
  """

  require Logger

  alias JidoCode.Tools.Handlers.LSP, as: LSPHandlers
  alias JidoCode.Tools.LSP.{Client, Protocol}

  @doc """
  Executes the find_references operation.

  ## Arguments

  - `params` - Map with "path", "line", "character", and optional "include_declaration" keys
  - `context` - Execution context with session_id or project_root

  ## Returns

  - `{:ok, result}` on success with reference locations
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
      include_declaration = extract_include_declaration(params)
      result = find_references(safe_path, line, character, include_declaration, context)
      LSPHandlers.emit_lsp_telemetry(:find_references, start_time, path, context, :success)
      result
    else
      {:error, reason} ->
        path = Map.get(params, "path", "<unknown>")
        LSPHandlers.emit_lsp_telemetry(:find_references, start_time, path, context, :error)
        {:error, LSPHandlers.format_error(reason, path)}
    end
  end

  # Extract include_declaration parameter (default: false)
  # The Executor validates that the value is a boolean before reaching this handler,
  # so we only handle boolean values and missing parameters here.
  defp extract_include_declaration(%{"include_declaration" => value}) when is_boolean(value) do
    value
  end

  defp extract_include_declaration(_), do: false

  # ============================================================================
  # LSP Integration
  # ============================================================================

  # Find references using Expert LSP server
  defp find_references(path, line, character, include_declaration, context) do
    if LSPHandlers.elixir_file?(path) do
      case LSPHandlers.get_lsp_client(context) do
        {:ok, client} ->
          request_references_from_expert(
            client,
            path,
            line,
            character,
            include_declaration,
            context
          )

        {:error, :lsp_not_available} ->
          lsp_not_available_response(path, line, character, include_declaration)
      end
    else
      {:ok,
       %{
         "status" => "unsupported_file_type",
         "message" => "Find references is only available for Elixir files (.ex, .exs)",
         "path" => path
       }}
    end
  end

  # Request references from Expert LSP server
  defp request_references_from_expert(client, path, line, character, include_declaration, context) do
    params =
      Protocol.references_params(path, line, character, include_declaration: include_declaration)

    case Client.request(client, Protocol.method_references(), params) do
      {:ok, nil} ->
        {:ok,
         %{
           "status" => "no_references",
           "message" => "No references found for the symbol at this position",
           "position" => %{
             "path" => path,
             "line" => line,
             "character" => character
           },
           "include_declaration" => include_declaration
         }}

      {:ok, []} ->
        {:ok,
         %{
           "status" => "no_references",
           "message" => "No references found for the symbol at this position",
           "position" => %{
             "path" => path,
             "line" => line,
             "character" => character
           },
           "include_declaration" => include_declaration
         }}

      {:ok, locations} when is_list(locations) ->
        case process_lsp_references_response(locations, context) do
          {:ok, result} ->
            {:ok, result}

          {:error, :no_references_found} ->
            {:ok,
             %{
               "status" => "no_references",
               "message" => "No references found within project boundaries",
               "position" => %{
                 "path" => path,
                 "line" => line,
                 "character" => character
               },
               "include_declaration" => include_declaration
             }}
        end

      {:error, :timeout} ->
        {:error, LSPHandlers.format_error(:lsp_timeout, path)}

      {:error, reason} ->
        Logger.warning("LSP references request failed: #{inspect(reason)}")
        {:error, LSPHandlers.format_error(:lsp_not_available, path)}
    end
  end

  # Response when LSP is not available
  defp lsp_not_available_response(path, line, character, include_declaration) do
    {:ok,
     %{
       "status" => "lsp_not_available",
       "message" =>
         "Expert LSP server is not available. Install Expert to enable LSP features: " <>
           "mix archive.install hex expert",
       "position" => %{
         "path" => path,
         "line" => line,
         "character" => character
       },
       "include_declaration" => include_declaration,
       "hint" => "Visit https://github.com/elixir-lang/expert for installation instructions"
     }}
  end

  # ============================================================================
  # LSP Response Processing (for Phase 3.6 integration)
  # ============================================================================

  @doc """
  Processes an LSP references response, validating and filtering output paths.

  This function will be called when the LSP client is integrated (Phase 3.6).
  It filters out any references outside the project boundary.

  ## Parameters

  - `lsp_response` - Raw response from LSP server (array of Locations)
  - `context` - Execution context with project_root

  ## Returns

  - `{:ok, result}` - Processed result with filtered and sanitized paths
  - `{:error, :no_references_found}` - No valid references found

  ## Notes

  Unlike go_to_definition, find_references does NOT include stdlib/OTP paths
  in results, as references in standard library code are not useful for the user.
  """
  @spec process_lsp_references_response([map()] | nil, map()) ::
          {:ok, map()} | {:error, :no_references_found}
  def process_lsp_references_response(nil, _context), do: {:error, :no_references_found}

  def process_lsp_references_response([], _context), do: {:error, :no_references_found}

  def process_lsp_references_response(locations, context) when is_list(locations) do
    # Filter to only project-local paths (no stdlib/OTP)
    references =
      for location <- locations,
          {:ok, ref} <- [process_reference_location(location, context)] do
        ref
      end

    case references do
      [] ->
        {:error, :no_references_found}

      refs ->
        {:ok,
         %{
           "status" => "found",
           "references" => refs,
           "count" => length(refs)
         }}
    end
  end

  # Process a single LSP Location for references
  # Only includes project-local paths (excludes stdlib/OTP)
  defp process_reference_location(%{"uri" => uri} = location, context) do
    # Convert file:// URI to path (case-insensitive)
    path = LSPHandlers.uri_to_path(uri)

    case LSPHandlers.validate_output_path(path, context) do
      {:ok, safe_path} ->
        # For references, exclude stdlib paths (they're not useful)
        if LSPHandlers.stdlib_path?(safe_path) do
          {:error, :stdlib_path}
        else
          {:ok,
           %{
             "path" => safe_path,
             # LSP uses 0-indexed positions, we convert to 1-indexed (editor convention)
             "line" => LSPHandlers.get_line_from_location(location),
             "character" => LSPHandlers.get_character_from_location(location)
           }}
        end

      {:error, :external_path} ->
        # Path is outside allowed boundaries - skip this location
        {:error, :external_path}
    end
  end

  defp process_reference_location(_, _context), do: {:error, :invalid_location}
end
