defmodule JidoCode.TUI do
  @moduledoc """
  Terminal User Interface for JidoCode using TermUI's Elm Architecture.

  This module implements the main TUI application following the Elm Architecture
  pattern: `init/1` for initial state, `update/2` for state transitions, and
  `view/1` for rendering.

  ## Architecture

  The TUI connects to the agent system via Phoenix PubSub, receiving events for:
  - Agent responses
  - Status changes (idle, processing, error)
  - Reasoning steps (Chain-of-Thought progress)
  - Configuration changes

  ## Usage

      # Start the TUI (blocks until quit)
      JidoCode.TUI.run()

      # Or start via Runtime directly
      TermUI.Runtime.run(root: JidoCode.TUI)

  ## Model

  The TUI state contains:
  - `input_buffer` - Current text being typed
  - `messages` - Conversation history
  - `agent_status` - Current agent state (:idle, :processing, :error, :unconfigured)
  - `config` - Provider and model configuration
  - `reasoning_steps` - Chain-of-Thought progress
  - `window` - Terminal dimensions
  """

  @behaviour TermUI.Elm

  alias JidoCode.Settings
  alias TermUI.Command
  alias TermUI.Event
  alias TermUI.Renderer.Style

  # Import only Component.Helpers (avoid text/1 conflict with Elm.Helpers)
  import TermUI.Component.Helpers, only: [text: 1, text: 2, stack: 2]

  # ============================================================================
  # Model
  # ============================================================================

  defmodule Model do
    @moduledoc """
    The TUI application state.
    """

    @type message :: %{
            role: :user | :assistant | :system,
            content: String.t(),
            timestamp: DateTime.t()
          }

    @type reasoning_step :: %{
            step: String.t(),
            status: :pending | :active | :complete
          }

    @type agent_status :: :idle | :processing | :error | :unconfigured

    @type t :: %__MODULE__{
            input_buffer: String.t(),
            messages: [message()],
            agent_status: agent_status(),
            config: %{provider: String.t() | nil, model: String.t() | nil},
            reasoning_steps: [reasoning_step()],
            window: {non_neg_integer(), non_neg_integer()}
          }

    @enforce_keys []
    defstruct input_buffer: "",
              messages: [],
              agent_status: :unconfigured,
              config: %{provider: nil, model: nil},
              reasoning_steps: [],
              window: {80, 24}
  end

  # ============================================================================
  # Elm Callbacks
  # ============================================================================

  @doc """
  Initializes the TUI state.

  Loads settings from disk, subscribes to PubSub events, and determines
  initial agent status based on configuration.
  """
  @impl true
  def init(_opts) do
    # Subscribe to TUI events
    Phoenix.PubSub.subscribe(JidoCode.PubSub, "tui.events")

    # Load configuration from settings
    config = load_config()

    # Determine initial status based on config
    status = determine_status(config)

    %Model{
      input_buffer: "",
      messages: [],
      agent_status: status,
      config: config,
      reasoning_steps: [],
      window: {80, 24}
    }
  end

  @doc """
  Converts terminal events to TUI messages.

  ## Message Types

  - `:submit` - Enter key pressed (submit input)
  - `{:key_input, char}` - Printable character typed
  - `{:key_input, :backspace}` - Backspace pressed
  - `:quit` - Ctrl+C pressed (exit application)
  - `{:resize, width, height}` - Terminal resized
  """
  @impl true
  def event_to_msg(%Event.Key{key: :enter}, _state) do
    {:msg, :submit}
  end

  def event_to_msg(%Event.Key{key: :backspace}, _state) do
    {:msg, {:key_input, :backspace}}
  end

  def event_to_msg(%Event.Key{key: :c, modifiers: modifiers}, _state) do
    if :ctrl in modifiers do
      {:msg, :quit}
    else
      {:msg, {:key_input, "c"}}
    end
  end

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:msg, {:key_input, char}}
  end

  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(_event, _state) do
    :ignore
  end

  @doc """
  Updates state based on messages.

  Handles the following messages:
  - `:submit` - Add user message to history, clear input buffer
  - `{:key_input, char}` - Append character to input buffer
  - `{:key_input, :backspace}` - Remove last character from input buffer
  - `:quit` - Return Command.quit() to exit application
  - `{:resize, width, height}` - Update window dimensions
  """
  @impl true
  def update(:submit, state) do
    if state.input_buffer != "" do
      message = %{
        role: :user,
        content: state.input_buffer,
        timestamp: DateTime.utc_now()
      }

      new_state = %{state | input_buffer: "", messages: state.messages ++ [message]}
      {new_state, []}
    else
      {state, []}
    end
  end

  def update({:key_input, :backspace}, state) do
    if state.input_buffer != "" do
      new_buffer = String.slice(state.input_buffer, 0..-2//1)
      {%{state | input_buffer: new_buffer}, []}
    else
      {state, []}
    end
  end

  def update({:key_input, char}, state) when is_binary(char) do
    new_buffer = state.input_buffer <> char
    {%{state | input_buffer: new_buffer}, []}
  end

  def update(:quit, state) do
    {state, [Command.quit(:user_requested)]}
  end

  def update({:resize, width, height}, state) do
    {%{state | window: {width, height}}, []}
  end

  def update(_msg, state) do
    {state, []}
  end

  @doc """
  Renders the current state to a render tree.

  Currently renders a placeholder view. Full view implementation
  will be done in task 4.2.1.
  """
  @impl true
  def view(state) do
    stack(:vertical, [
      render_status_bar(state),
      text(""),
      text("JidoCode - Agentic Coding Assistant", Style.new(fg: :cyan, attrs: [:bold])),
      text(""),
      render_config_info(state),
      text(""),
      text("Press Ctrl+C to quit", Style.new(fg: :bright_black))
    ])
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs the TUI application.

  This blocks the calling process until the TUI exits (e.g., user presses Ctrl+C).
  """
  @spec run() :: :ok
  def run do
    TermUI.Runtime.run(root: __MODULE__)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  @spec load_config() :: %{provider: String.t() | nil, model: String.t() | nil}
  defp load_config do
    {:ok, settings} = Settings.load()

    %{
      provider: Map.get(settings, "provider"),
      model: Map.get(settings, "model")
    }
  end

  @doc false
  @spec determine_status(%{provider: String.t() | nil, model: String.t() | nil}) :: Model.agent_status()
  def determine_status(config) do
    cond do
      is_nil(config.provider) -> :unconfigured
      is_nil(config.model) -> :unconfigured
      true -> :idle
    end
  end

  # ============================================================================
  # View Helpers
  # ============================================================================

  defp render_status_bar(state) do
    config_text = format_config(state.config)
    status_text = format_status(state.agent_status)

    text("#{config_text} | #{status_text}", Style.new(fg: :white, bg: :blue))
  end

  defp format_config(%{provider: nil}), do: "No provider configured"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  defp format_status(:idle), do: "Idle"
  defp format_status(:processing), do: "Processing..."
  defp format_status(:error), do: "Error"
  defp format_status(:unconfigured), do: "Not Configured"

  defp render_config_info(state) do
    case state.agent_status do
      :unconfigured ->
        stack(:vertical, [
          text("Configuration Required", Style.new(fg: :yellow, attrs: [:bold])),
          text(""),
          text("No provider or model configured."),
          text("Create ~/.jido_code/settings.json with:"),
          text(""),
          text("  {", Style.new(fg: :bright_black)),
          text(~s(    "provider": "anthropic",), Style.new(fg: :bright_black)),
          text(~s(    "model": "claude-3-5-sonnet"), Style.new(fg: :bright_black)),
          text("  }", Style.new(fg: :bright_black))
        ])

      _ ->
        stack(:vertical, [
          text("Ready", Style.new(fg: :green, attrs: [:bold])),
          text(""),
          text("Provider: #{state.config.provider || "none"}"),
          text("Model: #{state.config.model || "none"}")
        ])
    end
  end
end
