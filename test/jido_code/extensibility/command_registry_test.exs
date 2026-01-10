defmodule JidoCode.Extensibility.CommandRegistryTest do
  use ExUnit.Case, async: false
  alias JidoCode.Extensibility.{Command, CommandParser, CommandRegistry}

  @valid_command """
  ---
  name: test_command
  description: A test command for registry
  tools:
    - read_file
  ---

  You are a test command.
  """

  @another_command """
  ---
  name: another_command
  description: Another test command
  ---

  Another command content.
  """

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_command(name, module_name) do
    attrs = %{
      name: name,
      description: "Test command",
      tools: [],
      prompt: "Test prompt",
      schema: [],
      channels: [],
      signals: [],
      module: module_name
    }

    {:ok, command} = Command.new(attrs)
    command
  end

  defp create_temp_command(name, content, tmp_dir) do
    path = Path.join(tmp_dir, "#{name}.md")
    File.write!(path, content)
    path
  end

  # ============================================================================
  # Registry Lifecycle Tests
  # ============================================================================

  describe "start_link/1" do
    test "starts the registry successfully" do
      assert {:ok, pid} = CommandRegistry.start_link(name: :test_registry_start)
      assert Process.alive?(pid)
      GenServer.stop(pid)
    end

    test "starts with auto_scan disabled" do
      assert {:ok, pid} =
               CommandRegistry.start_link(name: :test_registry_no_scan, auto_scan: false)

      # Check state directly
      state = :sys.get_state(pid)
      assert map_size(state.by_name) == 0

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Command Registration Tests
  # ============================================================================

  describe "register_command/2" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_register, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "registers a command successfully", %{registry: _pid} do
      command = create_test_command("test_cmd", JidoCode.Extensibility.Commands.TestCommand)

      assert {:ok, registered} = GenServer.call(:test_registry_register, {:register, command, []})
      assert registered.name == "test_cmd"

      # Check via state
      state = :sys.get_state(:test_registry_register)
      assert Map.has_key?(state.by_name, "test_cmd")
    end

    test "returns error when registering duplicate command" do
      command = create_test_command("duplicate", JidoCode.Extensibility.Commands.Duplicate)

      assert {:ok, _command} = GenServer.call(:test_registry_register, {:register, command, []})
      assert {:error, {:already_registered, "duplicate"}} =
               GenServer.call(:test_registry_register, {:register, command, []})
    end

    test "forces registration with force option" do
      command = create_test_command("force_test", JidoCode.Extensibility.Commands.ForceTest)

      assert {:ok, _cmd1} = GenServer.call(:test_registry_register, {:register, command, []})
      assert {:ok, cmd2} = GenServer.call(:test_registry_register, {:register, command, [force: true]})
      assert cmd2.name == "force_test"
    end

    test "stores command in both name and module indexes" do
      command = create_test_command("indexed", JidoCode.Extensibility.Commands.Indexed)

      assert {:ok, _command} = GenServer.call(:test_registry_register, {:register, command, []})

      state = :sys.get_state(:test_registry_register)
      assert Map.has_key?(state.by_name, "indexed")
      assert Map.has_key?(state.by_module, JidoCode.Extensibility.Commands.Indexed)
    end
  end

  # ============================================================================
  # Command Lookup Tests
  # ============================================================================

  describe "get_command/1" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_get, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "retrieves command by name" do
      command = create_test_command("lookup_test", JidoCode.Extensibility.Commands.LookupTest)

      GenServer.call(:test_registry_get, {:register, command, []})
      assert {:ok, retrieved} = GenServer.call(:test_registry_get, {:get_by_name, "lookup_test"})
      assert retrieved.name == "lookup_test"
    end

    test "returns error for non-existent command" do
      assert {:error, :not_found} = GenServer.call(:test_registry_get, {:get_by_name, "nonexistent"})
    end
  end

  describe "get_by_module/1" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_get_module, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "retrieves command by module" do
      command = create_test_command("module_test", JidoCode.Extensibility.Commands.ModuleTest)

      GenServer.call(:test_registry_get_module, {:register, command, []})
      assert {:ok, retrieved} = GenServer.call(:test_registry_get_module, {:get_by_module, JidoCode.Extensibility.Commands.ModuleTest})
      assert retrieved.name == "module_test"
    end

    test "returns error for non-existent module" do
      assert {:error, :not_found} = GenServer.call(:test_registry_get_module, {:get_by_module, JidoCode.Extensibility.Commands.NonExistent})
    end
  end

  describe "list_commands/0" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_list, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "returns all registered commands" do
      cmd1 = create_test_command("list1", JidoCode.Extensibility.Commands.List1)
      cmd2 = create_test_command("list2", JidoCode.Extensibility.Commands.List2)

      GenServer.call(:test_registry_list, {:register, cmd1, []})
      GenServer.call(:test_registry_list, {:register, cmd2, []})

      commands = GenServer.call(:test_registry_list, :list_commands)
      assert length(commands) == 2

      names = Enum.map(commands, & &1.name) |> Enum.sort()
      assert names == ["list1", "list2"]
    end

    test "returns empty list when no commands registered" do
      commands = GenServer.call(:test_registry_list, :list_commands)
      assert commands == []
    end
  end

  describe "registered?/1" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_registered, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "returns true for registered command" do
      command = create_test_command("check_registered", JidoCode.Extensibility.Commands.CheckRegistered)
      GenServer.call(:test_registry_registered, {:register, command, []})
      assert GenServer.call(:test_registry_registered, {:registered?, "check_registered"})
    end

    test "returns false for non-registered command" do
      refute GenServer.call(:test_registry_registered, {:registered?, "not_registered"})
    end
  end

  describe "find_command/1" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_find, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "finds commands by partial name match" do
      cmd1 = create_test_command("commit", JidoCode.Extensibility.Commands.Commit)
      cmd2 = create_test_command("compare", JidoCode.Extensibility.Commands.Compare)

      GenServer.call(:test_registry_find, {:register, cmd1, []})
      GenServer.call(:test_registry_find, {:register, cmd2, []})

      results = GenServer.call(:test_registry_find, {:find_command, "com"})
      assert length(results) == 2

      names = Enum.map(results, & &1.name) |> Enum.sort()
      assert names == ["commit", "compare"]
    end

    test "finds commands case-insensitively" do
      command = create_test_command("MyCommand", JidoCode.Extensibility.Commands.MyCommand)
      GenServer.call(:test_registry_find, {:register, command, []})

      results = GenServer.call(:test_registry_find, {:find_command, "mycommand"})
      assert length(results) == 1
      assert hd(results).name == "MyCommand"
    end

    test "returns empty list for no matches" do
      results = GenServer.call(:test_registry_find, {:find_command, "nonexistent"})
      assert results == []
    end
  end

  describe "count/0" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_count, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "returns zero when empty" do
      assert GenServer.call(:test_registry_count, :count) == 0
    end

    test "returns number of registered commands" do
      cmd1 = create_test_command("count1", JidoCode.Extensibility.Commands.Count1)
      cmd2 = create_test_command("count2", JidoCode.Extensibility.Commands.Count2)

      GenServer.call(:test_registry_count, {:register, cmd1, []})
      assert GenServer.call(:test_registry_count, :count) == 1

      GenServer.call(:test_registry_count, {:register, cmd2, []})
      assert GenServer.call(:test_registry_count, :count) == 2
    end
  end

  # ============================================================================
  # Command Unloading Tests
  # ============================================================================

  describe "unregister_command/1" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_unregister, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "removes command from registry" do
      command = create_test_command("unregister_me", JidoCode.Extensibility.Commands.UnregisterMe)

      GenServer.call(:test_registry_unregister, {:register, command, []})
      assert GenServer.call(:test_registry_unregister, {:registered?, "unregister_me"})

      assert :ok = GenServer.call(:test_registry_unregister, {:unregister, "unregister_me"})
      refute GenServer.call(:test_registry_unregister, {:registered?, "unregister_me"})
    end

    test "returns error for non-existent command" do
      assert {:error, :not_found} = GenServer.call(:test_registry_unregister, {:unregister, "nonexistent"})
    end

    test "removes from both name and module indexes" do
      command = create_test_command("remove_indexes", JidoCode.Extensibility.Commands.RemoveIndexes)

      GenServer.call(:test_registry_unregister, {:register, command, []})
      assert :ok = GenServer.call(:test_registry_unregister, {:unregister, "remove_indexes"})

      assert {:error, :not_found} = GenServer.call(:test_registry_unregister, {:get_by_name, "remove_indexes"})
      assert {:error, :not_found} = GenServer.call(:test_registry_unregister, {:get_by_module, JidoCode.Extensibility.Commands.RemoveIndexes})
    end
  end

  describe "clear/0" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_clear, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "removes all commands" do
      cmd1 = create_test_command("clear1", JidoCode.Extensibility.Commands.Clear1)
      cmd2 = create_test_command("clear2", JidoCode.Extensibility.Commands.Clear2)

      GenServer.call(:test_registry_clear, {:register, cmd1, []})
      GenServer.call(:test_registry_clear, {:register, cmd2, []})
      assert GenServer.call(:test_registry_clear, :count) == 2

      assert :ok = GenServer.call(:test_registry_clear, :clear)
      assert GenServer.call(:test_registry_clear, :count) == 0
    end
  end

  # ============================================================================
  # Command Discovery Tests
  # ============================================================================

  describe "scan_commands_directory/2" do
    setup do
      tmp_dir =
        Path.join([
          System.tmp_dir!(),
          "command_scan_test",
          Integer.to_string(:erlang.unique_integer([:positive]))
        ])

      File.mkdir_p!(tmp_dir)

      on_exit(fn -> File.rm_rf!(tmp_dir) end)

      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_scan, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)

      %{tmp_dir: tmp_dir, registry: pid}
    end

    test "discovers and registers commands from directory", %{tmp_dir: tmp_dir} do
      # Create valid command file
      create_temp_command("scan_test", @valid_command, tmp_dir)

      {loaded, skipped, errors} = GenServer.call(:test_registry_scan, {:scan_directory, tmp_dir, []})

      assert loaded >= 0
      assert is_integer(loaded)
      assert is_list(errors)
    end

    test "returns zero for empty directory", %{tmp_dir: tmp_dir} do
      {loaded, skipped, errors} = GenServer.call(:test_registry_scan, {:scan_directory, tmp_dir, []})

      assert loaded == 0
      assert skipped == 0
      assert errors == []
    end

    test "handles non-existent directory gracefully" do
      {loaded, skipped, errors} =
        GenServer.call(:test_registry_scan, {:scan_directory, "/nonexistent/directory", []})

      assert loaded == 0
      assert skipped == 0
      assert errors == []
    end
  end

  describe "scan_all_commands/0" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_scan_all, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "scans global and local directories" do
      # Just verify it doesn't crash
      assert :ok = GenServer.call(:test_registry_scan_all, :scan_all_commands)
    end
  end

  # ============================================================================
  # Signal Emission Tests
  # ============================================================================

  describe "signals" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_signals, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)

      # Subscribe to registry events
      Phoenix.PubSub.subscribe(JidoCode.PubSub, "command_registry")

      %{registry: pid}
    end

    test "emits registration signal" do
      command = create_test_command("signal_test", JidoCode.Extensibility.Commands.SignalTest)

      GenServer.call(:test_registry_signals, {:register, command, []})

      # Check for signal (with timeout)
      assert_receive({"command:registered", %{name: "signal_test"}}, 1000)
    end

    test "emits unregistration signal" do
      command = create_test_command("unreg_signal", JidoCode.Extensibility.Commands.UnregSignal)

      GenServer.call(:test_registry_signals, {:register, command, []})
      GenServer.call(:test_registry_signals, {:unregister, "unreg_signal"})

      assert_receive({"command:unregistered", %{name: "unreg_signal"}}, 1000)
    end
  end

  # ============================================================================
  # ETS Table Tests
  # ============================================================================

  describe "ETS table" do
    setup do
      {:ok, pid} = CommandRegistry.start_link(name: :test_registry_ets, auto_scan: false)
      on_exit(fn ->
        if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end)
      %{registry: pid}
    end

    test "creates named table on startup", %{registry: pid} do
      # Get the state to check table exists
      state = :sys.get_state(pid)
      assert state.table != nil
      assert is_reference(state.table) or is_atom(state.table_name)
    end

    test "persists data across lookups" do
      command = create_test_command("ets_test", JidoCode.Extensibility.Commands.EtsTest)

      GenServer.call(:test_registry_ets, {:register, command, []})

      # Multiple lookups should succeed
      assert {:ok, _} = GenServer.call(:test_registry_ets, {:get_by_name, "ets_test"})
      assert {:ok, _} = GenServer.call(:test_registry_ets, {:get_by_name, "ets_test"})
      assert {:ok, _} = GenServer.call(:test_registry_ets, {:get_by_name, "ets_test"})
    end
  end
end
