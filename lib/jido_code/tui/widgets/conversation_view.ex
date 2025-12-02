defmodule JidoCode.TUI.Widgets.ConversationView do
  @moduledoc """
  ConversationView widget for displaying scrollable chat conversations.

  A purpose-built widget for displaying chat conversations with message-aware
  rendering, role-based styling, mouse-interactive scrollbar, and collapsible
  long messages.

  ## Usage

      ConversationView.new(
        messages: [],
        max_collapsed_lines: 15,
        show_timestamps: true
      )

  ## Features

  - Virtual scrolling for efficient rendering
  - Role-based styling (user, assistant, system)
  - Text wrapping at word boundaries
  - Collapsible long messages with truncation indicator
  - Mouse wheel and scrollbar drag support
  - Streaming message support with auto-scroll
  - Copy functionality for focused message

  ## Keyboard Controls

  - Up/Down: Scroll by line
  - PageUp/PageDown: Scroll by page
  - Home/End: Jump to top/bottom
  - Ctrl+Up/Down: Move message focus
  - Space: Toggle expand on focused message
  - e: Expand all messages
  - c: Collapse all messages
  - y: Copy focused message
  """

  use TermUI.StatefulComponent

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @typedoc "Message role indicating who sent the message"
  @type role :: :user | :assistant | :system

  @typedoc "A chat message with metadata"
  @type message :: %{
          id: String.t(),
          role: role(),
          content: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc "Role styling configuration"
  @type role_style :: %{
          name: String.t(),
          color: atom()
        }

  @typedoc "Internal widget state"
  @type state :: %{
          # Messages
          messages: [message()],
          # Scroll state
          scroll_offset: non_neg_integer(),
          viewport_height: pos_integer(),
          viewport_width: pos_integer(),
          total_lines: non_neg_integer(),
          # Expansion state
          expanded: MapSet.t(String.t()),
          # Focus state
          cursor_message_idx: non_neg_integer(),
          # Mouse drag state
          dragging: boolean(),
          drag_start_y: non_neg_integer() | nil,
          drag_start_offset: non_neg_integer() | nil,
          # Streaming state
          streaming_id: String.t() | nil,
          was_at_bottom: boolean(),
          # Configuration
          max_collapsed_lines: pos_integer(),
          show_timestamps: boolean(),
          scrollbar_width: pos_integer(),
          indent: pos_integer(),
          scroll_lines: pos_integer(),
          role_styles: %{role() => role_style()},
          on_copy: (String.t() -> any()) | nil
        }

  @default_role_styles %{
    user: %{name: "You", color: :green},
    assistant: %{name: "Assistant", color: :cyan},
    system: %{name: "System", color: :yellow}
  }

  # ============================================================================
  # Props
  # ============================================================================

  @doc """
  Creates new ConversationView widget props.

  ## Options

  - `:messages` - Initial messages (default: [])
  - `:max_collapsed_lines` - Lines before truncation (default: 15)
  - `:show_timestamps` - Show [HH:MM] prefix (default: true)
  - `:scrollbar_width` - Scrollbar column width (default: 2)
  - `:indent` - Content indent spaces (default: 2)
  - `:scroll_lines` - Lines to scroll per wheel event (default: 3)
  - `:role_styles` - Per-role styling configuration
  - `:on_copy` - Clipboard callback function
  """
  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    %{
      messages: Keyword.get(opts, :messages, []),
      max_collapsed_lines: Keyword.get(opts, :max_collapsed_lines, 15),
      show_timestamps: Keyword.get(opts, :show_timestamps, true),
      scrollbar_width: Keyword.get(opts, :scrollbar_width, 2),
      indent: Keyword.get(opts, :indent, 2),
      scroll_lines: Keyword.get(opts, :scroll_lines, 3),
      role_styles: Keyword.get(opts, :role_styles, @default_role_styles),
      on_copy: Keyword.get(opts, :on_copy)
    }
  end

  # ============================================================================
  # StatefulComponent Callbacks
  # ============================================================================

  @impl true
  def init(props) do
    messages = props.messages

    state = %{
      # Messages
      messages: messages,
      # Scroll state
      scroll_offset: 0,
      viewport_height: 20,
      viewport_width: 80,
      total_lines: calculate_total_lines(messages, props.max_collapsed_lines, MapSet.new(), 80),
      # Expansion state
      expanded: MapSet.new(),
      # Focus state
      cursor_message_idx: 0,
      # Mouse drag state
      dragging: false,
      drag_start_y: nil,
      drag_start_offset: nil,
      # Streaming state
      streaming_id: nil,
      was_at_bottom: true,
      # Configuration (from props)
      max_collapsed_lines: props.max_collapsed_lines,
      show_timestamps: props.show_timestamps,
      scrollbar_width: props.scrollbar_width,
      indent: props.indent,
      scroll_lines: props.scroll_lines,
      role_styles: props.role_styles,
      on_copy: props.on_copy
    }

    {:ok, state}
  end

  @impl true
  def handle_event(_event, state) do
    # Event handling will be implemented in Section 9.4/9.5
    {:ok, state}
  end

  @impl true
  def render(state, area) do
    # Rendering will be implemented in Section 9.2/9.3
    # For now, return a simple placeholder
    _state = %{
      state
      | viewport_height: area.height,
        viewport_width: area.width
    }

    text("ConversationView placeholder", nil)
  end

  # ============================================================================
  # Public API - Message Management
  # ============================================================================

  @doc """
  Adds a message to the conversation.

  Appends the message to the end and recalculates total lines.
  If currently at the bottom, auto-scrolls to show the new message.
  """
  @spec add_message(state(), message()) :: state()
  def add_message(state, message) do
    messages = state.messages ++ [message]
    was_at_bottom = at_bottom?(state)

    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        state.expanded,
        state.viewport_width
      )

    state = %{state | messages: messages, total_lines: new_total_lines}

    # Auto-scroll if was at bottom
    if was_at_bottom do
      scroll_to(state, :bottom)
    else
      state
    end
  end

  @doc """
  Replaces all messages in the conversation.

  Resets scroll position to the top.
  """
  @spec set_messages(state(), [message()]) :: state()
  def set_messages(state, messages) do
    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        MapSet.new(),
        state.viewport_width
      )

    %{
      state
      | messages: messages,
        total_lines: new_total_lines,
        scroll_offset: 0,
        cursor_message_idx: 0,
        expanded: MapSet.new()
    }
  end

  @doc """
  Clears all messages from the conversation.

  Resets all state to initial values.
  """
  @spec clear(state()) :: state()
  def clear(state) do
    %{
      state
      | messages: [],
        total_lines: 0,
        scroll_offset: 0,
        cursor_message_idx: 0,
        expanded: MapSet.new(),
        streaming_id: nil
    }
  end

  @doc """
  Appends content to an existing message by ID.

  Used for streaming responses where content arrives incrementally.
  Auto-scrolls if `was_at_bottom` is true in state.
  """
  @spec append_to_message(state(), String.t(), String.t()) :: state()
  def append_to_message(state, message_id, content) do
    messages =
      Enum.map(state.messages, fn msg ->
        if msg.id == message_id do
          %{msg | content: msg.content <> content}
        else
          msg
        end
      end)

    new_total_lines =
      calculate_total_lines(
        messages,
        state.max_collapsed_lines,
        state.expanded,
        state.viewport_width
      )

    state = %{state | messages: messages, total_lines: new_total_lines}

    # Auto-scroll if was at bottom when streaming started
    if state.was_at_bottom do
      scroll_to(state, :bottom)
    else
      state
    end
  end

  # ============================================================================
  # Public API - Expansion
  # ============================================================================

  @doc """
  Toggles the expanded state for a message.

  Expanded messages show full content; collapsed messages are truncated.
  """
  @spec toggle_expand(state(), String.t()) :: state()
  def toggle_expand(state, message_id) do
    expanded =
      if MapSet.member?(state.expanded, message_id) do
        MapSet.delete(state.expanded, message_id)
      else
        MapSet.put(state.expanded, message_id)
      end

    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        expanded,
        state.viewport_width
      )

    %{state | expanded: expanded, total_lines: new_total_lines}
  end

  @doc """
  Expands all messages that are currently truncated.
  """
  @spec expand_all(state()) :: state()
  def expand_all(state) do
    expanded = state.messages |> Enum.map(& &1.id) |> MapSet.new()

    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        expanded,
        state.viewport_width
      )

    %{state | expanded: expanded, total_lines: new_total_lines}
  end

  @doc """
  Collapses all expanded messages.
  """
  @spec collapse_all(state()) :: state()
  def collapse_all(state) do
    new_total_lines =
      calculate_total_lines(
        state.messages,
        state.max_collapsed_lines,
        MapSet.new(),
        state.viewport_width
      )

    # Also clamp scroll offset since total_lines decreased
    max_offset = max_scroll_offset(%{state | total_lines: new_total_lines})
    scroll_offset = min(state.scroll_offset, max_offset)

    %{state | expanded: MapSet.new(), total_lines: new_total_lines, scroll_offset: scroll_offset}
  end

  # ============================================================================
  # Public API - Scrolling
  # ============================================================================

  @doc """
  Scrolls to a specific position.

  ## Positions

  - `:top` - Scroll to the beginning
  - `:bottom` - Scroll to the end
  - `{:message, id}` - Scroll to make a specific message visible
  """
  @spec scroll_to(state(), :top | :bottom | {:message, String.t()}) :: state()
  def scroll_to(state, :top) do
    %{state | scroll_offset: 0}
  end

  def scroll_to(state, :bottom) do
    max_offset = max_scroll_offset(state)
    %{state | scroll_offset: max_offset}
  end

  def scroll_to(state, {:message, message_id}) do
    # Find the message index
    case Enum.find_index(state.messages, &(&1.id == message_id)) do
      nil ->
        state

      idx ->
        # Calculate cumulative lines to this message
        lines_before =
          state.messages
          |> Enum.take(idx)
          |> Enum.reduce(0, fn msg, acc ->
            acc + message_line_count(msg, state.max_collapsed_lines, state.expanded, state.viewport_width)
          end)

        # Scroll to put message at top of viewport
        offset = min(lines_before, max_scroll_offset(state))
        %{state | scroll_offset: offset, cursor_message_idx: idx}
    end
  end

  @doc """
  Scrolls by a relative number of lines.

  Positive values scroll down, negative values scroll up.
  """
  @spec scroll_by(state(), integer()) :: state()
  def scroll_by(state, delta) do
    new_offset = state.scroll_offset + delta
    clamped_offset = clamp_scroll(new_offset, state)
    %{state | scroll_offset: clamped_offset}
  end

  # ============================================================================
  # Public API - Selection
  # ============================================================================

  @doc """
  Gets the content of the currently focused message.

  Returns empty string if no message is focused.
  """
  @spec get_selected_text(state()) :: String.t()
  def get_selected_text(state) do
    case Enum.at(state.messages, state.cursor_message_idx) do
      nil -> ""
      msg -> msg.content
    end
  end

  # ============================================================================
  # Public API - Streaming
  # ============================================================================

  @doc """
  Starts streaming mode for a new message.

  Creates a placeholder message and tracks streaming state.
  """
  @spec start_streaming(state(), role()) :: {state(), String.t()}
  def start_streaming(state, role) do
    message_id = generate_id()

    message = %{
      id: message_id,
      role: role,
      content: "",
      timestamp: DateTime.utc_now()
    }

    was_at_bottom = at_bottom?(state)
    state = add_message(state, message)

    {%{state | streaming_id: message_id, was_at_bottom: was_at_bottom}, message_id}
  end

  @doc """
  Ends streaming mode.

  Clears the streaming_id and resets was_at_bottom.
  """
  @spec end_streaming(state()) :: state()
  def end_streaming(state) do
    %{state | streaming_id: nil, was_at_bottom: false}
  end

  @doc """
  Appends a chunk to the currently streaming message.

  No-op if not in streaming mode.
  """
  @spec append_chunk(state(), String.t()) :: state()
  def append_chunk(state, chunk) do
    case state.streaming_id do
      nil -> state
      id -> append_to_message(state, id, chunk)
    end
  end

  # ============================================================================
  # Public API - Accessors
  # ============================================================================

  @doc """
  Returns whether the view is currently at the bottom.
  """
  @spec at_bottom?(state()) :: boolean()
  def at_bottom?(state) do
    state.scroll_offset >= max_scroll_offset(state)
  end

  @doc """
  Returns the maximum scroll offset.
  """
  @spec max_scroll_offset(state()) :: non_neg_integer()
  def max_scroll_offset(state) do
    max(0, state.total_lines - state.viewport_height)
  end

  @doc """
  Returns whether a message is currently expanded.
  """
  @spec expanded?(state(), String.t()) :: boolean()
  def expanded?(state, message_id) do
    MapSet.member?(state.expanded, message_id)
  end

  @doc """
  Returns the number of messages.
  """
  @spec message_count(state()) :: non_neg_integer()
  def message_count(state) do
    length(state.messages)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp calculate_total_lines(messages, max_collapsed, expanded, viewport_width) do
    Enum.reduce(messages, 0, fn msg, acc ->
      acc + message_line_count(msg, max_collapsed, expanded, viewport_width)
    end)
  end

  defp message_line_count(msg, max_collapsed, expanded, viewport_width) do
    # Header line + content lines + separator
    content_lines = count_wrapped_lines(msg.content, viewport_width - 4)

    display_lines =
      if MapSet.member?(expanded, msg.id) or content_lines <= max_collapsed do
        content_lines
      else
        # Show truncated version: max_collapsed - 1 lines + truncation indicator
        max_collapsed
      end

    # 1 for header + display_lines + 1 for separator
    1 + display_lines + 1
  end

  defp count_wrapped_lines("", _width), do: 1

  defp count_wrapped_lines(text, width) when width <= 0, do: 1

  defp count_wrapped_lines(text, width) do
    text
    |> String.split("\n")
    |> Enum.reduce(0, fn line, acc ->
      line_len = String.length(line)

      if line_len == 0 do
        acc + 1
      else
        acc + ceil(line_len / width)
      end
    end)
  end

  defp clamp_scroll(offset, state) do
    max_offset = max_scroll_offset(state)
    max(0, min(offset, max_offset))
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
