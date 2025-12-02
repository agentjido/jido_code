# Feature: LogViewer Conversation Area

## Problem Statement

The current conversation area in JidoCode TUI is built using basic TermUI primitives (`stack(:vertical, lines)` with `text()` nodes). This approach has limitations:

1. **No scrolling support** - Content is statically rendered, scroll offset manually managed
2. **No text selection** - Users cannot select and copy conversation content
3. **No copy functionality** - Cannot copy messages or responses to clipboard
4. **Limited scalability** - Manual line management doesn't handle large conversations efficiently
5. **No search** - Cannot search through conversation history

## Solution Overview

Replace the custom conversation rendering with TermUI's `LogViewer` widget which provides:

- Virtual scrolling for efficient rendering of large content
- Built-in selection and copy functionality
- Keyboard navigation (Up/Down, PageUp/PageDown, Home/End)
- Search with regex support and match highlighting
- Tail mode for auto-scroll during streaming responses
- Line wrapping support

### Key Design Decisions

1. **Use LogViewer widget** - Leverages existing, tested widget rather than building custom
2. **Custom parser function** - Convert messages to LogViewer's log entry format
3. **Role-based styling** - Map message roles to log levels for color coding
4. **Stateful component** - LogViewer state managed alongside other TUI state
5. **Event forwarding** - Forward scroll/selection events when conversation is focused

## Technical Details

### Files to Modify

| File | Changes |
|------|---------|
| `lib/jido_code/tui.ex` | Add LogViewer state, event handling, initialization |
| `lib/jido_code/tui/view_helpers.ex` | Update `render_conversation` to use LogViewer |

### LogViewer Configuration

```elixir
LogViewer.new(
  lines: formatted_messages,
  tail_mode: true,              # Auto-scroll during streaming
  wrap_lines: true,             # Wrap long messages
  show_line_numbers: false,     # Not needed for chat
  show_timestamps: false,       # We format our own
  show_levels: false,           # Use custom role display
  highlight_levels: false,      # Custom styling instead
  on_copy: &handle_copy/1,      # Clipboard integration
  parser: &message_parser/1     # Custom message formatting
)
```

### Message to Log Entry Mapping

```elixir
# Message format
%{role: :user | :assistant | :system, content: String.t(), timestamp: DateTime.t()}

# Log entry format
%{
  id: index,
  timestamp: message.timestamp,
  level: role_to_level(message.role),  # :info, :notice, :warning
  source: role_to_source(message.role), # "You", "Assistant", "System"
  message: message.content,
  raw: format_raw_line(message)
}
```

### Role Mapping

| Role | Level | Source Display | Color |
|------|-------|----------------|-------|
| `:user` | `:info` | "You" | green |
| `:assistant` | `:notice` | "Assistant" | blue |
| `:system` | `:warning` | "System" | yellow |

### Event Handling

Events to forward to LogViewer when conversation is focused:
- Up/Down arrows - Line navigation
- PageUp/PageDown - Page scrolling
- Home/End - Jump to start/end
- Space - Start/extend selection
- Escape - Clear selection
- `/` - Start search (optional, future)

## Success Criteria

1. ✅ Conversation content displays in LogViewer widget
2. ✅ Scrolling works with keyboard (Up/Down, PageUp/PageDown, Home/End)
3. ✅ New messages auto-scroll when in tail mode
4. ✅ Text selection works with Space key
5. ✅ Copy functionality works (system clipboard if available)
6. ✅ Streaming responses update in real-time
7. ✅ Role-based color coding preserved
8. ✅ Long messages wrap properly

## Implementation Plan

### Step 1: Add LogViewer State to Model
- [x] Add `conversation_viewer: map() | nil` to Model struct
- [x] Import/alias LogViewer widget
- [x] Initialize LogViewer in `init/1`

### Step 2: Create Message Parser
- [x] Create `message_to_log_entry/2` function
- [x] Create `messages_to_lines/1` helper
- [x] Handle tool call formatting
- [x] Handle streaming content

### Step 3: Update Conversation Rendering
- [x] Replace `render_conversation/1` to use LogViewer.render
- [x] Pass correct dimensions to LogViewer
- [x] Handle empty state

### Step 4: Event Forwarding
- [x] Update `event_to_msg/2` to check for conversation focus
- [x] Add `{:conversation_event, event}` message type
- [x] Add `update/2` handler for LogViewer events

### Step 5: Handle Message Updates
- [x] Update LogViewer content when messages change
- [x] Handle streaming chunks
- [x] Maintain scroll position or tail mode

### Step 6: Copy Functionality
- [x] Implement `on_copy` callback
- [x] Integrate with system clipboard (if available)
- [x] Fallback behavior for no clipboard access

## Current Status

- **What works**: LogViewer-based conversation display with scrolling, selection, and copy support
- **What's next**: Testing and validation
- **How to run**: `iex -S mix` then `JidoCode.TUI.run()`

## Notes/Considerations

1. **Clipboard access** - May need external tool (xclip, pbcopy) or Erlang port
2. **Performance** - LogViewer uses virtual scrolling, should handle large conversations
3. **Focus management** - Need to track when conversation area vs input is focused
4. **Tool call display** - May need special formatting in log entries
5. **Multiline messages** - Each message may span multiple log entries
