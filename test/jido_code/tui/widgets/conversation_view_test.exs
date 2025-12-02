defmodule JidoCode.TUI.Widgets.ConversationViewTest do
  use ExUnit.Case, async: true

  alias JidoCode.TUI.Widgets.ConversationView

  # ============================================================================
  # Test Helpers
  # ============================================================================

  defp make_message(id, role, content) do
    %{
      id: id,
      role: role,
      content: content,
      timestamp: DateTime.utc_now()
    }
  end

  defp init_state(opts \\ []) do
    props = ConversationView.new(opts)
    {:ok, state} = ConversationView.init(props)
    state
  end

  # ============================================================================
  # new/1 Tests
  # ============================================================================

  describe "new/1" do
    test "returns valid props with defaults" do
      props = ConversationView.new()

      assert props.messages == []
      assert props.max_collapsed_lines == 15
      assert props.show_timestamps == true
      assert props.scrollbar_width == 2
      assert props.indent == 2
      assert props.scroll_lines == 3
      assert is_map(props.role_styles)
      assert props.on_copy == nil
    end

    test "with custom messages" do
      messages = [make_message("1", :user, "Hello")]
      props = ConversationView.new(messages: messages)

      assert props.messages == messages
    end

    test "with custom max_collapsed_lines" do
      props = ConversationView.new(max_collapsed_lines: 20)

      assert props.max_collapsed_lines == 20
    end

    test "with show_timestamps disabled" do
      props = ConversationView.new(show_timestamps: false)

      assert props.show_timestamps == false
    end

    test "with custom scrollbar_width" do
      props = ConversationView.new(scrollbar_width: 3)

      assert props.scrollbar_width == 3
    end

    test "with custom indent" do
      props = ConversationView.new(indent: 4)

      assert props.indent == 4
    end

    test "with custom scroll_lines" do
      props = ConversationView.new(scroll_lines: 5)

      assert props.scroll_lines == 5
    end

    test "with custom role_styles" do
      custom_styles = %{
        user: %{name: "Me", color: :blue},
        assistant: %{name: "Bot", color: :green},
        system: %{name: "Sys", color: :red}
      }

      props = ConversationView.new(role_styles: custom_styles)

      assert props.role_styles == custom_styles
    end

    test "with on_copy callback" do
      callback = fn _text -> :ok end
      props = ConversationView.new(on_copy: callback)

      assert props.on_copy == callback
    end
  end

  # ============================================================================
  # init/1 Tests
  # ============================================================================

  describe "init/1" do
    test "creates valid state from props" do
      state = init_state()

      assert state.messages == []
      assert state.scroll_offset == 0
      assert state.viewport_height == 20
      assert state.viewport_width == 80
      assert state.expanded == MapSet.new()
      assert state.cursor_message_idx == 0
      assert state.dragging == false
      assert state.streaming_id == nil
    end

    test "initializes with provided messages" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi there!")
      ]

      state = init_state(messages: messages)

      assert state.messages == messages
      assert length(state.messages) == 2
    end

    test "calculates correct total_lines for empty messages" do
      state = init_state()

      assert state.total_lines == 0
    end

    test "calculates correct total_lines for messages" do
      # Each message = 1 header + content lines + 1 separator
      # Short message: 1 header + 1 content + 1 separator = 3 lines
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      # 2 messages * 3 lines each = 6 lines
      assert state.total_lines == 6
    end

    test "preserves config from props" do
      state = init_state(
        max_collapsed_lines: 10,
        show_timestamps: false,
        scrollbar_width: 3,
        indent: 4,
        scroll_lines: 5
      )

      assert state.max_collapsed_lines == 10
      assert state.show_timestamps == false
      assert state.scrollbar_width == 3
      assert state.indent == 4
      assert state.scroll_lines == 5
    end
  end

  # ============================================================================
  # add_message/2 Tests
  # ============================================================================

  describe "add_message/2" do
    test "appends message to empty state" do
      state = init_state()
      message = make_message("1", :user, "Hello")

      state = ConversationView.add_message(state, message)

      assert length(state.messages) == 1
      assert hd(state.messages).content == "Hello"
    end

    test "appends message to existing messages" do
      state = init_state(messages: [make_message("1", :user, "First")])
      message = make_message("2", :assistant, "Second")

      state = ConversationView.add_message(state, message)

      assert length(state.messages) == 2
      assert List.last(state.messages).content == "Second"
    end

    test "updates total_lines" do
      state = init_state()
      initial_lines = state.total_lines

      message = make_message("1", :user, "Hello")
      state = ConversationView.add_message(state, message)

      assert state.total_lines > initial_lines
    end

    test "auto-scrolls when at bottom" do
      state = init_state()
      # Start at bottom (scroll_offset 0 with empty messages is at bottom)
      assert ConversationView.at_bottom?(state)

      message = make_message("1", :user, "Hello")
      state = ConversationView.add_message(state, message)

      # Should still be at bottom after adding
      assert ConversationView.at_bottom?(state)
    end
  end

  # ============================================================================
  # set_messages/2 Tests
  # ============================================================================

  describe "set_messages/2" do
    test "replaces all messages" do
      state = init_state(messages: [make_message("1", :user, "Old")])
      new_messages = [
        make_message("2", :user, "New1"),
        make_message("3", :assistant, "New2")
      ]

      state = ConversationView.set_messages(state, new_messages)

      assert length(state.messages) == 2
      assert hd(state.messages).content == "New1"
    end

    test "resets scroll_offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 100}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.scroll_offset == 0
    end

    test "resets cursor_message_idx to 0" do
      state = init_state()
      state = %{state | cursor_message_idx: 5}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.cursor_message_idx == 0
    end

    test "clears expanded set" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2", "3"])}

      state = ConversationView.set_messages(state, [make_message("1", :user, "Test")])

      assert state.expanded == MapSet.new()
    end

    test "recalculates total_lines" do
      state = init_state()
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "World")
      ]

      state = ConversationView.set_messages(state, messages)

      # Each message = 3 lines, so 2 messages = 6 lines
      assert state.total_lines == 6
    end
  end

  # ============================================================================
  # clear/1 Tests
  # ============================================================================

  describe "clear/1" do
    test "empties messages" do
      state = init_state(messages: [make_message("1", :user, "Test")])

      state = ConversationView.clear(state)

      assert state.messages == []
    end

    test "resets total_lines to 0" do
      state = init_state(messages: [make_message("1", :user, "Test")])

      state = ConversationView.clear(state)

      assert state.total_lines == 0
    end

    test "resets scroll_offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 50}

      state = ConversationView.clear(state)

      assert state.scroll_offset == 0
    end

    test "resets cursor_message_idx to 0" do
      state = init_state()
      state = %{state | cursor_message_idx: 5}

      state = ConversationView.clear(state)

      assert state.cursor_message_idx == 0
    end

    test "clears expanded set" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2"])}

      state = ConversationView.clear(state)

      assert state.expanded == MapSet.new()
    end

    test "clears streaming_id" do
      state = init_state()
      state = %{state | streaming_id: "stream-1"}

      state = ConversationView.clear(state)

      assert state.streaming_id == nil
    end
  end

  # ============================================================================
  # append_to_message/3 Tests
  # ============================================================================

  describe "append_to_message/3" do
    test "appends content to correct message" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      state = ConversationView.append_to_message(state, "2", " there!")

      msg = Enum.find(state.messages, &(&1.id == "2"))
      assert msg.content == "Hi there!"
    end

    test "does not modify other messages" do
      messages = [
        make_message("1", :user, "Hello"),
        make_message("2", :assistant, "Hi")
      ]

      state = init_state(messages: messages)

      state = ConversationView.append_to_message(state, "2", " there!")

      msg1 = Enum.find(state.messages, &(&1.id == "1"))
      assert msg1.content == "Hello"
    end

    test "updates total_lines" do
      state = init_state(messages: [make_message("1", :user, "Hi")])
      initial_lines = state.total_lines

      # Add enough content to create new lines
      long_content = String.duplicate("x", 200)
      state = ConversationView.append_to_message(state, "1", long_content)

      assert state.total_lines > initial_lines
    end

    test "no-op for non-existent message id" do
      state = init_state(messages: [make_message("1", :user, "Hello")])

      state = ConversationView.append_to_message(state, "nonexistent", "extra")

      msg = Enum.find(state.messages, &(&1.id == "1"))
      assert msg.content == "Hello"
    end
  end

  # ============================================================================
  # toggle_expand/2 Tests
  # ============================================================================

  describe "toggle_expand/2" do
    test "adds message id to expanded set" do
      state = init_state()

      state = ConversationView.toggle_expand(state, "1")

      assert MapSet.member?(state.expanded, "1")
    end

    test "removes message id from expanded set when already expanded" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1"])}

      state = ConversationView.toggle_expand(state, "1")

      refute MapSet.member?(state.expanded, "1")
    end

    test "recalculates total_lines after toggle" do
      # Create a long message that will be truncated
      long_content = String.duplicate("Line\n", 30)
      messages = [make_message("1", :user, long_content)]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      collapsed_lines = state.total_lines

      state = ConversationView.toggle_expand(state, "1")
      expanded_lines = state.total_lines

      # Expanded should have more lines
      assert expanded_lines > collapsed_lines
    end
  end

  # ============================================================================
  # expand_all/1 and collapse_all/1 Tests
  # ============================================================================

  describe "expand_all/1" do
    test "expands all messages" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)

      state = ConversationView.expand_all(state)

      assert MapSet.member?(state.expanded, "1")
      assert MapSet.member?(state.expanded, "2")
    end
  end

  describe "collapse_all/1" do
    test "collapses all expanded messages" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1", "2", "3"])}

      state = ConversationView.collapse_all(state)

      assert state.expanded == MapSet.new()
    end

    test "clamps scroll_offset when total_lines decreases" do
      long_content = String.duplicate("Line\n", 50)
      messages = [make_message("1", :user, long_content)]

      state = init_state(messages: messages, max_collapsed_lines: 5)
      state = ConversationView.expand_all(state)
      state = ConversationView.scroll_to(state, :bottom)
      expanded_offset = state.scroll_offset

      state = ConversationView.collapse_all(state)

      # Scroll offset should be clamped to valid range
      assert state.scroll_offset <= ConversationView.max_scroll_offset(state)
      assert state.scroll_offset < expanded_offset
    end
  end

  # ============================================================================
  # scroll_to/2 Tests
  # ============================================================================

  describe "scroll_to/2" do
    test "scrolls to :top sets offset to 0" do
      state = init_state()
      state = %{state | scroll_offset: 100}

      state = ConversationView.scroll_to(state, :top)

      assert state.scroll_offset == 0
    end

    test "scrolls to :bottom sets offset to max" do
      messages = Enum.map(1..10, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_to(state, :bottom)

      assert state.scroll_offset == ConversationView.max_scroll_offset(state)
    end

    test "scrolls to {:message, id} makes message visible" do
      messages = Enum.map(1..10, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_to(state, {:message, "5"})

      # Message 5 should now be visible (scroll offset adjusted)
      assert state.cursor_message_idx == 4  # 0-indexed
    end

    test "scroll to non-existent message is no-op" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      original_offset = state.scroll_offset

      state = ConversationView.scroll_to(state, {:message, "nonexistent"})

      assert state.scroll_offset == original_offset
    end
  end

  # ============================================================================
  # scroll_by/2 Tests
  # ============================================================================

  describe "scroll_by/2" do
    test "scrolls down by positive delta" do
      messages = Enum.map(1..20, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}

      state = ConversationView.scroll_by(state, 5)

      assert state.scroll_offset == 5
    end

    test "scrolls up by negative delta" do
      messages = Enum.map(1..20, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 10}

      state = ConversationView.scroll_by(state, -3)

      assert state.scroll_offset == 7
    end

    test "clamps to 0 for negative scroll" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      state = %{state | scroll_offset: 2}

      state = ConversationView.scroll_by(state, -100)

      assert state.scroll_offset == 0
    end

    test "clamps to max_scroll_offset for overshooting" do
      messages = Enum.map(1..10, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5}
      max_offset = ConversationView.max_scroll_offset(state)

      state = ConversationView.scroll_by(state, 1000)

      assert state.scroll_offset == max_offset
    end
  end

  # ============================================================================
  # get_selected_text/1 Tests
  # ============================================================================

  describe "get_selected_text/1" do
    test "returns content of focused message" do
      messages = [
        make_message("1", :user, "First message"),
        make_message("2", :assistant, "Second message")
      ]

      state = init_state(messages: messages)
      state = %{state | cursor_message_idx: 1}

      text = ConversationView.get_selected_text(state)

      assert text == "Second message"
    end

    test "returns empty string when no messages" do
      state = init_state()

      text = ConversationView.get_selected_text(state)

      assert text == ""
    end

    test "returns empty string for out of bounds cursor" do
      state = init_state(messages: [make_message("1", :user, "Test")])
      state = %{state | cursor_message_idx: 100}

      text = ConversationView.get_selected_text(state)

      assert text == ""
    end
  end

  # ============================================================================
  # Streaming API Tests
  # ============================================================================

  describe "start_streaming/2" do
    test "creates a new message with empty content" do
      state = init_state()

      {state, _id} = ConversationView.start_streaming(state, :assistant)

      assert length(state.messages) == 1
      assert hd(state.messages).content == ""
      assert hd(state.messages).role == :assistant
    end

    test "returns the message id" do
      state = init_state()

      {_state, id} = ConversationView.start_streaming(state, :assistant)

      assert is_binary(id)
      assert String.length(id) > 0
    end

    test "sets streaming_id in state" do
      state = init_state()

      {state, id} = ConversationView.start_streaming(state, :assistant)

      assert state.streaming_id == id
    end

    test "captures was_at_bottom" do
      state = init_state()
      assert ConversationView.at_bottom?(state)

      {state, _id} = ConversationView.start_streaming(state, :assistant)

      assert state.was_at_bottom == true
    end
  end

  describe "end_streaming/1" do
    test "clears streaming_id" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.end_streaming(state)

      assert state.streaming_id == nil
    end

    test "resets was_at_bottom" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.end_streaming(state)

      assert state.was_at_bottom == false
    end
  end

  describe "append_chunk/2" do
    test "appends to streaming message" do
      state = init_state()
      {state, _id} = ConversationView.start_streaming(state, :assistant)

      state = ConversationView.append_chunk(state, "Hello ")
      state = ConversationView.append_chunk(state, "World!")

      msg = hd(state.messages)
      assert msg.content == "Hello World!"
    end

    test "no-op when not streaming" do
      messages = [make_message("1", :user, "Test")]
      state = init_state(messages: messages)

      state = ConversationView.append_chunk(state, "extra")

      msg = hd(state.messages)
      assert msg.content == "Test"
    end
  end

  # ============================================================================
  # Accessor Tests
  # ============================================================================

  describe "at_bottom?/1" do
    test "returns true when at bottom" do
      state = init_state()

      assert ConversationView.at_bottom?(state)
    end

    test "returns false when not at bottom" do
      messages = Enum.map(1..20, fn i ->
        make_message("#{i}", :user, "Message #{i}")
      end)

      state = init_state(messages: messages)
      state = %{state | viewport_height: 5, scroll_offset: 0}

      refute ConversationView.at_bottom?(state)
    end
  end

  describe "expanded?/2" do
    test "returns true for expanded message" do
      state = init_state()
      state = %{state | expanded: MapSet.new(["1"])}

      assert ConversationView.expanded?(state, "1")
    end

    test "returns false for collapsed message" do
      state = init_state()

      refute ConversationView.expanded?(state, "1")
    end
  end

  describe "message_count/1" do
    test "returns 0 for empty state" do
      state = init_state()

      assert ConversationView.message_count(state) == 0
    end

    test "returns correct count" do
      messages = [
        make_message("1", :user, "First"),
        make_message("2", :assistant, "Second")
      ]

      state = init_state(messages: messages)

      assert ConversationView.message_count(state) == 2
    end
  end
end
