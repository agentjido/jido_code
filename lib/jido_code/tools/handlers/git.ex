defmodule JidoCode.Tools.Handlers.Git do
  @moduledoc """
  Handler modules for Git operations.

  This module serves as a namespace for Git-related tool handlers.

  ## Session Context

  Handlers use `HandlerHelpers.get_project_root/1` for session-aware working directory:

  1. `session_id` present → Uses `Session.Manager.project_root/1`
  2. `project_root` present → Uses provided project root (legacy)
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Handlers

  - `Git.Command` - Execute git commands with safety constraints
  """

  alias JidoCode.Tools.HandlerHelpers

  # ============================================================================
  # Shared Helpers
  # ============================================================================

  @doc false
  @spec get_project_root(map()) :: {:ok, String.t()} | {:error, String.t()}
  defdelegate get_project_root(context), to: HandlerHelpers

  # ============================================================================
  # Telemetry
  # ============================================================================

  @doc false
  @spec emit_git_telemetry(atom(), integer(), String.t(), map(), atom(), integer()) :: :ok
  def emit_git_telemetry(operation, start_time, subcommand, context, status, exit_code) do
    duration = System.monotonic_time(:microsecond) - start_time

    :telemetry.execute(
      [:jido_code, :git, operation],
      %{duration: duration, exit_code: exit_code},
      %{
        subcommand: subcommand,
        status: status,
        session_id: Map.get(context, :session_id)
      }
    )
  end
end

defmodule JidoCode.Tools.Handlers.Git.Command do
  @moduledoc """
  Handler for the git_command tool.

  Executes git commands with security validation including subcommand
  allowlisting and destructive operation guards. Delegates to the Lua
  bridge for actual execution.

  ## Session Context

  Uses `HandlerHelpers.get_project_root/1` for session-aware context:

  1. `session_id` present → Uses `Session.Manager.project_root/1`
  2. `project_root` present → Uses provided project root (legacy)
  3. Neither → Falls back to global `Tools.Manager` (deprecated)

  ## Security

  - Validates subcommand against allowlist
  - Blocks destructive operations unless explicitly allowed
  - Executes commands in the session's project directory
  - Parses structured output for common commands (status, log, diff, branch)

  ## Telemetry

  Emits `[:jido_code, :git, :command]` telemetry events with:
  - Measurements: `duration` (microseconds), `exit_code`
  - Metadata: `subcommand`, `status`, `session_id`
  """

  alias JidoCode.Tools.Bridge
  alias JidoCode.Tools.Handlers.Git

  @doc """
  Executes a git command.

  ## Parameters

  - `params` - Map with:
    - `"subcommand"` (required) - Git subcommand to execute
    - `"args"` (optional) - Additional arguments
    - `"allow_destructive"` (optional) - Allow destructive operations

  - `context` - Map with:
    - `:session_id` - Session identifier (preferred)
    - `:project_root` - Project directory (legacy)

  ## Returns

  - `{:ok, map}` - Success with output, parsed data, and exit_code
  - `{:error, string}` - Error with message

  ## Examples

      iex> execute(%{"subcommand" => "status"}, %{session_id: "abc123..."})
      {:ok, %{output: "...", parsed: %{...}, exit_code: 0}}

      iex> execute(%{"subcommand" => "status"}, %{project_root: "/path/to/repo"})
      {:ok, %{output: "...", parsed: %{...}, exit_code: 0}}

      iex> execute(%{"subcommand" => "push", "args" => ["--force"]}, %{project_root: "/path"})
      {:error, "destructive operation blocked: ..."}
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(params, context) do
    start_time = System.monotonic_time(:microsecond)
    subcommand = Map.get(params, "subcommand")
    args = Map.get(params, "args", [])
    allow_destructive = Map.get(params, "allow_destructive", false)

    with :ok <- validate_subcommand(subcommand),
         {:ok, project_root} <- get_project_root(context) do
      bridge_args = build_bridge_args(subcommand, args, allow_destructive)

      case Bridge.lua_git(bridge_args, :luerl.init(), project_root) do
        {[result], _state} when is_list(result) ->
          result_map = convert_result(result)
          exit_code = Map.get(result_map, :exit_code, 0)
          Git.emit_git_telemetry(:command, start_time, subcommand, context, :ok, exit_code)
          {:ok, result_map}

        {[nil, error], _state} ->
          Git.emit_git_telemetry(:command, start_time, subcommand, context, :error, 1)
          {:error, error}
      end
    else
      {:error, reason} when is_atom(reason) ->
        Git.emit_git_telemetry(:command, start_time, subcommand || "unknown", context, :error, 1)
        {:error, format_error(reason)}

      {:error, reason} ->
        Git.emit_git_telemetry(:command, start_time, subcommand || "unknown", context, :error, 1)
        {:error, reason}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Delegates to HandlerHelpers for session-aware project root
  defp get_project_root(context), do: Git.get_project_root(context)

  # Validates the subcommand is provided and is a string
  defp validate_subcommand(nil) do
    {:error, "subcommand is required"}
  end

  defp validate_subcommand(subcommand) when is_binary(subcommand) do
    :ok
  end

  defp validate_subcommand(_) do
    {:error, "subcommand must be a string"}
  end

  # Formats error atoms to human-readable messages
  defp format_error(:not_found), do: "session not found"
  defp format_error(:invalid_session_id), do: "invalid session ID format"
  defp format_error(:session_context_required), do: "session_id or project_root required"
  defp format_error(reason) when is_atom(reason), do: "#{reason}"
  defp format_error(reason), do: reason

  # Builds arguments for the bridge function
  defp build_bridge_args(subcommand, [], false) do
    [subcommand]
  end

  defp build_bridge_args(subcommand, args, false) when is_list(args) and args != [] do
    args_table = args |> Enum.with_index(1) |> Enum.map(fn {arg, idx} -> {idx, arg} end)
    [subcommand, args_table]
  end

  defp build_bridge_args(subcommand, args, allow_destructive) when is_list(args) do
    args_table =
      if args == [] do
        []
      else
        args |> Enum.with_index(1) |> Enum.map(fn {arg, idx} -> {idx, arg} end)
      end

    opts_table = [{"allow_destructive", allow_destructive}]
    [subcommand, args_table, opts_table]
  end

  # Converts the bridge result to a map
  defp convert_result(result) do
    result
    |> Enum.reduce(%{}, fn
      {"output", output}, acc -> Map.put(acc, :output, output)
      {"parsed", parsed}, acc -> Map.put(acc, :parsed, convert_parsed(parsed))
      {"exit_code", code}, acc -> Map.put(acc, :exit_code, code)
      _, acc -> acc
    end)
  end

  # Converts nested Lua table parsed data to Elixir maps
  defp convert_parsed(parsed) when is_list(parsed) do
    cond do
      # List of tuples with string keys (like {key, value} pairs from Lua)
      Enum.all?(parsed, fn
        {k, _v} when is_binary(k) -> true
        _ -> false
      end) ->
        Enum.reduce(parsed, %{}, fn {k, v}, acc ->
          Map.put(acc, String.to_atom(k), convert_parsed(v))
        end)

      # Numeric indexed list (array from Lua)
      Enum.all?(parsed, fn
        {k, _v} when is_integer(k) -> true
        _ -> false
      end) ->
        parsed
        |> Enum.sort_by(fn {k, _} -> k end)
        |> Enum.map(fn {_, v} -> convert_parsed(v) end)

      # Empty list
      true ->
        parsed
    end
  end

  defp convert_parsed(value), do: value
end
