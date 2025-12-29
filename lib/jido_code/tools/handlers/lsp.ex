defmodule JidoCode.Tools.Handlers.LSP do
  @moduledoc """
  Handler modules for LSP (Language Server Protocol) tools.

  This module contains handlers for code intelligence operations:
  - `GetHoverInfo` - Get type info and documentation at cursor position

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
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec get_project_root(map()) ::
          {:ok, String.t()} | {:error, :not_found | :invalid_session_id | String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  @doc false
  @spec validate_path(String.t(), map()) ::
          {:ok, String.t()} | {:error, atom() | :not_found | :invalid_session_id}
  defdelegate validate_path(path, context), to: HandlerHelpers

  @doc false
  @spec format_error(atom() | {atom(), term()} | String.t(), String.t()) :: String.t()
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

    with {:ok, path} <- extract_path(params),
         {:ok, line} <- extract_line(params),
         {:ok, character} <- extract_character(params),
         {:ok, safe_path} <- LSPHandlers.validate_path(path, context),
         :ok <- validate_file_exists(safe_path) do
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
  # Parameter Extraction
  # ============================================================================

  defp extract_path(%{"path" => path}) when is_binary(path) and byte_size(path) > 0 do
    {:ok, path}
  end

  defp extract_path(_), do: {:error, "path is required and must be a non-empty string"}

  defp extract_line(%{"line" => line}) when is_integer(line) and line >= 1 do
    {:ok, line}
  end

  defp extract_line(%{"line" => line}) when is_binary(line) do
    case Integer.parse(line) do
      {n, ""} when n >= 1 -> {:ok, n}
      _ -> {:error, "line must be a positive integer (1-indexed)"}
    end
  end

  defp extract_line(_), do: {:error, "line is required and must be a positive integer (1-indexed)"}

  defp extract_character(%{"character" => character})
       when is_integer(character) and character >= 1 do
    {:ok, character}
  end

  defp extract_character(%{"character" => character}) when is_binary(character) do
    case Integer.parse(character) do
      {n, ""} when n >= 1 -> {:ok, n}
      _ -> {:error, "character must be a positive integer (1-indexed)"}
    end
  end

  defp extract_character(_),
    do: {:error, "character is required and must be a positive integer (1-indexed)"}

  # ============================================================================
  # File Validation
  # ============================================================================

  defp validate_file_exists(path) do
    if File.exists?(path) do
      :ok
    else
      {:error, :enoent}
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
    if elixir_file?(path) do
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

  defp elixir_file?(path) do
    ext = Path.extname(path) |> String.downcase()
    ext in [".ex", ".exs"]
  end
end
