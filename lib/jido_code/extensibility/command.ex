defmodule JidoCode.Extensibility.Command do
  @moduledoc """
  Command struct and macro for defining Jido.Action-compliant commands.

  Commands are discrete actions that can be invoked via slash commands
  or signal routing. This module provides:

  1. **Command struct** - Holds parsed command definition from markdown
  2. **`__using__/1` macro** - Generates Jido.Action-compliant modules

  ## Command Struct

  The Command struct represents a parsed command definition:

      %__MODULE__{
        name: "commit",
        description: "Create git commit",
        module: MyCommandModule,
        model: "anthropic:claude-sonnet-4-20250514",
        tools: ["read_file", "grep"],
        prompt: "You are a commit message generator...",
        schema: [...],
        channels: %{broadcast_to: ["ui_state"]},
        signals: %{emit: ["command.completed"]},
        source_path: "/path/to/command.md"
      }

  ## Using the Macro

  To define a command module, use the macro:

      defmodule MyCommand do
        use JidoCode.Extensibility.Command,
          name: "my_command",
          description: "My specialized command",
          schema: [message: [type: :string, required: true]],
          system_prompt: "You are helpful.",
          tools: [:read_file],
          channels: [broadcast_to: ["ui_state"]],
          signals: [emit: ["command.done"]]
      end

  This creates a Jido.Action-compliant module with:
  - Action schema (NimbleOptions format)
  - System prompt storage
  - Tool restrictions
  - Channel broadcasting integration
  - Signal emit configuration

  ## Example

  A minimal command definition:

      defmodule CommitCommand do
        use JidoCode.Extensibility.Command,
          name: "commit",
          description: "Create a git commit",
          schema: [
            message: [type: :string, required: false],
            amend: [type: :boolean, default: false]
          ],
          system_prompt: "You generate commit messages."
      end

  With a more complete configuration:

      defmodule ReviewCommand do
        use JidoCode.Extensibility.Command,
          name: "code_review",
          description: "Review code for security issues",
          schema: [
            file: [type: :string, required: true],
            focus: [type: {:in, [:security, :performance, :style]}, default: :security]
          ],
          system_prompt: "You are a code reviewer.",
          tools: [:read_file, :grep],
          signals: [
            emit: ["review.started", "review.completed"]
          ]
      end
  """

  alias Jido.Agent.Directive
  alias Jido.Signal

  # ============================================================================
  # Command Struct
  # ============================================================================

  @schema Zoi.struct(
            __MODULE__,
            %{
              name:
                Zoi.string(description: "Command identifier (unique, kebab-case)")
                |> Zoi.optional(),

              description:
                Zoi.string(description: "Human-readable command description")
                |> Zoi.optional(),

              module:
                Zoi.atom(description: "Generated Jido.Action module")
                |> Zoi.optional(),

              model:
                Zoi.string(description: "LLM model identifier")
                |> Zoi.optional(),

              tools:
                Zoi.list(Zoi.string(), description: "Allowed tool names")
                |> Zoi.optional()
                |> Zoi.default([]),

              prompt:
                Zoi.string(description: "System prompt from markdown body")
                |> Zoi.default(""),

              schema:
                Zoi.any(description: "NimbleOptions schema for parameters")
                |> Zoi.optional()
                |> Zoi.default([]),

              channels:
                Zoi.any(description: "Channel broadcasting configuration")
                |> Zoi.optional()
                |> Zoi.default([]),

              signals:
                Zoi.any(description: "Signal emit/subscribe configuration")
                |> Zoi.optional()
                |> Zoi.default([]),

              source_path:
                Zoi.string(description: "Path to source markdown file")
                |> Zoi.optional()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  def schema, do: @schema

  # ============================================================================
  # Macro
  # ============================================================================

  @doc """
  Defines a Jido.Action-compliant command module.

  ## Options

  - `:name` (required) - Command name (kebab-case)
  - `:description` (required) - Command description
  - `:schema` (optional) - NimbleOptions schema for parameters
  - `:system_prompt` (optional) - System prompt text
  - `:tools` (optional) - List of allowed tool names (default: [])
  - `:channels` (optional) - Channel broadcasting configuration
  - `:signals` (optional) - Signal emit configuration

  ## Generated Module

  The macro generates a module that:
  - Uses `Jido.Action` with the provided configuration
  - Stores system_prompt, tools, channels, signals as module attributes
  - Implements `run/2` with signal emission
  - Provides accessor functions

  ## Examples

      defmodule MyCommand do
        use JidoCode.Extensibility.Command,
          name: "my_command",
          description: "My specialized command",
          schema: [value: [type: :integer, default: 0]]
      end
  """
  defmacro __using__(opts) do
    # Extract and validate options at compile time
    name = Keyword.fetch!(opts, :name)
    description = Keyword.fetch!(opts, :description)
    system_prompt = Keyword.get(opts, :system_prompt, "")
    tools = Keyword.get(opts, :tools, [])
    channels = Keyword.get(opts, :channels, [])
    signals = Keyword.get(opts, :signals, [])
    schema = Keyword.get(opts, :schema, [])

    quote location: :keep do
      use Jido.Action,
        name: unquote(name),
        description: unquote(description),
        schema: unquote(schema)

      alias Jido.Agent.Directive
      alias Jido.Signal

      # Store module attributes for runtime access
      @command_system_prompt unquote(system_prompt)
      @command_tools unquote(Macro.escape(tools))
      @command_channels unquote(Macro.escape(channels))
      @command_signals unquote(Macro.escape(signals))
      @command_name unquote(name)

      @doc """
      Returns the system prompt for this command.
      """
      def system_prompt, do: @command_system_prompt

      @doc """
      Returns the allowed tools for this command.
      """
      def allowed_tools, do: @command_tools

      @doc """
      Returns the channel configuration for this command.
      """
      def channel_config, do: @command_channels

      @doc """
      Returns the signal configuration for this command.
      """
      def signal_config, do: @command_signals

      @impl true
      def run(params, context) do
        # Emit start signal if configured
        start_directives = maybe_emit_signal(:on_start, params, context, @command_signals)

        # Execute command logic - can be overridden by implementing modules
        result = execute_command(params, context)

        # Add completion signal if configured
        end_directives =
          maybe_emit_signal(:on_complete, params, context, @command_signals)

        all_directives = start_directives ++ end_directives

        # Return result with directives as third element
        case result do
          {:ok, data} -> {:ok, data, all_directives}
          {:ok, data, extra_directives} -> {:ok, data, extra_directives ++ all_directives}
          error -> error
        end
      end

      @doc """
      Override this function to implement command-specific logic.

      Default implementation returns ok with params.

      ## Return Values

      - `{:ok, data}` - Return data with default directives (signals)
      - `{:ok, data, directives}` - Return data with additional directives
      - `{:error, reason}` - Return an error
      """
      def execute_command(params, _context) do
        {:ok, params}
      end

      defoverridable(execute_command: 2)

      # Private helper for emitting configured signals
      defp maybe_emit_signal(event_type, params, context, signal_config) do
        events = Keyword.get(signal_config, :events, [])

        case Keyword.get(events, event_type) do
          nil ->
            []

          signal_types when is_list(signal_types) ->
            Enum.map(signal_types, &build_signal_directive(&1, params, context, event_type))

          signal_type ->
            [build_signal_directive(signal_type, params, context, event_type)]
        end
      end

      defp build_signal_directive(signal_type, params, context, event_type) do
        signal_data = %{
          command_name: @command_name,
          params: inspect(params),
          context: inspect(context),
          event: event_type,
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        signal = Signal.new!(signal_type, signal_data, source: "command:#{@command_name}")

        %Directive.Emit{signal: signal}
      end
    end
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Sanitizes a command name into a valid Elixir module name.

  Handles both kebab-case and snake_case by converting to CamelCase.

  ## Examples

      iex> sanitize_module_name("code-reviewer")
      "CodeReviewer"

      iex> sanitize_module_name("my_command")
      "MyCommand"

      iex> sanitize_module_name("my-test-command")
      "MyTestCommand"

  """
  def sanitize_module_name(name) when is_binary(name) do
    name
    |> String.replace("-", "_")  # First normalize hyphens to underscores
    |> String.split("_", trim: true)  # Then split on underscores
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end

  @doc """
  Generates a full module name for a dynamically generated command.

  ## Examples

      iex> module_name("code-reviewer")
      JidoCode.Extensibility.Commands.CodeReviewer

  """
  def module_name(name) when is_binary(name) do
    Module.concat([JidoCode.Extensibility.Commands, sanitize_module_name(name)])
  end

  @doc """
  Creates a new Command struct from a map.

  Useful for testing or manual construction.

  ## Examples

      iex> new(%{name: "test", description: "Test command"})
      {:ok, %JidoCode.Extensibility.Command{name: "test", description: "Test command", ...}}

  """
  def new(attrs) when is_map(attrs) do
    Zoi.parse(@schema, attrs)
  end

  @doc """
  Same as `new/1` but raises on error.
  """
  def new!(attrs) when is_map(attrs) do
    case new(attrs) do
      {:ok, struct} -> struct
      {:error, reason} -> raise ArgumentError, "Invalid Command: #{inspect(reason)}"
    end
  end

  @doc """
  Converts a Command struct to a map with string keys.

  Useful for serialization.
  """
  def to_map(%__MODULE__{} = command) do
    command
    |> Map.from_struct()
    |> Enum.map(fn {k, v} -> {Atom.to_string(k), v} end)
    |> Map.new()
  end
end
