defmodule JidoCode.TUI.ViewHelpers do
  @moduledoc """
  View helper functions for TUI rendering.

  This module extracts view rendering logic from the main TUI module to improve
  maintainability. It provides functions for rendering the status bar, conversation
  area, tool calls, reasoning panel, and input bar.

  ## Rendering Components

  - Status bar: Provider/model info, agent status, keyboard hints
  - Conversation: Message history with timestamps and role indicators
  - Tool calls: Formatted tool execution entries with results
  - Reasoning: Chain-of-Thought steps with status indicators
  - Input bar: Prompt and current input buffer
  """

  import TermUI.Component.Helpers

  alias JidoCode.Tools.Display
  alias JidoCode.TUI
  alias JidoCode.TUI.Model
  alias TermUI.Renderer.Style

  # ============================================================================
  # Status Bar
  # ============================================================================

  @doc """
  Renders the status bar with config, status, CoT indicator, and keyboard hints.
  """
  @spec render_status_bar(Model.t()) :: TermUI.View.t()
  def render_status_bar(state) do
    config_text = format_config(state.config)
    status_text = format_status(state.agent_status)
    cot_indicator = if has_active_reasoning?(state), do: " [CoT]", else: ""
    reasoning_hint = if state.show_reasoning, do: "Ctrl+R: Hide", else: "Ctrl+R: Reasoning"
    tools_hint = if state.show_tool_details, do: "Ctrl+T: Hide", else: "Ctrl+T: Tools"
    hints = "#{reasoning_hint} | #{tools_hint} | Ctrl+M: Model | Ctrl+C: Quit"

    full_text = "#{config_text} | #{status_text}#{cot_indicator} | #{hints}"
    bar_style = build_status_bar_style(state)

    text(full_text, bar_style)
  end

  defp build_status_bar_style(state) do
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
  defp format_status(:processing), do: "Streaming..."
  defp format_status(:error), do: "Error"
  defp format_status(:unconfigured), do: "Not Configured"

  defp format_config(%{provider: nil}), do: "No provider"
  defp format_config(%{model: nil, provider: p}), do: "#{p} (no model)"
  defp format_config(%{provider: p, model: m}), do: "#{p}:#{m}"

  # ============================================================================
  # Conversation Area
  # ============================================================================

  @doc """
  Renders the conversation area with messages, tool calls, and streaming content.
  """
  @spec render_conversation(Model.t()) :: TermUI.View.t()
  def render_conversation(state) do
    {width, height} = state.window
    available_height = max(height - 2, 1)
    has_content = state.messages != [] or state.tool_calls != [] or state.is_streaming

    if has_content do
      render_conversation_content(state, available_height, width)
    else
      render_empty_conversation()
    end
  end

  defp render_empty_conversation do
    stack(:vertical, [
      text("", nil),
      text("No messages yet. Type a message and press Enter.", Style.new(fg: :bright_black))
    ])
  end

  defp render_conversation_content(state, available_height, width) do
    # Messages are stored in reverse order (newest first), so reverse for display
    message_lines = Enum.flat_map(Enum.reverse(state.messages), &format_message(&1, width))

    # Tool calls are stored in reverse order (newest first), so reverse for display
    tool_call_lines =
      state.tool_calls
      |> Enum.reverse()
      |> Enum.flat_map(&format_tool_call_entry(&1, state.show_tool_details))

    # Build streaming message line if streaming
    streaming_lines =
      if state.is_streaming and state.streaming_message != nil do
        format_streaming_message(state.streaming_message, width)
      else
        []
      end

    # Combine all lines (tool calls appear after messages, streaming at the end)
    all_lines = message_lines ++ tool_call_lines ++ streaming_lines
    total_lines = length(all_lines)

    # Calculate which lines to show based on scroll offset
    end_index = total_lines - state.scroll_offset
    start_index = max(end_index - available_height, 0)

    visible_lines =
      all_lines
      |> Enum.slice(start_index, available_height)

    stack(:vertical, visible_lines)
  end

  defp format_streaming_message(content, width) do
    ts = TUI.format_timestamp(DateTime.utc_now())
    prefix = "Assistant: "
    cursor = "▌"
    style = Style.new(fg: :white)

    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)
    content_with_cursor = content <> cursor

    lines = TUI.wrap_text(content_with_cursor, content_width)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      if index == 0 do
        text("#{ts} #{prefix}#{line}", style)
      else
        padding = String.duplicate(" ", prefix_len)
        text("#{padding}#{line}", style)
      end
    end)
  end

  defp format_message(%{role: role, content: content, timestamp: timestamp}, width) do
    ts = TUI.format_timestamp(timestamp)
    prefix = role_prefix(role)
    style = role_style(role)

    prefix_len = String.length("#{ts} #{prefix}")
    content_width = max(width - prefix_len, 20)
    lines = TUI.wrap_text(content, content_width)

    lines
    |> Enum.with_index()
    |> Enum.map(fn {line, index} ->
      if index == 0 do
        text("#{ts} #{prefix}#{line}", style)
      else
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
  # Tool Calls
  # ============================================================================

  @doc """
  Formats a tool call entry for display.

  Returns a list of render nodes representing the tool call and its result.
  """
  @spec format_tool_call_entry(Model.tool_call_entry(), boolean()) :: [TermUI.View.t()]
  def format_tool_call_entry(entry, show_details) do
    call_line = render_tool_call_line(entry)
    result_lines = render_tool_result_lines(entry, show_details)

    [call_line | result_lines]
  end

  defp render_tool_call_line(entry) do
    ts = TUI.format_timestamp(entry.timestamp)
    formatted = Display.format_tool_call(entry.tool_name, entry.params, entry.call_id)
    style = Style.new(fg: :bright_black)

    text("#{ts} #{formatted}", style)
  end

  defp render_tool_result_lines(%{result: nil}, _show_details) do
    [text("       ⋯ executing...", Style.new(fg: :bright_black, attrs: [:dim]))]
  end

  defp render_tool_result_lines(%{result: result}, show_details) do
    {icon, style} = tool_result_style(result.status)
    duration_text = "[#{result.duration_ms}ms]"

    content_preview =
      if show_details do
        result.content
      else
        Display.truncate_content(result.content, 80)
      end

    result_text = "       #{icon} #{result.tool_name} #{duration_text}: #{content_preview}"
    [text(result_text, style)]
  end

  defp tool_result_style(:ok), do: {"✓", Style.new(fg: :green)}
  defp tool_result_style(:error), do: {"✗", Style.new(fg: :red)}
  defp tool_result_style(:timeout), do: {"⏱", Style.new(fg: :yellow)}

  # ============================================================================
  # Input Bar
  # ============================================================================

  @doc """
  Renders the input bar with prompt indicator and current input buffer.
  """
  @spec render_input_bar(Model.t()) :: TermUI.View.t()
  def render_input_bar(state) do
    cursor = "_"
    prompt = ">"

    text("#{prompt} #{state.input_buffer}#{cursor}", Style.new(fg: :green))
  end

  # ============================================================================
  # Reasoning Panel
  # ============================================================================

  @doc """
  Renders the reasoning panel showing Chain-of-Thought steps.

  Steps are displayed with status indicators:
  - ○ pending (dim)
  - ● active (yellow)
  - ✓ complete (green)
  """
  @spec render_reasoning(Model.t()) :: TermUI.View.t()
  def render_reasoning(state) do
    case state.reasoning_steps do
      [] -> render_empty_reasoning()
      steps -> render_reasoning_steps(steps)
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

    # Steps are stored in reverse order (newest first), so reverse for display
    step_lines = Enum.map(Enum.reverse(steps), &format_reasoning_step/1)

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

    format_reasoning_step(%{
      step: step_text,
      status: status_atom,
      confidence: Map.get(step, :confidence)
    })
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
  @spec render_reasoning_compact(Model.t()) :: TermUI.View.t()
  def render_reasoning_compact(state) do
    case state.reasoning_steps do
      [] ->
        text("Reasoning: (none)", Style.new(fg: :bright_black))

      steps ->
        # Steps are stored in reverse order (newest first), so reverse for display
        step_indicators =
          Enum.map_join(Enum.reverse(steps), " │ ", fn step ->
            status = Map.get(step, :status) || :pending
            {indicator, _style} = step_indicator(status)
            step_text = Map.get(step, :step) || "?"
            short_text = String.slice(step_text, 0, 15)
            "#{indicator} #{short_text}"
          end)

        text("Reasoning: #{step_indicators}", Style.new(fg: :magenta))
    end
  end

  # ============================================================================
  # Configuration Screen
  # ============================================================================

  @doc """
  Renders the configuration information or unconfigured screen.
  """
  @spec render_config_info(Model.t()) :: TermUI.View.t()
  def render_config_info(state) do
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
