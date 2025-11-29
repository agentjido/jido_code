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

  Loads settings from disk and determines initial agent status based on configuration.
  PubSub subscription is handled by PubSubBridge which forwards messages to this component.
  """
  @impl true
  def init(_opts) do
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

  # ============================================================================
  # PubSub Message Handlers
  # ============================================================================

  # Handles agent response from PubSub - adds assistant message to conversation history
  def update({:agent_response, content}, state) do
    message = %{
      role: :assistant,
      content: content,
      timestamp: DateTime.utc_now()
    }

    new_state = %{state |
      messages: state.messages ++ [message],
      agent_status: :idle
    }

    {new_state, []}
  end

  # Handles agent status change from PubSub - updates the agent_status indicator
  def update({:agent_status, status}, state) when status in [:idle, :processing, :error] do
    {%{state | agent_status: status}, []}
  end

  # Handles reasoning step update from PubSub - adds or updates reasoning steps for CoT display
  def update({:reasoning_step, step}, state) do
    # Add new step or update existing one based on step content
    new_steps = update_reasoning_steps(state.reasoning_steps, step)
    {%{state | reasoning_steps: new_steps}, []}
  end

  # Handles configuration change from PubSub - updates config and re-determines status
  def update({:config_changed, new_config}, state) do
    config = %{
      provider: Map.get(new_config, :provider) || Map.get(new_config, "provider"),
      model: Map.get(new_config, :model) || Map.get(new_config, "model")
    }

    status = determine_status(config)

    {%{state | config: config, agent_status: status}, []}
  end

  def update(_msg, state) do
    {state, []}
  end

  # ============================================================================
  # Reasoning Step Helpers
  # ============================================================================

  defp update_reasoning_steps(steps, %{step: step_text, status: status}) do
    # Look for existing step with same text
    case Enum.find_index(steps, fn s -> s.step == step_text end) do
      nil ->
        # Add new step
        steps ++ [%{step: step_text, status: status}]

      index ->
        # Update existing step status
        List.update_at(steps, index, fn s -> %{s | status: status} end)
    end
  end

  defp update_reasoning_steps(steps, step_text) when is_binary(step_text) do
    # Simple text step - add as pending
    steps ++ [%{step: step_text, status: :pending}]
  end

  @doc """
  Renders the current state to a render tree.

  Implements a three-pane layout:
  - Status bar at top (provider:model, status indicator, keyboard hints)
  - Conversation area in the middle (message history)
  - Input bar at bottom (prompt + input buffer)
  """
  @impl true
  def view(state) do
    stack(:vertical, [
      render_status_bar(state),
      render_conversation(state),
      render_input_bar(state)
    ])
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Runs the TUI application.

  Starts the TermUI Runtime with a registered name, then starts the PubSub bridge
  to forward agent events to the TUI component.

  This blocks the calling process until the TUI exits (e.g., user presses Ctrl+C).
  """
  @spec run() :: :ok
  def run do
    # Start runtime with registered name so PubSubBridge can send messages to it
    {:ok, runtime_pid} = TermUI.Runtime.start_link(
      root: __MODULE__,
      name: __MODULE__.Runtime
    )

    # Monitor runtime to know when it exits
    ref = Process.monitor(runtime_pid)

    # Start PubSub bridge to forward agent events to the TUI
    {:ok, bridge_pid} = JidoCode.TUI.PubSubBridge.start_link(
      runtime: __MODULE__.Runtime,
      name: __MODULE__.PubSubBridge
    )

    # Block until runtime exits
    receive do
      {:DOWN, ^ref, :process, ^runtime_pid, _reason} ->
        # Stop the bridge when runtime exits
        if Process.alive?(bridge_pid) do
          JidoCode.TUI.PubSubBridge.stop(bridge_pid)
        end
        :ok
    end
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
  # View Helpers - Status Bar
  # ============================================================================

  defp render_status_bar(state) do
    config_text = format_config(state.config)
    status_indicator = format_status_indicator(state.agent_status)
    cot_indicator = format_cot_indicator(state.reasoning_steps)
    hints = "Ctrl+C: Quit"

    # Build status bar content
    content =
      [config_text, status_indicator, cot_indicator, hints]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(" | ")

    text(content, Style.new(fg: :white, bg: :blue))
  end

  defp format_config(%{provider: nil}), do: "No provider configured"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  defp format_status_indicator(:idle), do: "Idle"
  defp format_status_indicator(:processing), do: "Processing..."
  defp format_status_indicator(:error), do: "Error"
  defp format_status_indicator(:unconfigured), do: "Not Configured"

  defp format_cot_indicator([]), do: nil
  defp format_cot_indicator(steps) when is_list(steps) do
    active_count = Enum.count(steps, fn s -> s.status == :active end)
    complete_count = Enum.count(steps, fn s -> s.status == :complete end)
    total = length(steps)

    if active_count > 0 do
      "CoT: #{complete_count}/#{total}"
    else
      nil
    end
  end

  # ============================================================================
  # View Helpers - Conversation Area
  # ============================================================================

  defp render_conversation(state) do
    if Enum.empty?(state.messages) do
      render_empty_conversation(state)
    else
      render_messages(state.messages)
    end
  end

  defp render_empty_conversation(state) do
    case state.agent_status do
      :unconfigured ->
        stack(:vertical, [
          text(""),
          text("Configuration Required", Style.new(fg: :yellow, attrs: [:bold])),
          text(""),
          text("No provider or model configured."),
          text("Create ~/.jido_code/settings.json with:"),
          text(""),
          text("  {", Style.new(fg: :bright_black)),
          text(~s(    "provider": "anthropic",), Style.new(fg: :bright_black)),
          text(~s(    "model": "claude-3-5-sonnet"), Style.new(fg: :bright_black)),
          text("  }", Style.new(fg: :bright_black)),
          text("")
        ])

      _ ->
        stack(:vertical, [
          text(""),
          text("JidoCode - Agentic Coding Assistant", Style.new(fg: :cyan, attrs: [:bold])),
          text(""),
          text("Ready. Type a message and press Enter to send."),
          text("")
        ])
    end
  end

  defp render_messages(messages) do
    message_nodes =
      messages
      |> Enum.map(&render_message/1)

    stack(:vertical, [text("") | message_nodes])
  end

  defp render_message(%{role: :user, content: content, timestamp: timestamp}) do
    time_str = format_timestamp(timestamp)
    stack(:vertical, [
      text("[#{time_str}] You: #{content}", Style.new(fg: :cyan))
    ])
  end

  defp render_message(%{role: :assistant, content: content, timestamp: timestamp}) do
    time_str = format_timestamp(timestamp)
    stack(:vertical, [
      text("[#{time_str}] Assistant: #{content}", Style.new(fg: :white))
    ])
  end

  defp render_message(%{role: :system, content: content, timestamp: timestamp}) do
    time_str = format_timestamp(timestamp)
    stack(:vertical, [
      text("[#{time_str}] System: #{content}", Style.new(fg: :bright_black))
    ])
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  # ============================================================================
  # View Helpers - Input Bar
  # ============================================================================

  defp render_input_bar(state) do
    prompt = text("> ", Style.new(fg: :green, attrs: [:bold]))
    input = text(state.input_buffer)

    stack(:horizontal, [prompt, input])
  end
end
