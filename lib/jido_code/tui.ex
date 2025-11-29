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
            window: {non_neg_integer(), non_neg_integer()},
            scroll_offset: non_neg_integer(),
            show_reasoning: boolean()
          }

    @enforce_keys []
    defstruct input_buffer: "",
              messages: [],
              agent_status: :unconfigured,
              config: %{provider: nil, model: nil},
              reasoning_steps: [],
              window: {80, 24},
              scroll_offset: 0,
              show_reasoning: false
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
      window: {80, 24},
      scroll_offset: 0,
      show_reasoning: false
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

  def event_to_msg(%Event.Key{key: :r, modifiers: modifiers}, _state) do
    if :ctrl in modifiers do
      {:msg, :toggle_reasoning}
    else
      {:msg, {:key_input, "r"}}
    end
  end

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:msg, {:key_input, char}}
  end

  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:msg, {:resize, width, height}}
  end

  def event_to_msg(%Event.Key{key: :up}, _state) do
    {:msg, :scroll_up}
  end

  def event_to_msg(%Event.Key{key: :down}, _state) do
    {:msg, :scroll_down}
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

      # Reset scroll_offset to 0 for auto-scroll to latest message
      new_state = %{state |
        input_buffer: "",
        messages: state.messages ++ [message],
        scroll_offset: 0
      }
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

  def update(:scroll_up, state) do
    # Increase offset to scroll up through history (show older messages)
    max_offset = max(0, length(state.messages) - 1)
    new_offset = min(state.scroll_offset + 1, max_offset)
    {%{state | scroll_offset: new_offset}, []}
  end

  def update(:scroll_down, state) do
    # Decrease offset to scroll down (show newer messages)
    new_offset = max(0, state.scroll_offset - 1)
    {%{state | scroll_offset: new_offset}, []}
  end

  def update(:toggle_reasoning, state) do
    {%{state | show_reasoning: not state.show_reasoning}, []}
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

    # Reset scroll_offset to 0 for auto-scroll to latest message
    new_state = %{state |
      messages: state.messages ++ [message],
      agent_status: :idle,
      scroll_offset: 0
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

  Implements a multi-pane layout:
  - Status bar at top (provider:model, status indicator, keyboard hints)
  - Conversation area in the middle (message history)
  - Optional reasoning panel (right sidebar or bottom drawer based on width)
  - Input bar at bottom (prompt + input buffer)
  """
  @impl true
  def view(state) do
    {width, _height} = state.window
    show_panel = state.show_reasoning and not Enum.empty?(state.reasoning_steps)

    if show_panel and width >= 100 do
      # Wide terminal: reasoning panel as right sidebar
      render_wide_layout(state)
    else
      # Narrow terminal or no panel: vertical layout
      render_narrow_layout(state, show_panel)
    end
  end

  defp render_wide_layout(state) do
    # Right sidebar layout for wide terminals
    stack(:vertical, [
      stack(:horizontal, [
        # Left side: status bar
        render_status_bar(state),
        text(" | "),
        # Right side: reasoning header
        render_reasoning_header(state)
      ]),
      stack(:horizontal, [
        # Left side: conversation
        render_conversation(state),
        text(" "),
        # Right side: reasoning steps
        render_reasoning_steps(state)
      ]),
      render_input_bar(state)
    ])
  end

  defp render_narrow_layout(state, show_panel) do
    elements = [
      render_status_bar(state),
      render_conversation(state)
    ]

    # Add reasoning panel as bottom drawer if enabled
    elements =
      if show_panel do
        elements ++ [render_reasoning_panel(state)]
      else
        elements
      end

    elements = elements ++ [render_input_bar(state)]

    stack(:vertical, elements)
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

  defp load_config do
    {:ok, settings} = Settings.load()

    %{
      provider: Map.get(settings, "provider"),
      model: Map.get(settings, "model")
    }
  end

  @doc false
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
    # Build segments with individual styling
    segments = [
      render_config_segment(state.config),
      text(" | ", Style.new(fg: :white, bg: :blue)),
      render_status_segment(state.agent_status)
    ]

    # Add CoT indicator if active
    segments =
      case render_cot_segment(state.reasoning_steps) do
        nil -> segments
        cot -> segments ++ [text(" | ", Style.new(fg: :white, bg: :blue)), cot]
      end

    # Add keyboard hints
    segments = segments ++ [
      text(" | ", Style.new(fg: :white, bg: :blue)),
      render_hints_segment()
    ]

    stack(:horizontal, segments)
  end

  # Config segment with warning colors for unconfigured states
  defp render_config_segment(%{provider: nil}) do
    text("No provider configured", Style.new(fg: :red, bg: :blue))
  end

  defp render_config_segment(%{model: nil, provider: p}) do
    text("#{p} (no model)", Style.new(fg: :yellow, bg: :blue))
  end

  defp render_config_segment(%{provider: p, model: m}) do
    text("#{p}:#{m}", Style.new(fg: :white, bg: :blue))
  end

  # Status segment with colored indicators
  defp render_status_segment(status) do
    {indicator, label, style} = status_indicator_style(status)
    text("#{indicator} #{label}", style)
  end

  # Returns indicator symbol, label, and style for each status
  defp status_indicator_style(:idle) do
    {"●", "Idle", Style.new(fg: :green, bg: :blue)}
  end

  defp status_indicator_style(:processing) do
    {"●", "Processing", Style.new(fg: :yellow, bg: :blue)}
  end

  defp status_indicator_style(:error) do
    {"●", "Error", Style.new(fg: :red, bg: :blue)}
  end

  defp status_indicator_style(:unconfigured) do
    {"○", "Not Configured", Style.new(fg: :bright_black, bg: :blue)}
  end

  # CoT segment (returns nil if no active reasoning)
  defp render_cot_segment([]), do: nil

  defp render_cot_segment(steps) when is_list(steps) do
    active_count = Enum.count(steps, fn s -> s.status == :active end)
    complete_count = Enum.count(steps, fn s -> s.status == :complete end)
    total = length(steps)

    if active_count > 0 do
      text("CoT: #{complete_count}/#{total}", Style.new(fg: :magenta, bg: :blue))
    else
      nil
    end
  end

  # Keyboard hints segment
  defp render_hints_segment do
    text("Ctrl+M: Model | Ctrl+R: Reasoning | Ctrl+C: Quit", Style.new(fg: :bright_black, bg: :blue))
  end

  # ============================================================================
  # View Helpers - Conversation Area
  # ============================================================================

  defp render_conversation(state) do
    if Enum.empty?(state.messages) do
      render_empty_conversation(state)
    else
      render_messages(state)
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

  # Optimized scroll offset handling using Enum.take/2 instead of double Enum.reverse/1
  defp get_visible_messages(messages, 0), do: messages
  defp get_visible_messages(messages, scroll_offset) do
    keep_count = length(messages) - scroll_offset
    if keep_count > 0, do: Enum.take(messages, keep_count), else: messages
  end

  defp render_messages(state) do
    {width, _height} = state.window
    messages = state.messages

    # Apply scroll offset - skip messages from the end
    visible_messages = get_visible_messages(messages, state.scroll_offset)

    message_nodes =
      visible_messages
      |> Enum.map(&render_message(&1, width))

    # Add scroll indicator if not at bottom
    scroll_indicator =
      if state.scroll_offset > 0 do
        [text("  ↓ #{state.scroll_offset} more message(s) below", Style.new(fg: :bright_black))]
      else
        []
      end

    stack(:vertical, [text("") | message_nodes] ++ scroll_indicator)
  end

  # Message role configuration: {label, style}
  defp message_config(:user), do: {"You", Style.new(fg: :cyan)}
  defp message_config(:assistant), do: {"Assistant", Style.new(fg: :white)}
  defp message_config(:system), do: {"System", Style.new(fg: :bright_black)}

  defp render_message(%{role: role, content: content, timestamp: timestamp}, width) do
    {label, style} = message_config(role)
    time_str = format_timestamp(timestamp)
    prefix = "[#{time_str}] #{label}: "
    wrapped_lines = wrap_message(prefix, content, width)

    lines_as_nodes =
      wrapped_lines
      |> Enum.map(fn line -> text(line, style) end)

    stack(:vertical, lines_as_nodes)
  end

  defp format_timestamp(datetime) do
    Calendar.strftime(datetime, "%H:%M")
  end

  # Wraps a message with a prefix, using continuation indent for wrapped lines
  defp wrap_message(prefix, content, max_width) do
    # First line includes prefix
    first_line_width = max_width - String.length(prefix)
    # Continuation lines are indented to align with content after prefix
    indent = String.duplicate(" ", String.length(prefix))

    if first_line_width <= 0 do
      # Terminal too narrow, just show as-is
      [prefix <> content]
    else
      wrap_text(content, first_line_width, max_width - String.length(indent))
      |> Enum.with_index()
      |> Enum.map(fn {line, index} ->
        if index == 0 do
          prefix <> line
        else
          indent <> line
        end
      end)
    end
  end

  # Wraps text at word boundaries
  @doc false
  @spec wrap_text(String.t(), non_neg_integer(), non_neg_integer()) :: [String.t()]
  def wrap_text(text, first_line_width, continuation_width) do
    words = String.split(text, ~r/\s+/, trim: true)

    case words do
      [] ->
        [""]

      [first | rest] ->
        # Handle first line with potentially different width
        {first_line, remaining_words} = build_line(first, rest, first_line_width)

        # Handle remaining lines with continuation width
        continuation_lines = wrap_remaining(remaining_words, continuation_width)

        [first_line | continuation_lines]
    end
  end

  defp build_line(current, [], _max_width), do: {current, []}

  defp build_line(current, [next | rest], max_width) do
    candidate = current <> " " <> next

    if String.length(candidate) <= max_width do
      build_line(candidate, rest, max_width)
    else
      {current, [next | rest]}
    end
  end

  defp wrap_remaining([], _max_width), do: []

  defp wrap_remaining([first | rest], max_width) do
    {line, remaining} = build_line(first, rest, max_width)
    [line | wrap_remaining(remaining, max_width)]
  end

  # ============================================================================
  # View Helpers - Reasoning Panel
  # ============================================================================

  # Header for the reasoning panel showing step count
  defp render_reasoning_header(state) do
    step_count = length(state.reasoning_steps)
    text("Reasoning (#{step_count})", Style.new(fg: :magenta, attrs: [:bold]))
  end

  # Renders reasoning steps as a vertical list (for wide layout sidebar)
  defp render_reasoning_steps(state) do
    step_nodes =
      state.reasoning_steps
      |> Enum.map(&render_reasoning_step/1)

    stack(:vertical, step_nodes)
  end

  # Renders the full reasoning panel as a bottom drawer (for narrow layout)
  defp render_reasoning_panel(state) do
    step_count = length(state.reasoning_steps)
    header = text("Reasoning (#{step_count})", Style.new(fg: :magenta, attrs: [:bold]))

    # In narrow mode, render steps horizontally to save vertical space
    step_texts =
      state.reasoning_steps
      |> Enum.map(&format_step_inline/1)
      |> Enum.join(" │ ")

    steps_line = text(step_texts)

    stack(:vertical, [header, steps_line])
  end

  # Renders a single reasoning step with status indicator
  defp render_reasoning_step(%{step: step_text, status: status}) do
    {indicator, style} = step_indicator(status)
    text("#{indicator} #{step_text}", style)
  end

  # Formats a step inline for narrow layout (horizontal display)
  defp format_step_inline(%{step: step_text, status: status}) do
    {indicator, _style} = step_indicator(status)
    "#{indicator} #{step_text}"
  end

  # Returns the status indicator symbol and style for a reasoning step
  defp step_indicator(:pending), do: {"○", Style.new(fg: :bright_black)}
  defp step_indicator(:active), do: {"●", Style.new(fg: :yellow, attrs: [:bold])}
  defp step_indicator(:complete), do: {"✓", Style.new(fg: :green)}

  # ============================================================================
  # View Helpers - Input Bar
  # ============================================================================

  defp render_input_bar(state) do
    prompt = text("> ", Style.new(fg: :green, attrs: [:bold]))
    input = text(state.input_buffer)

    stack(:horizontal, [prompt, input])
  end
end
