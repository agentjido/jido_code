defmodule JidoCode.Tools.Handlers.Git do
  @moduledoc """
  Handler modules for Git operations.

  This module serves as a namespace for Git-related tool handlers.

  ## Handlers

  - `Git.Command` - Execute git commands with safety constraints
  """
end

defmodule JidoCode.Tools.Handlers.Git.Command do
  @moduledoc """
  Handler for the git_command tool.

  Executes git commands with security validation including subcommand
  allowlisting and destructive operation guards. Delegates to the Lua
  bridge for actual execution.

  ## Security

  - Validates subcommand against allowlist
  - Blocks destructive operations unless explicitly allowed
  - Executes commands in the session's project directory
  - Parses structured output for common commands (status, log, diff, branch)
  """

  alias JidoCode.Tools.Bridge

  @doc """
  Executes a git command.

  ## Parameters

  - `params` - Map with:
    - `"subcommand"` (required) - Git subcommand to execute
    - `"args"` (optional) - Additional arguments
    - `"allow_destructive"` (optional) - Allow destructive operations

  - `context` - Map with:
    - `:project_root` - Project directory (required)
    - `:session_id` - Session identifier (optional)

  ## Returns

  - `{:ok, map}` - Success with output, parsed data, and exit_code
  - `{:error, string}` - Error with message

  ## Examples

      iex> execute(%{"subcommand" => "status"}, %{project_root: "/path/to/repo"})
      {:ok, %{output: "...", parsed: %{...}, exit_code: 0}}

      iex> execute(%{"subcommand" => "push", "args" => ["--force"]}, %{project_root: "/path"})
      {:error, "destructive operation blocked: ..."}
  """
  @spec execute(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def execute(params, context) do
    subcommand = Map.get(params, "subcommand")
    args = Map.get(params, "args", [])
    allow_destructive = Map.get(params, "allow_destructive", false)

    with :ok <- validate_subcommand(subcommand),
         :ok <- validate_context(context) do
      project_root = Map.fetch!(context, :project_root)
      bridge_args = build_bridge_args(subcommand, args, allow_destructive)

      case Bridge.lua_git(bridge_args, :luerl.init(), project_root) do
        {[result], _state} when is_list(result) ->
          {:ok, convert_result(result)}

        {[nil, error], _state} ->
          {:error, error}
      end
    end
  end

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

  # Validates required context fields
  defp validate_context(%{project_root: project_root}) when is_binary(project_root) do
    :ok
  end

  defp validate_context(_) do
    {:error, "project_root is required in context"}
  end

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
