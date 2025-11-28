defmodule JidoCode.Tools.Manager do
  @moduledoc """
  GenServer wrapping the Luerl Lua runtime for sandboxed tool execution.

  The Manager maintains a Lua state with dangerous functions removed to prevent:
  - Shell command execution (os.execute, io.popen)
  - Process termination (os.exit)
  - Arbitrary file loading (loadfile, dofile, require)
  - Module system access (package)

  ## Usage

  The Manager is started as part of the application supervision tree with
  a project root path that defines the boundary for file operations.

      # Via supervision tree (automatic)
      JidoCode.Tools.Manager.execute("my_tool", %{"arg" => "value"})

      # Get project root
      {:ok, path} = JidoCode.Tools.Manager.project_root()

  ## Sandbox Restrictions

  The following Lua functions are removed from the sandbox:

  - `os.execute` - Shell command execution
  - `os.exit` - Process termination
  - `io.popen` - Shell command with pipe
  - `loadfile` - Load Lua code from file
  - `dofile` - Execute Lua file
  - `package` - Module loading system
  - `require` - Module require

  ## Tool Execution

  Tools are executed by loading their Lua script and calling it with the
  provided arguments. The script is expected to return a result that will
  be converted to Elixir terms.
  """

  use GenServer

  require Logger

  @type state :: %{
          lua_state: :luerl.luerl_state(),
          project_root: String.t()
        }

  @default_timeout 30_000

  # Dangerous functions to remove from sandbox
  @restricted_functions [
    [:os, :execute],
    [:os, :exit],
    [:io, :popen],
    [:loadfile],
    [:dofile],
    [:package],
    [:require]
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the Manager GenServer.

  ## Options

  - `:project_root` - Root directory for file operations (default: cwd)
  - `:name` - GenServer name (default: `__MODULE__`)

  ## Examples

      {:ok, pid} = Manager.start_link(project_root: "/my/project")
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Executes a Lua script in the sandbox.

  The script is executed with the provided arguments available as a global
  `args` table. The script should return a value that becomes the result.

  ## Parameters

  - `script` - Lua code to execute
  - `args` - Map of arguments (available as `args` table in Lua)
  - `timeout` - Execution timeout in milliseconds (default: 30000)

  ## Returns

  - `{:ok, result}` - Execution succeeded with result
  - `{:error, reason}` - Execution failed

  ## Examples

      {:ok, result} = Manager.execute("return args.x + args.y", %{"x" => 1, "y" => 2})
      # => {:ok, 3.0}

      {:error, reason} = Manager.execute("os.execute('rm -rf /')", %{})
      # => {:error, "attempt to call a nil value"}
  """
  @spec execute(String.t(), map(), pos_integer()) :: {:ok, term()} | {:error, term()}
  def execute(script, args \\ %{}, timeout \\ @default_timeout) do
    GenServer.call(__MODULE__, {:execute, script, args}, timeout + 1000)
  end

  @doc """
  Gets the project root path.

  ## Returns

  - `{:ok, path}` - The project root path
  """
  @spec project_root() :: {:ok, String.t()}
  def project_root do
    GenServer.call(__MODULE__, :project_root)
  end

  @doc """
  Checks if a function is restricted in the sandbox.

  ## Parameters

  - `path` - Function path as list of atoms (e.g., `[:os, :execute]`)

  ## Returns

  - `true` if the function is restricted
  - `false` if the function is allowed
  """
  @spec restricted?(list(atom())) :: boolean()
  def restricted?(path) when is_list(path) do
    path in @restricted_functions
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    project_root = Keyword.get(opts, :project_root, File.cwd!())

    Logger.info("Starting Tools.Manager with project_root: #{project_root}")

    # Initialize Lua state and apply sandbox restrictions
    lua_state =
      :luerl.init()
      |> apply_sandbox_restrictions()

    {:ok, %{lua_state: lua_state, project_root: project_root}}
  end

  @impl true
  def handle_call({:execute, script, args}, _from, state) do
    result = execute_script(script, args, state.lua_state)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:project_root, _from, state) do
    {:reply, {:ok, state.project_root}, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp apply_sandbox_restrictions(lua_state) do
    Enum.reduce(@restricted_functions, lua_state, fn path, state ->
      remove_function(state, path)
    end)
  end

  defp remove_function(lua_state, [key]) when is_atom(key) do
    # Remove top-level global
    key_str = Atom.to_string(key)
    {:ok, state} = :luerl.set_table_keys([key_str], nil, lua_state)
    state
  end

  defp remove_function(lua_state, path) when is_list(path) do
    # Remove nested function (e.g., [:os, :execute])
    path_strs = Enum.map(path, &Atom.to_string/1)
    {:ok, state} = :luerl.set_table_keys(path_strs, nil, lua_state)
    state
  end

  defp execute_script(script, args, lua_state) do
    # Set args as global table using luerl's encode
    {encoded_args, lua_state} = encode_args(args, lua_state)
    {:ok, lua_state} = :luerl.set_table_keys(["args"], encoded_args, lua_state)

    # Execute the script
    case :luerl.do(script, lua_state) do
      {:ok, results, new_state} ->
        # Decode results - luerl returns a list of return values
        result = decode_results(results, new_state)
        {:ok, result}

      {:error, reason, _state} ->
        {:error, format_error(reason)}
    end
  rescue
    e ->
      {:error, Exception.message(e)}
  catch
    kind, reason ->
      {:error, "#{kind}: #{inspect(reason)}"}
  end

  defp encode_args(args, lua_state) when map_size(args) == 0 do
    # Create empty Lua table
    :luerl.encode([], lua_state)
  end

  defp encode_args(args, lua_state) do
    # Convert to list of tuples for Lua table
    lua_table = Enum.map(args, fn {k, v} -> {to_string(k), encode_value(v)} end)
    :luerl.encode(lua_table, lua_state)
  end

  defp encode_value(v) when is_map(v) do
    Enum.map(v, fn {k, val} -> {to_string(k), encode_value(val)} end)
  end

  defp encode_value(v) when is_list(v) do
    Enum.with_index(v, 1) |> Enum.map(fn {val, idx} -> {idx, encode_value(val)} end)
  end

  defp encode_value(v) when is_binary(v), do: v
  defp encode_value(v) when is_number(v), do: v
  defp encode_value(v) when is_boolean(v), do: v
  defp encode_value(nil), do: nil
  defp encode_value(v) when is_atom(v), do: Atom.to_string(v)

  defp decode_results([], _state), do: nil
  defp decode_results([single], state), do: decode_value(single, state)
  defp decode_results(multiple, state), do: Enum.map(multiple, &decode_value(&1, state))

  defp decode_value(v, _state) when is_binary(v), do: v
  defp decode_value(v, _state) when is_number(v), do: v
  defp decode_value(v, _state) when is_boolean(v), do: v
  defp decode_value(nil, _state), do: nil

  defp decode_value({:tref, _} = tref, state) do
    # Decode table reference using luerl
    decoded = :luerl.decode(tref, state)
    decode_lua_table(decoded, state)
  end

  defp decode_value(other, _state), do: inspect(other)

  defp decode_lua_table(table, state) when is_list(table) do
    # Check if it's an array (sequential integer keys starting at 1)
    if array_table?(table) do
      table
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> Enum.map(fn {_k, v} -> decode_nested_value(v, state) end)
    else
      Map.new(table, fn {k, v} -> {decode_key(k), decode_nested_value(v, state)} end)
    end
  end

  defp decode_lua_table(other, _state), do: other

  # Decode nested values which may be lists (tables) or table refs
  defp decode_nested_value({:tref, _} = tref, state) do
    decoded = :luerl.decode(tref, state)
    decode_lua_table(decoded, state)
  end

  defp decode_nested_value(list, state) when is_list(list) do
    # This is an inline table, decode it
    decode_lua_table(list, state)
  end

  defp decode_nested_value(v, _state) when is_binary(v), do: v
  defp decode_nested_value(v, _state) when is_number(v), do: v
  defp decode_nested_value(v, _state) when is_boolean(v), do: v
  defp decode_nested_value(nil, _state), do: nil
  defp decode_nested_value(other, _state), do: inspect(other)

  defp decode_key(k) when is_binary(k), do: k
  defp decode_key(k) when is_number(k), do: trunc(k)
  defp decode_key(k), do: inspect(k)

  defp array_table?(table) when is_list(table) do
    keys = Enum.map(table, fn {k, _v} -> k end)

    if Enum.empty?(keys) do
      false
    else
      num_keys = length(keys)
      expected = Enum.to_list(1..num_keys)
      sorted_int_keys = keys |> Enum.map(&to_int_key/1) |> Enum.sort()
      sorted_int_keys == expected
    end
  end

  defp to_int_key(k) when is_integer(k), do: k
  defp to_int_key(k) when is_float(k), do: trunc(k)
  defp to_int_key(_), do: nil

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason) when is_atom(reason), do: Atom.to_string(reason)

  defp format_error({:lua_error, error, _stack}) do
    format_error(error)
  end

  defp format_error(reason), do: inspect(reason)
end
