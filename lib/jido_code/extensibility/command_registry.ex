defmodule JidoCode.Extensibility.CommandRegistry do
  @moduledoc """
  Registry for managing dynamically loaded commands.

  The CommandRegistry maintains a collection of commands loaded from markdown
  files, providing fast lookups via ETS tables and supporting automatic
  discovery from predefined directories.

  ## Features

  - ETS-backed storage for O(1) command lookups
  - Dual indexing by name and module
  - Automatic command discovery from directories
  - Fuzzy search support
  - Signal emission on registry changes

  ## Registry Structure

  ```elixir
  %CommandRegistry{
    by_name: %{
      "commit" => %Command{name: "commit", ...}
    },
    by_module: %{
      JidoCode.Extensibility.Commands.Commit => %Command{...}
    },
    table: :ets_tid(...)
  }
  ```

  ## Command Directories

  Commands are automatically discovered from:
  - Global: `~/.jido_code/commands/*.md`
  - Local: `.jido_code/commands/*.md` (overrides global)

  ## Signals

  The registry emits the following signals:
  - `{"command:registered", %{name: name, command: command}}`
  - `{"command:unregistered", %{name: name}}`

  ## Examples

  ```elixir
  # Start the registry
  {:ok, pid} = CommandRegistry.start_link([])

  # Register a command manually
  {:ok, command} = CommandParser.parse_file("/path/to/command.md")
  {:ok, module} = CommandParser.generate_module(command)
  {:ok, registered} = CommandRegistry.register_command(%{command | module: module})

  # Look up by name
  {:ok, command} = CommandRegistry.get_command("commit")

  # Look up by module
  {:ok, command} = CommandRegistry.get_by_module(JidoCode.Extensibility.Commands.Commit)

  # List all commands
  commands = CommandRegistry.list_commands()

  # Fuzzy search
  results = CommandRegistry.find_command("com")  # => [%Command{name: "commit"}, ...]

  # Discover and load from directories
  {loaded, skipped, errors} = CommandRegistry.scan_all_commands()

  # Unregister a command
  :ok = CommandRegistry.unregister_command("commit")
  ```

  """

  use GenServer
  alias JidoCode.Extensibility.{Command, CommandParser}

  @type name :: String.t()
  @type module_ref :: module()
  @type command :: Command.t()

  @table_name :jido_command_registry
  @global_commands_dir Path.expand("~/.jido_code/commands")
  @local_commands_dir ".jido_code/commands"

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts the CommandRegistry.

  ## Options

  - `:name` - The name to register the GenServer (default: `CommandRegistry`)
  - `:global_dir` - Global commands directory (default: `~/.jido_code/commands`)
  - `:local_dir` - Local commands directory (default: `.jido_code/commands`)
  - `:auto_scan` - Whether to automatically scan for commands on start (default: `true`)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    gen_opts = [name: name]
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Registers a command in the registry.

  If a command with the same name already exists, returns `{:error, {:already_registered, name}}`
  unless `force: true` is provided.

  ## Options

  - `:force` - Replace existing command with same name (default: `false`)

  """
  @spec register_command(command(), keyword()) :: {:ok, command()} | {:error, term()}
  def register_command(%Command{} = command, opts \\ []) do
    GenServer.call(__MODULE__, {:register, command, opts})
  end

  @doc """
  Retrieves a command by name.

  """
  @spec get_command(name()) :: {:ok, command()} | {:error, :not_found}
  def get_command(name) when is_binary(name) do
    GenServer.call(__MODULE__, {:get_by_name, name})
  end

  @doc """
  Retrieves a command by its module.

  """
  @spec get_by_module(module_ref()) :: {:ok, command()} | {:error, :not_found}
  def get_by_module(module) when is_atom(module) do
    GenServer.call(__MODULE__, {:get_by_module, module})
  end

  @doc """
  Lists all registered commands.

  Returns a list of `%Command{}` structs.

  """
  @spec list_commands() :: [command()]
  def list_commands do
    GenServer.call(__MODULE__, :list_commands)
  end

  @doc """
  Checks if a command is registered by name.

  """
  @spec registered?(name()) :: boolean()
  def registered?(name) when is_binary(name) do
    GenServer.call(__MODULE__, {:registered?, name})
  end

  @doc """
  Finds commands by fuzzy name matching.

  Performs a case-insensitive substring search on command names.

  ## Examples

      iex> CommandRegistry.find_command("com")
      [%Command{name: "commit"}, %Command{name: "compare"}]

      iex> CommandRegistry.find_command("nonexistent")
      []

  """
  @spec find_command(String.t()) :: [command()]
  def find_command(pattern) when is_binary(pattern) do
    GenServer.call(__MODULE__, {:find_command, pattern})
  end

  @doc """
  Scans a directory for markdown command files and registers them.

  Returns `{loaded_count, skipped_count, errors}`.

  ## Options

  - `:override` - Allow local commands to override global ones (default: `true`)

  """
  @spec scan_commands_directory(Path.t(), keyword()) :: {non_neg_integer(), non_neg_integer(), [term()]}
  def scan_commands_directory(dir, opts \\ []) do
    GenServer.call(__MODULE__, {:scan_directory, dir, opts})
  end

  @doc """
  Scans both global and local command directories.

  Global: `~/.jido_code/commands/*.md`
  Local: `.jido_code/commands/*.md`

  Local commands override global commands with the same name.

  Returns `{loaded_count, skipped_count, errors}`.

  """
  @spec scan_all_commands(keyword()) :: {non_neg_integer(), non_neg_integer(), [term()]}
  def scan_all_commands(opts \\ []) do
    GenServer.call(__MODULE__, :scan_all_commands)
  end

  @doc """
  Unregisters a command by name.

  Removes the command from all indexes and the ETS table.

  """
  @spec unregister_command(name()) :: :ok | {:error, :not_found}
  def unregister_command(name) when is_binary(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  @doc """
  Returns the count of registered commands.

  """
  @spec count() :: non_neg_integer()
  def count do
    GenServer.call(__MODULE__, :count)
  end

  @doc """
  Clears all commands from the registry.

  Useful for testing or complete reloads.

  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    global_dir = Keyword.get(opts, :global_dir, @global_commands_dir)
    local_dir = Keyword.get(opts, :local_dir, @local_commands_dir)
    auto_scan = Keyword.get(opts, :auto_scan, true)

    # Create unique table name for this registry instance
    table_name = :"#{__MODULE__}_#{:erlang.unique_integer()}"

    # Create ETS table for fast lookups
    table =
      :ets.new(table_name, [
        :set,
        :named_table,
        :protected,
        read_concurrency: true
      ])

    state = %{
      by_name: %{},
      by_module: %{},
      table: table,
      table_name: table_name,
      global_dir: global_dir,
      local_dir: local_dir
    }

    # Auto-scan if enabled
    state =
      if auto_scan do
        scan_all_directories(state)
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def handle_call({:register, %Command{name: name} = command, opts}, _from, state) do
    force = Keyword.get(opts, :force, false)

    case Map.get(state.by_name, name) do
      nil ->
        {:reply, do_register_command(command, state), update_state(state, command)}

      existing when force == true ->
        # Unregister existing first
        state = do_unregister_command(name, state)
        {:reply, do_register_command(command, state), update_state(state, command)}

      _existing ->
        {:reply, {:error, {:already_registered, name}}, state}
    end
  end

  def handle_call({:get_by_name, name}, _from, state) do
    case Map.get(state.by_name, name) do
      nil -> {:reply, {:error, :not_found}, state}
      command -> {:reply, {:ok, command}, state}
    end
  end

  def handle_call({:get_by_module, module}, _from, state) do
    case Map.get(state.by_module, module) do
      nil -> {:reply, {:error, :not_found}, state}
      command -> {:reply, {:ok, command}, state}
    end
  end

  def handle_call(:list_commands, _from, state) do
    commands = Map.values(state.by_name)
    {:reply, commands, state}
  end

  def handle_call({:registered?, name}, _from, state) do
    {:reply, Map.has_key?(state.by_name, name), state}
  end

  def handle_call({:find_command, pattern}, _from, state) do
    results =
      state.by_name
      |> Enum.filter(fn {name, _command} ->
        String.contains?(String.downcase(name), String.downcase(pattern))
      end)
      |> Enum.map(fn {_name, command} -> command end)

    {:reply, results, state}
  end

  def handle_call({:scan_directory, dir, opts}, _from, state) do
    {loaded, skipped, errors, new_state} = do_scan_directory(dir, state, opts)
    {:reply, {loaded, skipped, errors}, new_state}
  end

  def handle_call(:scan_all_commands, _from, state) do
    new_state = scan_all_directories(state)
    {:reply, :ok, new_state}
  end

  def handle_call({:unregister, name}, _from, state) do
    case Map.get(state.by_name, name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _command ->
        new_state = do_unregister_command(name, state)
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:count, _from, state) do
    {:reply, map_size(state.by_name), state}
  end

  def handle_call(:clear, _from, state) do
    # Clear ETS table
    :ets.delete_all_objects(state.table_name)

    new_state = %{
      state
      | by_name: %{},
        by_module: %{}
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Clean up ETS table
    try do
      :ets.delete(state.table_name)
    rescue
      _ -> :ok
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_register_command(%Command{name: name, module: module} = command, state) do
    # Store in ETS table for fast lookups
    :ets.insert(state.table_name, {name, command})
    :ets.insert(state.table_name, {module, command})

    # Emit registration signal
    emit_signal("command:registered", %{name: name, command: command})

    {:ok, command}
  end

  defp update_state(state, %Command{name: name, module: module} = command) do
    %{state |
      by_name: Map.put(state.by_name, name, command),
      by_module: Map.put(state.by_module, module, command)
    }
  end

  defp do_unregister_command(name, state) do
    case Map.get(state.by_name, name) do
      nil ->
        state

      %Command{module: module} ->
        # Remove from ETS
        :ets.delete(state.table_name, name)
        :ets.delete(state.table_name, module)

        # Emit signal
        emit_signal("command:unregistered", %{name: name})

        %{state |
          by_name: Map.delete(state.by_name, name),
          by_module: Map.delete(state.by_module, module)
        }
    end
  end

  defp scan_all_directories(state) do
    # Scan global directory first
    state = do_scan_directory_safe(state.global_dir, state, override: false)

    # Then scan local directory (can override global)
    state = do_scan_directory_safe(state.local_dir, state, override: true)

    state
  end

  defp do_scan_directory_safe(dir, state, opts) do
    if File.dir?(dir) do
      {loaded, _skipped, _errors, new_state} = do_scan_directory(dir, state, opts)
      new_state
    else
      state
    end
  rescue
    _ -> state
  end

  defp do_scan_directory(dir, state, opts \\ []) do
    override = Keyword.get(opts, :override, true)

    pattern = Path.join(dir, "*.md")

    case Path.wildcard(pattern) do
      [] ->
        {0, 0, [], state}

      files ->
        Enum.reduce(files, {0, 0, [], state}, fn file, {loaded, skipped, errors, acc_state} ->
          case load_command_file(file, acc_state, override) do
            {:ok, new_state} ->
              {loaded + 1, skipped, errors, new_state}

            {:skip, new_state} ->
              {loaded, skipped + 1, errors, new_state}

            {:error, reason, new_state} ->
              {loaded, skipped, [{file, reason} | errors], new_state}
          end
        end)
    end
  end

  defp load_command_file(file_path, state, override) do
    with {:ok, %Command{} = command} <- CommandParser.parse_file(file_path),
         {:ok, module} <- CommandParser.generate_module(command),
         command_with_module <- %{command | module: module, source_path: file_path},
         {:ok, _command} <- register_or_skip(command_with_module, state, override) do
      {:ok, state}
    else
      {:error, reason} ->
        # Parse or generate failed
        {:error, reason, state}

      {:skip, _state} = result ->
        result
    end
  end

  defp register_or_skip(%Command{name: name} = command, state, override) do
    case Map.get(state.by_name, name) do
      nil ->
        # Not registered, register it
        do_register_command(command, state)
        {:ok, update_state(state, command)}

      _existing when override == true ->
        # Override existing
        do_register_command(command, state)
        {:ok, update_state(state, command)}

      _existing ->
        # Skip (don't override)
        {:skip, state}
    end
  end

  defp emit_signal(type, data) do
    # Emit signal via Jido.Signal if available
    # For now, we'll use Phoenix.PubSub which is already a dependency
    try do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "command_registry", {type, data})
    rescue
      _ -> :ok
    end
  end
end
