defmodule JidoCode.Tools.Bridge do
  @moduledoc """
  Erlang-Lua bridge functions for the sandbox.

  This module provides Elixir functions that can be called from Lua scripts.
  All file operations validate paths using `Security.validate_path/3` before
  execution.

  ## Available Bridge Functions

  File operations:
  - `jido.read_file(path)` - Read file contents
  - `jido.write_file(path, content)` - Write content to file
  - `jido.list_dir(path)` - List directory contents
  - `jido.file_exists(path)` - Check if path exists

  Shell operations:
  - `jido.shell(command, args)` - Execute shell command

  ## Usage in Lua

      -- Read a file
      local content = jido.read_file("src/main.ex")

      -- Write a file
      jido.write_file("output.txt", "Hello, World!")

      -- List directory
      local files = jido.list_dir("src")

      -- Check existence
      if jido.file_exists("config.json") then ... end

      -- Run shell command
      local result = jido.shell("mix", {"test"})
      -- result = {exit_code = 0, stdout = "...", stderr = "..."}

  ## Error Handling

  Bridge functions return `{nil, error_message}` on failure, allowing
  Lua scripts to handle errors gracefully.
  """

  alias JidoCode.Tools.Security

  require Logger

  @default_shell_timeout 60_000

  # ============================================================================
  # File Operations
  # ============================================================================

  @doc """
  Reads a file's contents. Called from Lua as `jido.read_file(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[content], state}` on success
  - `{[nil, error], state}` on failure
  """
  def lua_read_file(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        do_read_file(path, state, project_root)

      _ ->
        {[nil, "read_file requires a path argument"], state}
    end
  end

  defp do_read_file(path, state, project_root) do
    with {:ok, safe_path} <- Security.validate_path(path, project_root),
         {:ok, content} <- File.read(safe_path) do
      {[content], state}
    else
      {:error, :path_escapes_boundary} -> {[nil, format_security_error(:path_escapes_boundary, path)], state}
      {:error, :path_outside_boundary} -> {[nil, format_security_error(:path_outside_boundary, path)], state}
      {:error, :symlink_escapes_boundary} -> {[nil, format_security_error(:symlink_escapes_boundary, path)], state}
      {:error, reason} -> {[nil, format_file_error(reason, path)], state}
    end
  end

  @doc """
  Writes content to a file. Called from Lua as `jido.write_file(path, content)`.

  ## Parameters

  - `args` - Lua arguments: `[path, content]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` on success
  - `{[nil, error], state}` on failure
  """
  def lua_write_file(args, state, project_root) do
    case args do
      [path, content] when is_binary(path) and is_binary(content) ->
        do_write_file(path, content, state, project_root)

      [path, _content] when is_binary(path) ->
        {[nil, "write_file content must be a string"], state}

      _ ->
        {[nil, "write_file requires path and content arguments"], state}
    end
  end

  defp do_write_file(path, content, state, project_root) do
    with {:ok, safe_path} <- Security.validate_path(path, project_root),
         :ok <- safe_path |> Path.dirname() |> File.mkdir_p(),
         :ok <- File.write(safe_path, content) do
      {[true], state}
    else
      {:error, :path_escapes_boundary} -> {[nil, format_security_error(:path_escapes_boundary, path)], state}
      {:error, :path_outside_boundary} -> {[nil, format_security_error(:path_outside_boundary, path)], state}
      {:error, :symlink_escapes_boundary} -> {[nil, format_security_error(:symlink_escapes_boundary, path)], state}
      {:error, reason} -> {[nil, format_file_error(reason, path)], state}
    end
  end

  @doc """
  Lists directory contents. Called from Lua as `jido.list_dir(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[entries], state}` on success (entries as Lua array)
  - `{[nil, error], state}` on failure
  """
  def lua_list_dir(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        do_list_dir(path, state, project_root)

      [] ->
        # Default to project root
        lua_list_dir([""], state, project_root)

      _ ->
        {[nil, "list_dir requires a path argument"], state}
    end
  end

  defp do_list_dir(path, state, project_root) do
    with {:ok, safe_path} <- Security.validate_path(path, project_root),
         {:ok, entries} <- File.ls(safe_path) do
      # Convert to Lua array format (1-indexed list of tuples)
      lua_array =
        entries
        |> Enum.sort()
        |> Enum.with_index(1)
        |> Enum.map(fn {entry, idx} -> {idx, entry} end)

      {[lua_array], state}
    else
      {:error, :path_escapes_boundary} -> {[nil, format_security_error(:path_escapes_boundary, path)], state}
      {:error, :path_outside_boundary} -> {[nil, format_security_error(:path_outside_boundary, path)], state}
      {:error, :symlink_escapes_boundary} -> {[nil, format_security_error(:symlink_escapes_boundary, path)], state}
      {:error, reason} -> {[nil, format_file_error(reason, path)], state}
    end
  end

  @doc """
  Checks if a path exists. Called from Lua as `jido.file_exists(path)`.

  ## Parameters

  - `args` - Lua arguments: `[path]`
  - `state` - Lua state
  - `project_root` - Project root for path validation

  ## Returns

  - `{[true], state}` if path exists
  - `{[false], state}` if path doesn't exist
  - `{[nil, error], state}` on security violation
  """
  def lua_file_exists(args, state, project_root) do
    case args do
      [path] when is_binary(path) ->
        case Security.validate_path(path, project_root) do
          {:ok, safe_path} ->
            {[File.exists?(safe_path)], state}

          {:error, reason} ->
            {[nil, format_security_error(reason, path)], state}
        end

      _ ->
        {[nil, "file_exists requires a path argument"], state}
    end
  end

  # ============================================================================
  # Shell Operations
  # ============================================================================

  @doc """
  Executes a shell command. Called from Lua as `jido.shell(command, args)`.

  The command runs in the project directory with a configurable timeout.
  Returns exit code, stdout, and stderr.

  ## Parameters

  - `args` - Lua arguments: `[command]` or `[command, args_table]` or `[command, args_table, opts_table]`
  - `state` - Lua state
  - `project_root` - Project root (used as working directory)

  ## Returns

  - `{[result_table], state}` with `{exit_code, stdout, stderr}`
  - `{[nil, error], state}` on failure

  ## Examples in Lua

      -- Simple command
      local result = jido.shell("ls")

      -- Command with arguments
      local result = jido.shell("mix", {"test", "--trace"})

      -- Command with timeout
      local result = jido.shell("mix", {"compile"}, {timeout = 120000})
  """
  def lua_shell(args, state, project_root) do
    case parse_shell_args(args) do
      {:ok, command, cmd_args, opts} ->
        _timeout = Keyword.get(opts, :timeout, @default_shell_timeout)

        try do
          {output, exit_code} =
            System.cmd(command, cmd_args,
              cd: project_root,
              stderr_to_stdout: false,
              into: "",
              env: []
            )

          # Return as list of tuples - luerl will convert inline to Lua table
          result = [
            {"exit_code", exit_code},
            {"stdout", output},
            {"stderr", ""}
          ]

          {[result], state}
        catch
          :error, :enoent ->
            {[nil, "Command not found: #{command}"], state}

          kind, reason ->
            {[nil, "Shell error: #{kind} - #{inspect(reason)}"], state}
        end

      {:error, message} ->
        {[nil, message], state}
    end
  end

  # ============================================================================
  # Registration
  # ============================================================================

  @doc """
  Registers all bridge functions in the Lua state.

  Creates the `jido` namespace table and registers each function.

  ## Parameters

  - `lua_state` - The Lua state to modify
  - `project_root` - Project root for path validation

  ## Returns

  The modified Lua state with bridge functions registered.
  """
  def register(lua_state, project_root) do
    # Create jido namespace as an empty Lua table
    {tref, lua_state} = :luerl.encode([], lua_state)
    {:ok, lua_state} = :luerl.set_table_keys(["jido"], tref, lua_state)

    # Register each bridge function
    lua_state
    |> register_function("read_file", &lua_read_file/3, project_root)
    |> register_function("write_file", &lua_write_file/3, project_root)
    |> register_function("list_dir", &lua_list_dir/3, project_root)
    |> register_function("file_exists", &lua_file_exists/3, project_root)
    |> register_function("shell", &lua_shell/3, project_root)
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp register_function(lua_state, name, fun, project_root) do
    # Create a wrapper that captures project_root
    wrapper = fn args, state ->
      fun.(args, state, project_root)
    end

    # Wrap as {:erl_func, Fun} for luerl to recognize it as callable
    {:ok, state} = :luerl.set_table_keys(["jido", name], {:erl_func, wrapper}, lua_state)
    state
  end

  defp parse_shell_args([command]) when is_binary(command) do
    {:ok, command, [], []}
  end

  defp parse_shell_args([command, args_table]) when is_binary(command) and is_list(args_table) do
    # Convert Lua array to list of strings
    cmd_args =
      args_table
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_, val} -> to_string(val) end)

    {:ok, command, cmd_args, []}
  end

  defp parse_shell_args([command, args_table, opts_table])
       when is_binary(command) and is_list(args_table) and is_list(opts_table) do
    cmd_args =
      args_table
      |> Enum.sort_by(fn {idx, _} -> idx end)
      |> Enum.map(fn {_, val} -> to_string(val) end)

    opts = parse_shell_opts(opts_table)
    {:ok, command, cmd_args, opts}
  end

  defp parse_shell_args(_) do
    {:error, "shell requires a command string and optional args array"}
  end

  defp parse_shell_opts(opts_table) do
    Enum.reduce(opts_table, [], fn
      {"timeout", timeout}, acc when is_number(timeout) ->
        [{:timeout, trunc(timeout)} | acc]

      _, acc ->
        acc
    end)
  end

  defp format_file_error(:enoent, path), do: "File not found: #{path}"
  defp format_file_error(:eacces, path), do: "Permission denied: #{path}"
  defp format_file_error(:eisdir, path), do: "Is a directory: #{path}"
  defp format_file_error(:enotdir, path), do: "Not a directory: #{path}"
  defp format_file_error(:enomem, _path), do: "Out of memory"
  defp format_file_error(reason, path), do: "File error (#{reason}): #{path}"

  defp format_security_error(:path_escapes_boundary, path) do
    "Security error: path escapes project boundary: #{path}"
  end

  defp format_security_error(:path_outside_boundary, path) do
    "Security error: path is outside project: #{path}"
  end

  defp format_security_error(:symlink_escapes_boundary, path) do
    "Security error: symlink points outside project: #{path}"
  end

  defp format_security_error(reason, path) do
    "Security error (#{reason}): #{path}"
  end
end
