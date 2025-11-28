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
          | {:agent_status, Model.agent_status()}
          | {:status_update, Model.agent_status()}
          | {:config_changed, map()}
          | {:config_change, map()}
          | {:reasoning_step, Model.reasoning_step()}
          | :clear_reasoning_steps

  # Maximum number of messages to keep in the debug queue
  @max_queue_size 100

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

    @type queued_message :: {term(), DateTime.t()}

    @type t :: %__MODULE__{
            input_buffer: String.t(),
            messages: [message()],
            agent_status: agent_status(),
            config: %{provider: String.t() | nil, model: String.t() | nil},
            reasoning_steps: [reasoning_step()],
            window: {non_neg_integer(), non_neg_integer()},
            message_queue: [queued_message()],
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
              message_queue: [],
              scroll_offset: 0,
              show_reasoning: false
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
      window: {80, 24},
      message_queue: [],
      scroll_offset: 0,
      show_reasoning: false
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

  def event_to_msg(%Event.Key{key: :r, modifiers: modifiers}, _state) do
    if :ctrl in modifiers do
      :toggle_reasoning
    else
      {:key_input, "r"}
    end
  end

  def event_to_msg(%Event.Key{char: char}, _state) when is_binary(char) and char != "" do
    {:key_input, char}
  end

  def event_to_msg(%Event.Resize{width: width, height: height}, _state) do
    {:resize, width, height}
  end

  def event_to_msg(%Event.Key{key: :up}, _state) do
    {:scroll, :up}
  end

  def event_to_msg(%Event.Key{key: :down}, _state) do
    {:scroll, :down}
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

  # Scroll navigation
  def update({:scroll, :up}, state) do
    # Scroll up (towards older messages) - increase offset
    max_offset = max_scroll_offset(state)
    new_offset = min(state.scroll_offset + 1, max_offset)
    {%{state | scroll_offset: new_offset}, []}
  end

  def update({:scroll, :down}, state) do
    # Scroll down (towards newer messages) - decrease offset
    new_offset = max(state.scroll_offset - 1, 0)
    {%{state | scroll_offset: new_offset}, []}
  end

  # PubSub message handlers with message queueing
  def update({:agent_response, content}, state) do
    message = %{role: :assistant, content: content, timestamp: DateTime.utc_now()}
    queue = queue_message(state.message_queue, {:agent_response, content})

    new_state = %{state |
      messages: state.messages ++ [message],
      message_queue: queue
    }

    {new_state, []}
  end

  # Support both :status_update and :agent_status (per phase plan naming)
  def update({:status_update, status}, state) do
    queue = queue_message(state.message_queue, {:status_update, status})
    {%{state | agent_status: status, message_queue: queue}, []}
  end

  def update({:agent_status, status}, state) do
    update({:status_update, status}, state)
  end

  # Support both :config_change and :config_changed (per phase plan naming)
  def update({:config_change, config}, state) do
    new_config = %{
      provider: Map.get(config, :provider, Map.get(config, "provider")),
      model: Map.get(config, :model, Map.get(config, "model"))
    }

    new_status = determine_status(new_config)
    queue = queue_message(state.message_queue, {:config_change, config})
    {%{state | config: new_config, agent_status: new_status, message_queue: queue}, []}
  end

  def update({:config_changed, config}, state) do
    update({:config_change, config}, state)
  end

  def update({:reasoning_step, step}, state) do
    queue = queue_message(state.message_queue, {:reasoning_step, step})
    {%{state | reasoning_steps: state.reasoning_steps ++ [step], message_queue: queue}, []}
  end

  def update(:clear_reasoning_steps, state) do
    {%{state | reasoning_steps: []}, []}
  end

  def update(:toggle_reasoning, state) do
    {%{state | show_reasoning: not state.show_reasoning}, []}
  end

  # Catch-all for unhandled messages
  def update(_msg, state) do
    {state, []}
  end

  @doc """
  Renders the current state to a render tree.

  Implements a three-pane layout:
  - Status bar (top): Provider, model, agent status, keyboard hints
  - Conversation area (middle): Message history with role indicators
  - Input bar (bottom): Prompt indicator and current input buffer
  """
  @impl true
  def view(state) do
    case state.agent_status do
      :unconfigured ->
        # Show configuration screen when not configured
        render_unconfigured_view(state)

      _ ->
        # Show main chat interface when configured
        render_main_view(state)
    end
  end

  defp render_main_view(state) do
    {width, _height} = state.window

    if state.show_reasoning do
      # Show reasoning panel
      if width >= 100 do
        # Wide terminal: side-by-side layout
        render_main_view_with_sidebar(state)
      else
        # Narrow terminal: stacked layout with compact reasoning
        render_main_view_with_drawer(state)
      end
    else
      # Standard layout without reasoning panel
      stack(:vertical, [
        render_status_bar(state),
        render_conversation(state),
        render_input_bar(state)
      ])
    end
  end

  defp render_main_view_with_sidebar(state) do
    # Side-by-side layout for wide terminals
    stack(:vertical, [
      render_status_bar(state),
      stack(:horizontal, [
        render_conversation(state),
        render_reasoning(state)
      ]),
      render_input_bar(state)
    ])
  end

  defp render_main_view_with_drawer(state) do
    # Stacked layout with reasoning drawer for narrow terminals
    stack(:vertical, [
      render_status_bar(state),
      render_conversation(state),
      render_reasoning_compact(state),
      render_input_bar(state)
    ])
  end

  defp render_unconfigured_view(state) do
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

  @doc """
  Queues a message with timestamp, limiting to @max_queue_size entries.

  Used for debugging and preventing unbounded message accumulation during rapid updates.
  """
  @spec queue_message([Model.queued_message()], term()) :: [Model.queued_message()]
  def queue_message(queue, msg) do
    [{msg, DateTime.utc_now()} | queue]
    |> Enum.take(@max_queue_size)
  end

  @doc """
  Calculates the maximum scroll offset based on message count and available height.

  Returns 0 if all messages fit on screen, otherwise returns the number of lines
  that can be scrolled up (towards older messages).
  """
  @spec max_scroll_offset(Model.t()) :: non_neg_integer()
  def max_scroll_offset(state) do
    {width, height} = state.window
    available_height = max(height - 2, 1)
    # Calculate total lines with wrapping
    total_lines = calculate_total_lines(state.messages, width)
    max(total_lines - available_height, 0)
  end

  # Calculate total lines accounting for text wrapping
  defp calculate_total_lines(messages, width) do
    Enum.reduce(messages, 0, fn msg, acc ->
      # Account for prefix length in wrapping
      prefix_len = prefix_length(msg.role)
      content_width = max(width - prefix_len, 20)
      lines = wrap_text(msg.content, content_width)
      acc + length(lines)
    end)
  end

  defp prefix_length(:user), do: String.length("[00:00] You: ")
  defp prefix_length(:assistant), do: String.length("[00:00] Assistant: ")
  defp prefix_length(:system), do: String.length("[00:00] System: ")

  @doc """
  Wraps text to fit within the specified width.

  Words are kept together when possible. Words longer than max_width are split.
  Returns a list of lines.
  """
  @spec wrap_text(String.t(), pos_integer()) :: [String.t()]
  def wrap_text(text, max_width) when max_width > 0 do
    text
    |> String.split(" ")
    |> Enum.reduce({[], ""}, fn word, acc -> wrap_word(word, acc, max_width) end)
    |> finalize_wrap()
  end

  def wrap_text(_text, _max_width), do: [""]

  defp wrap_word(word, {lines, current_line}, max_width) do
    new_line = if current_line == "", do: word, else: current_line <> " " <> word

    cond do
      String.length(new_line) <= max_width ->
        {lines, new_line}

      current_line == "" ->
        # Word is longer than max_width, split it
        {lines ++ [String.slice(word, 0, max_width)], String.slice(word, max_width..-1//1)}

      true ->
        {lines ++ [current_line], word}
    end
  end

  defp finalize_wrap({lines, last}) do
    result = if last == "", do: lines, else: lines ++ [last]

    case result do
      [] -> [""]
      final_lines -> final_lines
    end
  end

  @doc """
  Formats a timestamp as HH:MM.
  """
  @spec format_timestamp(DateTime.t()) :: String.t()
  def format_timestamp(datetime) do
    hour = datetime.hour |> Integer.to_string() |> String.pad_leading(2, "0")
    minute = datetime.minute |> Integer.to_string() |> String.pad_leading(2, "0")
    "[#{hour}:#{minute}]"
  end

  # ============================================================================
  # View Helpers - Status Bar
  # ============================================================================

  defp render_status_bar(state) do
    # Build status bar components
    config_text = format_config(state.config)
    status_text = format_status(state.agent_status)
    cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""
    reasoning_hint = if state.show_reasoning, do: "Ctrl+R: Hide", else: "Ctrl+R: Reasoning"
    hints = "#{reasoning_hint} | Ctrl+M: Model | Ctrl+C: Quit"

    # Build the full status bar text
    full_text = "#{config_text} | #{status_text}#{cot_indicator} | #{hints}"

    # Use status-aware style based on the most important state
    bar_style = build_status_bar_style(state)

    text(full_text, bar_style)
  end

  defp build_status_bar_style(state) do
    # Determine the primary color based on the most important state
    fg_color =
      cond do
        state.agent_status == :error -> :red
        state.agent_status == :unconfigured -> :red
        state.config.provider == nil -> :red
        state.config.model == nil -> :yellow
        state.agent_status == :processing -> :yellow
        has_active_reasoning?(state) -> :magenta
        true -> :white
      end

    Style.new(fg: fg_color, bg: :blue)
  end

  defp has_active_reasoning?(state) do
    state.reasoning_steps != [] and
      Enum.any?(state.reasoning_steps, fn step ->
        Map.get(step, :status) == :active
      end)
  end

  defp format_status(:idle), do: "Idle"
  defp format_status(:processing), do: "Processing..."
  defp format_status(:error), do: "Error"
  defp format_status(:unconfigured), do: "Not Configured"

  @doc """
  Returns the style for a given agent status.
  """
  def status_style(:idle), do: Style.new(fg: :green, bg: :blue)
  def status_style(:processing), do: Style.new(fg: :yellow, bg: :blue)
  def status_style(:error), do: Style.new(fg: :red, bg: :blue)
  def status_style(:unconfigured), do: Style.new(fg: :red, bg: :blue, attrs: [:dim])

  @doc """
  Returns the style for the config display based on configuration state.
  """
  def config_style(%{provider: nil}), do: Style.new(fg: :red, bg: :blue)
  def config_style(%{model: nil}), do: Style.new(fg: :yellow, bg: :blue)
  def config_style(_), do: Style.new(fg: :white, bg: :blue)

  defp format_config(%{provider: nil}), do: "No provider"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  # ============================================================================
  # View Helpers - Conversation Area
  # ============================================================================

  defp render_conversation(state) do
    {width, height} = state.window

    # Reserve 2 lines for status bar and input bar
    available_height = max(height - 2, 1)

    case state.messages do
      [] ->
        render_empty_conversation(available_height)

      messages ->
        render_messages(messages, available_height, width, state.scroll_offset)
    end
  end

  defp render_empty_conversation(_height) do
    stack(:vertical, [
      text("", nil),
      text("No messages yet. Type a message and press Enter.", Style.new(fg: :bright_black))
    ])
  end

  defp render_messages(messages, available_height, width, scroll_offset) do
    # Build message lines with text wrapping
    message_lines = Enum.flat_map(messages, &format_message(&1, width))

    total_lines = length(message_lines)

    # Calculate which lines to show based on scroll offset
    # scroll_offset of 0 = show latest, higher = show older
    end_index = total_lines - scroll_offset
    start_index = max(end_index - available_height, 0)

    visible_lines =
      message_lines
      |> Enum.slice(start_index, available_height)

    stack(:vertical, visible_lines)
  end

  defp format_message(%{role: role, content: content, timestamp: timestamp}, width) do
    ts = format_timestamp(timestamp)
    prefix = role_prefix(role)
    style = role_style(role)

    # Calculate content width accounting for prefix
    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)

    # Wrap content and format each line
    lines = wrap_text(content, content_width)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      if index == 0 do
        text("#{ts} #{prefix}#{line}", style)
      else
        # Continuation lines: indent to align with content
        padding = String.duplicate(" ", prefix_len)
        text("#{padding}#{line}", style)
      end
    end)
  end

  # Fallback for messages without timestamp (legacy format)
  defp format_message(%{role: role, content: content}, width) do
    format_message(%{role: role, content: content, timestamp: DateTime.utc_now()}, width)
  end

  defp role_prefix(:user), do: "You: "
  defp role_prefix(:assistant), do: "Assistant: "
  defp role_prefix(:system), do: "System: "

  defp role_style(:user), do: Style.new(fg: :cyan)
  defp role_style(:assistant), do: Style.new(fg: :white)
  defp role_style(:system), do: Style.new(fg: :yellow)

  # ============================================================================
  # View Helpers - Input Bar
  # ============================================================================

  defp render_input_bar(state) do
    cursor = "_"
    prompt = ">"

    text("#{prompt} #{state.input_buffer}#{cursor}", Style.new(fg: :green))
  end

  # ============================================================================
  # View Helpers - Reasoning Panel
  # ============================================================================

  @doc """
  Renders the reasoning panel showing Chain-of-Thought steps.

  Steps are displayed with status indicators:
  - ○ pending (dim)
  - ● active (yellow)
  - ✓ complete (green)
  """
  def render_reasoning(state) do
    case state.reasoning_steps do
      [] ->
        render_empty_reasoning()

      steps ->
        render_reasoning_steps(steps)
    end
  end

  defp render_empty_reasoning do
    stack(:vertical, [
      text("Reasoning (Ctrl+R to hide)", Style.new(fg: :magenta, attrs: [:bold])),
      text("─────────────────────────", Style.new(fg: :bright_black)),
      text("No reasoning steps yet.", Style.new(fg: :bright_black))
    ])
  end

  defp render_reasoning_steps(steps) do
    header = [
      text("Reasoning (Ctrl+R to hide)", Style.new(fg: :magenta, attrs: [:bold])),
      text("─────────────────────────", Style.new(fg: :bright_black))
    ]

    step_lines = Enum.map(steps, &format_reasoning_step/1)

    stack(:vertical, header ++ step_lines)
  end

  defp format_reasoning_step(%{step: step_text, status: status} = step) do
    {indicator, style} = step_indicator(status)
    confidence_text = format_confidence(step)

    text("#{indicator} #{step_text}#{confidence_text}", style)
  end

  # Handle steps that may be maps with string keys
  defp format_reasoning_step(step) when is_map(step) do
    step_text = Map.get(step, :step) || Map.get(step, "step") || "Unknown step"
    status = Map.get(step, :status) || Map.get(step, "status") || :pending
    status_atom = normalize_status(status)

    format_reasoning_step(%{step: step_text, status: status_atom, confidence: Map.get(step, :confidence)})
  end

  defp normalize_status(status) when is_atom(status), do: status
  defp normalize_status("pending"), do: :pending
  defp normalize_status("active"), do: :active
  defp normalize_status("complete"), do: :complete
  defp normalize_status(_), do: :pending

  defp step_indicator(:pending), do: {"○", Style.new(fg: :bright_black)}
  defp step_indicator(:active), do: {"●", Style.new(fg: :yellow, attrs: [:bold])}
  defp step_indicator(:complete), do: {"✓", Style.new(fg: :green)}

  defp format_confidence(%{confidence: confidence}) when is_number(confidence) do
    " (confidence: #{Float.round(confidence, 2)})"
  end

  defp format_confidence(_), do: ""

  @doc """
  Renders reasoning steps as a compact single-line display for narrow terminals.
  """
  def render_reasoning_compact(state) do
    case state.reasoning_steps do
      [] ->
        text("Reasoning: (none)", Style.new(fg: :bright_black))

      steps ->
        step_indicators =
          Enum.map_join(steps, " │ ", fn step ->
            status = Map.get(step, :status) || :pending
            {indicator, _style} = step_indicator(status)
            step_text = Map.get(step, :step) || "?"
            # Truncate step text for compact display
            short_text = String.slice(step_text, 0, 15)
            "#{indicator} #{short_text}"
          end)

        text("Reasoning: #{step_indicators}", Style.new(fg: :magenta))
    end
  end

  # ============================================================================
  # View Helpers - Configuration Screen
  # ============================================================================

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
