defmodule JidoCode.Extensibility.CommandDispatcher do
  @moduledoc """
  Dispatch and execute registered slash commands.

  The CommandDispatcher handles the execution of commands parsed by SlashParser,
  looking them up in the CommandRegistry and executing their associated Jido.Action
  modules with proper context, signals, and channel broadcasting.

  ## Features

  - Command lookup from CommandRegistry
  - Execution context building with tools, model, channels, and signals
  - Signal emission for command lifecycle events (started, completed, failed)
  - Channel broadcasting for command status updates
  - Error handling for missing and failed commands

  ## Lifecycle

  When a command is dispatched:

  1. **Lookup** - Find command by name in CommandRegistry
  2. **Build Context** - Create execution context from command config
  3. **Emit Started** - Broadcast `command_started` signal
  4. **Execute** - Call the Jido.Action with params and context
  5. **Emit Completed** - Broadcast `command_completed` or `command_failed`
  6. **Return Result** - Return success or error to caller

  ## Signals

  The dispatcher emits the following signals:

  - `{"command:started", %{command: name, params: params}}`
  - `{"command:completed", %{command: name, result: result}}`
  - `{"command:failed", %{command: name, error: reason}}`

  ## Examples

      # Dispatch a parsed slash command
      {:ok, parsed} = SlashParser.parse("/commit -m \"fix bug\"")
      {:ok, result} = CommandDispatcher.dispatch(parsed, context)

      # Handle missing command
      {:error, {:not_found, "unknown"}} = CommandDispatcher.dispatch(
        %ParsedCommand{command: "unknown"},
        context
      )

  """

  alias JidoCode.Extensibility.{SlashParser, CommandRegistry, Command}
  alias Jido.Agent.ExecPlan

  @type context :: map()
  @type dispatch_result :: {:ok, term()} | {:error, term()}

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Dispatch a parsed slash command for execution.

  ## Parameters

  - `parsed_command` - A `%SlashParser.ParsedCommand{}` from SlashParser.parse/1
  - `context` - Execution context map (optional, defaults to %{})

  ## Returns

  - `{:ok, result}` - Command executed successfully
  - `{:error, {:not_found, name}}` - Command not registered
  - `{:error, {:execution_failed, reason}}` - Command execution failed
  - `{:error, {:invalid_command, reason}}` - Command validation failed

  ## Examples

      iex> {:ok, parsed} = SlashParser.parse("/commit")
      iex> CommandDispatcher.dispatch(parsed, %{})
      {:ok, %{committed: true}}

      iex> {:ok, parsed} = SlashParser.parse("/unknown")
      iex> CommandDispatcher.dispatch(parsed, %{})
      {:error, {:not_found, "unknown"}}

  """
  @spec dispatch(SlashParser.ParsedCommand.t(), context()) :: dispatch_result()
  def dispatch(%SlashParser.ParsedCommand{} = parsed_command, context \\ %{}) do
    command_name = parsed_command.command

    # Look up command in registry
    case CommandRegistry.get_command(command_name) do
      {:ok, %Command{} = command} ->
        execute_command(command, parsed_command, context)

      {:error, :not_found} ->
        emit_signal("command:failed", %{
          command: command_name,
          error: :not_found
        })

        {:error, {:not_found, command_name}}
    end
  end

  @doc """
  Dispatch a slash command string directly.

  Convenience function that parses and dispatches in one step.

  ## Parameters

  - `slash_command` - A slash command string (e.g., "/commit -m \"fix\"")
  - `context` - Execution context map (optional, defaults to %{})

  ## Returns

  - `{:ok, result}` - Command executed successfully
  - `{:error, {:parse_error, reason}}` - Failed to parse command
  - `{:error, {:not_found, name}}` - Command not registered
  - `{:error, {:execution_failed, reason}}` - Command execution failed

  ## Examples

      iex> CommandDispatcher.dispatch_string("/commit")
      {:ok, %{committed: true}}

      iex> CommandDispatcher.dispatch_string("not a slash command")
      {:error, {:parse_error, :not_a_slash_command}}

  """
  @spec dispatch_string(String.t(), context()) :: dispatch_result()
  def dispatch_string(slash_command, context \\ %{}) when is_binary(slash_command) do
    case SlashParser.parse(slash_command) do
      {:ok, parsed} ->
        dispatch(parsed, context)

      {:error, reason} ->
        {:error, {:parse_error, reason}}
    end
  end

  @doc """
  Build execution context for a command.

  Combines the provided context with command-specific configuration
  including tools, model override, channels, and signals.

  ## Parameters

  - `command` - The `%Command{}` struct
  - `base_context` - Base execution context to extend

  ## Returns

  - A map containing the execution context

  """
  @spec build_context(Command.t(), map()) :: map()
  def build_context(%Command{} = command, base_context \\ %{}) do
    base_context
    |> Map.put(:command_name, command.name)
    |> Map.put(:command_tools, command.tools)
    |> Map.put(:command_model, command.model)
    |> Map.put(:command_channels, normalize_channels(command.channels))
    |> Map.put(:command_signals, normalize_signals(command.signals))
    |> Map.put(:command_source_path, command.source_path)
    |> add_tool_permissions(command.tools)
    |> add_model_override(command.model)
  end

  # ============================================================================
  # Private Functions - Command Execution
  # ============================================================================

  defp execute_command(%Command{} = command, %SlashParser.ParsedCommand{} = parsed, context) do
    # Build execution context
    exec_context = build_context(command, context)

    # Build params from parsed command (merge args and flags into params)
    params = build_params(command, parsed)

    # Emit started signal
    emit_signal("command:started", %{
      command: command.name,
      params: params
    })

    # Broadcast to channels
    broadcast_execution(command, :started, params, exec_context)

    # Execute the action
    case execute_action(command, params, exec_context) do
      {:ok, result} ->
        # Emit completed signal
        emit_signal("command:completed", %{
          command: command.name,
          result: result
        })

        # Broadcast completion
        broadcast_execution(command, :completed, result, exec_context)

        {:ok, result}

      {:error, reason} = error ->
        # Emit failed signal
        emit_signal("command:failed", %{
          command: command.name,
          error: reason
        })

        # Broadcast failure
        broadcast_execution(command, :failed, reason, exec_context)

        error
    end
  end

  defp execute_action(%Command{module: nil}, _params, _context) do
    {:error, {:execution_failed, :no_module}}
  end

  defp execute_action(%Command{module: module}, params, context) do
    # Ensure the module is loaded and has run/2
    if Code.ensure_loaded?(module) and function_exported?(module, :run, 2) do
      try do
        # Execute the Jido.Action
        case module.run(params, context) do
          {:error, reason} ->
            # Wrap error as execution failure (unwrap inner error tuple)
            {:error, {:execution_failed, reason}}

          ok_result ->
            ok_result
        end
      rescue
        error ->
          {:error, {:execution_failed, error}}
      end
    else
      {:error, {:execution_failed, :module_not_ready}}
    end
  end

  # ============================================================================
  # Private Functions - Parameter Building
  # ============================================================================

  defp build_params(%Command{schema: schema}, %SlashParser.ParsedCommand{
         args: args,
         flags: flags
       }) do
    # Start with flags (named parameters)
    base_params =
      Enum.reduce(flags, %{}, fn {key, value}, acc ->
        # Convert flag name to atom if possible
        atom_key = maybe_to_atom(key)
        Map.put(acc, atom_key, value)
      end)

    # Add positional args based on schema order
    add_positional_args(base_params, args, schema)
  end

  # Add positional args in schema order
  defp add_positional_args(params, [], _schema), do: params

  defp add_positional_args(params, args, []) do
    # Empty schema - add args as :args
    Map.put(params, :args, args)
  end

  defp add_positional_args(params, args, schema) when is_list(schema) do
    # Get required/optional param names in order
    param_names =
      schema
      |> Enum.filter(fn
        {_name, opts} when is_list(opts) -> true
        _ -> false
      end)
      |> Enum.map(fn {name, _opts} -> name end)

    # If no param names found, add as :args
    if param_names == [] do
      Map.put(params, :args, args)
    else
      # Assign args to param names by position
      {positional_params, _remaining_args} =
        Enum.zip_reduce(param_names, args, {%{}, []}, fn name, arg, {acc, _} ->
          {Map.put(acc, name, arg), %{}}
        end)

      Map.merge(params, positional_params)
    end
  end

  defp add_positional_args(params, args, _schema), do: Map.put(params, :args, args)

  # ============================================================================
  # Private Functions - Context Building
  # ============================================================================

  defp add_tool_permissions(context, tools) when is_list(tools) do
    Map.put(context, :allowed_tools, tools)
  end

  defp add_tool_permissions(context, _tools), do: context

  defp add_model_override(context, nil), do: context
  defp add_model_override(context, model) when is_binary(model), do: Map.put(context, :model, model)
  defp add_model_override(context, _model), do: context

  defp normalize_channels(channels) when is_list(channels), do: channels
  defp normalize_channels(%{broadcast_to: channels} = config) when is_list(channels), do: config
  defp normalize_channels(%{} = channels), do: channels
  defp normalize_channels(_), do: []

  defp normalize_signals(signals) when is_list(signals), do: signals
  defp normalize_signals(%{emit: types} = signals) when is_list(types), do: signals
  defp normalize_signals(%{} = signals), do: signals
  defp normalize_signals(_), do: []

  # ============================================================================
  # Private Functions - Signal Emission
  # ============================================================================

  defp emit_signal(type, data) do
    try do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, "command_dispatcher", {type, data})
    rescue
      _ -> :ok
    end
  end

  # ============================================================================
  # Private Functions - Channel Broadcasting
  # ============================================================================

  defp broadcast_execution(%Command{channels: channels}, status, data, context) do
    broadcast_channels = normalize_channels(channels)

    payload = %{
      status: status,
      data: data,
      context: context,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Enum.each(broadcast_channels, fn channel ->
      broadcast_to_channel(channel, payload)
    end)
  end

  defp broadcast_to_channel(channel_name, payload) when is_binary(channel_name) do
    try do
      Phoenix.PubSub.broadcast(JidoCode.PubSub, channel_name, {:command_event, payload})
    rescue
      _ -> :ok
    end
  end

  defp broadcast_to_channel(_channel, _payload), do: :ok

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp maybe_to_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> String.to_atom(key)
    end
  end

  defp maybe_to_atom(key), do: key
end
