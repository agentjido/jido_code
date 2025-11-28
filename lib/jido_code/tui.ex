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
  - Tool calls and results

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

  use TermUI.Elm

  alias JidoCode.Settings
  alias TermUI.Event
  alias TermUI.Renderer.Style

  # ============================================================================
  # Message Types
  # ============================================================================

  # Messages handled by update/2:
  #
  # Keyboard input:
  #   {:key_input, char}     - Printable character typed
  #   {:key_input, :backspace} - Backspace pressed
  #   {:submit}              - Enter key pressed
  #   :quit                  - Ctrl+C pressed
  #
  # PubSub messages (from agent):
  #   {:agent_response, content}  - Agent response received
  #   {:status_update, status}    - Agent status changed
  #   {:config_change, config}    - Configuration changed
  #   {:reasoning_step, step}     - Chain-of-Thought step

  @type msg ::
          {:key_input, String.t() | :backspace}
          | {:submit}
          | :quit
          | {:agent_response, String.t()}
          | {:status_update, Model.agent_status()}
          | {:config_change, map()}
          | {:reasoning_step, Model.reasoning_step()}

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

  Handles keyboard events:
  - Enter → {:submit}
  - Printable characters → {:key_input, char}
  - Backspace → {:key_input, :backspace}
  - Ctrl+C → :quit
  """
  @impl true
  def event_to_msg(%Event.Key{key: :enter}, _state) do
    {:submit}
  end

  def event_to_msg(%Event.Key{key: :backspace}, _state) do
    {:key_input, :backspace}
  end

  def event_to_msg(%Event.Key{key: :c, modifiers: modifiers}, _state) do
    if :ctrl in modifiers do
      :quit
    else
      {:key_input, "c"}
    end
  end

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:key_input, char}
  end

  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:resize, width, height}
  end

  def event_to_msg(_event, _state) do
    :ignore
  end

  @doc """
  Updates state based on messages.

  Handles:
  - `{:key_input, char}` - Append character to input buffer
  - `{:key_input, :backspace}` - Remove last character from buffer
  - `{:submit}` - Submit current input, clear buffer, add to messages
  - `:quit` - Return quit command
  - `{:resize, width, height}` - Update window dimensions
  - PubSub messages for agent events (to be fully implemented in 4.1.3)
  """
  @impl true
  def update({:key_input, char}, state) when is_binary(char) do
    new_buffer = state.input_buffer <> char
    {%{state | input_buffer: new_buffer}, []}
  end

  def update({:key_input, :backspace}, state) do
    new_buffer =
      if String.length(state.input_buffer) > 0 do
        String.slice(state.input_buffer, 0..-2//1)
      else
        ""
      end

    {%{state | input_buffer: new_buffer}, []}
  end

  def update({:submit}, state) do
    text = String.trim(state.input_buffer)

    if text == "" do
      {state, []}
    else
      message = %{role: :user, content: text, timestamp: DateTime.utc_now()}

      new_state = %{state | input_buffer: "", messages: state.messages ++ [message]}

      {new_state, []}
    end
  end

  def update(:quit, state) do
    {state, [:quit]}
  end

  def update({:resize, width, height}, state) do
    {%{state | window: {width, height}}, []}
  end

  # PubSub message handlers (basic implementation, expanded in 4.1.3)
  def update({:agent_response, content}, state) do
    message = %{role: :assistant, content: content, timestamp: DateTime.utc_now()}
    new_state = %{state | messages: state.messages ++ [message]}
    {new_state, []}
  end

  def update({:status_update, status}, state) do
    {%{state | agent_status: status}, []}
  end

  def update({:config_change, config}, state) do
    new_config = %{
      provider: Map.get(config, :provider, Map.get(config, "provider")),
      model: Map.get(config, :model, Map.get(config, "model"))
    }

    new_status = determine_status(new_config)
    {%{state | config: new_config, agent_status: new_status}, []}
  end

  def update({:reasoning_step, step}, state) do
    {%{state | reasoning_steps: state.reasoning_steps ++ [step]}, []}
  end

  # Catch-all for unhandled messages
  def update(_msg, state) do
    {state, []}
  end

  @doc """
  Renders the current state to a render tree.

  Currently renders a minimal placeholder UI. Full view rendering will be
  implemented in task 4.2.x.
  """
  @impl true
  def view(state) do
    stack(:vertical, [
      render_status_bar(state),
      text("", nil),
      text("JidoCode - Agentic Coding Assistant", Style.new(fg: :cyan, attrs: [:bold])),
      text("", nil),
      render_config_info(state),
      text("", nil),
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
  # View Helpers (Minimal)
  # ============================================================================

  defp render_status_bar(state) do
    status_text = format_status(state.agent_status)
    config_text = format_config(state.config)

    text("#{config_text} | #{status_text}", Style.new(fg: :white, bg: :blue))
  end

  defp format_status(:idle), do: "Status: Idle"
  defp format_status(:processing), do: "Status: Processing..."
  defp format_status(:error), do: "Status: Error"
  defp format_status(:unconfigured), do: "Status: Not Configured"

  defp format_config(%{provider: nil}), do: "No provider configured"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  defp render_config_info(state) do
    case state.agent_status do
      :unconfigured ->
        stack(:vertical, [
          text("Configuration Required", Style.new(fg: :yellow, attrs: [:bold])),
          text("", nil),
          text("No provider or model configured.", nil),
          text("Create ~/.jido_code/settings.json with:", nil),
          text("", nil),
          text("  {", Style.new(fg: :bright_black)),
          text(~s(    "provider": "anthropic",), Style.new(fg: :bright_black)),
          text(~s(    "model": "claude-3-5-sonnet"), Style.new(fg: :bright_black)),
          text("  }", Style.new(fg: :bright_black))
        ])

      _ ->
        stack(:vertical, [
          text("Ready", Style.new(fg: :green, attrs: [:bold])),
          text("", nil),
          text("Provider: #{state.config.provider || "none"}", nil),
          text("Model: #{state.config.model || "none"}", nil)
        ])
    end
  end
end
