defmodule JidoCode.Memory.ContextBuilder do
  @moduledoc """
  Builds memory-enhanced context for LLM prompts.

  Combines:
  - Working context (current session state)
  - Long-term memories (relevant persisted knowledge)

  Respects token budget allocation and prioritizes content
  based on relevance and recency.

  ## Usage

      # Build context for a session
      {:ok, context} = ContextBuilder.build(session_id)

      # Build with custom token budget
      {:ok, context} = ContextBuilder.build(session_id,
        token_budget: %{total: 16_000, ...}
      )

      # Build with query hint to adjust memory retrieval strategy
      {:ok, context} = ContextBuilder.build(session_id,
        query_hint: "user asked about Phoenix patterns"
      )

      # Format context for inclusion in system prompt
      prompt_text = ContextBuilder.format_for_prompt(context)

  ## Token Budget

  The builder respects token budgets for each context component:
  - `system`: Reserved for system instructions
  - `conversation`: Message history
  - `working`: Current session working context
  - `long_term`: Memories from long-term storage

  When a component exceeds its budget, content is truncated with
  priority given to more recent/relevant items.

  ## Query Hint Behavior

  When `query_hint` is provided, the builder retrieves more memories (up to 10)
  assuming the caller will perform relevance filtering. Without a hint, it retrieves
  fewer memories (up to 5) but with a higher minimum confidence threshold (0.7).

  Note: The hint itself is not currently used for relevance scoring; it only
  affects the query strategy (limit vs confidence filter).
  """

  require Logger

  alias JidoCode.Memory
  alias JidoCode.Memory.Summarizer
  alias JidoCode.Memory.TokenCounter
  alias JidoCode.Memory.Types
  alias JidoCode.Session.State

  # =============================================================================
  # Types
  # =============================================================================

  # Note: For message type, use Types.message() from the shared types module.
  # For stored_memory type, use Memory.stored_memory() directly.

  @typedoc """
  Token budget allocation for context components.
  """
  @type token_budget :: %{
          total: pos_integer(),
          system: pos_integer(),
          conversation: pos_integer(),
          working: pos_integer(),
          long_term: pos_integer()
        }

  @typedoc """
  Token counts for each context component.
  """
  @type token_counts :: %{
          conversation: non_neg_integer(),
          working: non_neg_integer(),
          long_term: non_neg_integer(),
          total: non_neg_integer()
        }

  @typedoc """
  The assembled context structure.
  """
  @type context :: %{
          conversation: [Types.message()],
          working_context: map(),
          long_term_memories: [Memory.stored_memory()],
          system_context: String.t() | nil,
          token_counts: token_counts()
        }

  # =============================================================================
  # Constants
  # =============================================================================

  @default_budget %{
    total: 32_000,
    system: 2_000,
    conversation: 20_000,
    working: 4_000,
    long_term: 6_000
  }

  # Default limits for memory queries
  @default_memory_limit 10
  @high_confidence_limit 5
  @high_confidence_threshold 0.7

  # Maximum content length for formatted output (security limit)
  @max_content_display_length 2000

  # Summary cache key for storing summarized conversations
  # Imported from Types to make coupling explicit (see Types.summary_cache_key/0)
  @summary_cache_key Types.summary_cache_key()

  # Precompiled sanitization regexes for performance (Concern #5)
  # These patterns detect common LLM jailbreak/prompt injection attempts
  @regex_ignore_instructions ~r/\bignore\s+(all\s+)?previous\s+instructions?\b/i
  @regex_you_are_now ~r/\byou\s+are\s+now\b/i
  @regex_forget_previous ~r/\bforget\s+(all\s+)?previous\b/i
  @regex_system_role ~r/\bsystem\s*:\s*/i
  @regex_user_role ~r/\buser\s*:\s*/i
  @regex_assistant_role ~r/\bassistant\s*:\s*/i

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Returns the default token budget configuration.
  """
  @spec default_budget() :: token_budget()
  def default_budget, do: @default_budget

  @doc """
  Returns the characters per token ratio used for estimation.

  Delegates to `TokenCounter.chars_per_token/0` for consistency.
  """
  @spec chars_per_token() :: pos_integer()
  defdelegate chars_per_token, to: TokenCounter

  @doc """
  Allocates a token budget based on a total token count.

  Distributes tokens across context components with the following ratios:
  - `system`: ~6% (capped at 2,000)
  - `conversation`: ~62.5%
  - `working`: ~12.5%
  - `long_term`: ~19%

  These ratios prioritize conversation history as the primary context source,
  with working context and long-term memories providing supplementary information.

  ## Parameters

  - `total` - Total tokens to allocate

  ## Returns

  A token budget map with allocations for each component.

  ## Examples

      iex> ContextBuilder.allocate_budget(32_000)
      %{total: 32_000, system: 2_000, conversation: 20_000, working: 4_000, long_term: 6_000}

      iex> ContextBuilder.allocate_budget(16_000)
      %{total: 16_000, system: 1_000, conversation: 10_000, working: 2_000, long_term: 3_000}

  """
  @spec allocate_budget(pos_integer()) :: token_budget()
  def allocate_budget(total) when is_integer(total) and total > 0 do
    %{
      total: total,
      # ~6% but capped at 2,000
      system: min(2_000, div(total, 16)),
      # ~62.5%
      conversation: div(total * 5, 8),
      # ~12.5%
      working: div(total, 8),
      # ~19%
      long_term: div(total * 3, 16)
    }
  end

  def allocate_budget(invalid) do
    Logger.warning("ContextBuilder: Invalid budget total #{inspect(invalid)}, using default")
    @default_budget
  end

  @doc """
  Validates a token budget map.

  Returns `true` if all required keys are present with positive integer values.

  ## Examples

      iex> ContextBuilder.valid_token_budget?(%{total: 32_000, system: 2_000, conversation: 20_000, working: 4_000, long_term: 6_000})
      true

      iex> ContextBuilder.valid_token_budget?(%{total: -1, system: 2_000, conversation: 20_000, working: 4_000, long_term: 6_000})
      false

  """
  @spec valid_token_budget?(term()) :: boolean()
  def valid_token_budget?(%{total: t, system: s, conversation: c, working: w, long_term: l})
      when is_integer(t) and is_integer(s) and is_integer(c) and is_integer(w) and is_integer(l) and
             t > 0 and s >= 0 and c >= 0 and w >= 0 and l >= 0,
      do: true

  def valid_token_budget?(_), do: false

  @doc """
  Builds a memory-enhanced context for the given session.

  ## Options

  - `:token_budget` - Custom token budget (default: `default_budget()`)
  - `:query_hint` - Optional text hint to adjust memory retrieval strategy.
    When provided, retrieves more memories (limit: 10). When absent, retrieves
    fewer memories with higher confidence threshold (min_confidence: 0.7, limit: 5).
    Note: The hint does not perform relevance scoring.
  - `:include_memories` - Whether to include long-term memories (default: true)
  - `:include_conversation` - Whether to include conversation history (default: true)
  - `:force_summarize` - Force re-summarization, bypassing cache (default: false)

  ## Summarization

  When conversation history exceeds the token budget, it is automatically
  summarized using extractive summarization. The summary is cached to avoid
  redundant computation. The cache is invalidated when new messages are added.

  ## Returns

  - `{:ok, context}` - Successfully assembled context
  - `{:error, :session_not_found}` - Session doesn't exist
  - `{:error, reason}` - Other errors

  ## Examples

      {:ok, context} = ContextBuilder.build("session-123")

      {:ok, context} = ContextBuilder.build("session-123",
        query_hint: "how do I configure authentication?",
        token_budget: %{total: 16_000, system: 1_000, conversation: 10_000, working: 2_000, long_term: 3_000}
      )

      # Force re-summarization
      {:ok, context} = ContextBuilder.build("session-123", force_summarize: true)

  """
  @spec build(String.t(), keyword()) :: {:ok, context()} | {:error, term()}
  def build(session_id, opts \\ []) when is_binary(session_id) do
    start_time = System.monotonic_time(:millisecond)
    token_budget = Keyword.get(opts, :token_budget, @default_budget)
    query_hint = Keyword.get(opts, :query_hint)
    include_memories = Keyword.get(opts, :include_memories, true)
    include_conversation = Keyword.get(opts, :include_conversation, true)
    force_summarize = Keyword.get(opts, :force_summarize, false)

    conversation_opts = %{
      budget: token_budget.conversation,
      force_summarize: force_summarize
    }

    with {:ok, conversation} <- get_conversation(session_id, conversation_opts, include_conversation),
         {:ok, working} <- get_working_context(session_id),
         {:ok, long_term} <- get_relevant_memories(session_id, query_hint, include_memories, token_budget.long_term) do
      context = assemble_context(conversation, working, long_term)
      emit_telemetry(session_id, context.token_counts, start_time)
      {:ok, context}
    end
  end

  @doc """
  Formats the context for inclusion in an LLM system prompt.

  Produces markdown-formatted text with sections for:
  - Session Context (working context key-value pairs)
  - Remembered Information (long-term memories with type and confidence)

  ## Examples

      context = %{
        working_context: %{project_root: "/app", primary_language: "elixir"},
        long_term_memories: [%{memory_type: :fact, confidence: 0.9, content: "Uses Phoenix 1.7"}]
      }

      ContextBuilder.format_for_prompt(context)
      # => "## Session Context\\n- **Project root**: /app\\n..."

  """
  @spec format_for_prompt(context()) :: String.t()
  def format_for_prompt(%{working_context: working, long_term_memories: memories}) do
    parts = []

    parts =
      if map_size(working) > 0 do
        ["## Session Context\n" <> format_working_context(working) | parts]
      else
        parts
      end

    parts =
      if memories != [] do
        ["## Remembered Information\n" <> format_memories(memories) | parts]
      else
        parts
      end

    Enum.join(Enum.reverse(parts), "\n\n")
  end

  def format_for_prompt(_), do: ""

  @doc """
  Estimates the token count for a given string.

  Delegates to `TokenCounter.estimate_tokens/1` for consistent estimation
  across the codebase. Uses a character-based approximation (4 chars ≈ 1 token).

  ## Examples

      ContextBuilder.estimate_tokens("Hello, world!")
      # => 3

  """
  @spec estimate_tokens(String.t() | nil) :: non_neg_integer()
  defdelegate estimate_tokens(text), to: TokenCounter

  # =============================================================================
  # Private Functions - Data Retrieval
  # =============================================================================

  defp get_conversation(_session_id, _opts, false) do
    {:ok, []}
  end

  defp get_conversation(session_id, opts, true) do
    budget = opts.budget
    force_summarize = opts.force_summarize

    case State.get_messages(session_id) do
      {:ok, messages} ->
        current_tokens = TokenCounter.count_messages(messages)

        cond do
          # Under budget - no summarization needed
          current_tokens <= budget ->
            {:ok, messages}

          # Over budget - check cache or summarize
          true ->
            get_or_create_summary(session_id, messages, budget, force_summarize)
        end

      {:error, :not_found} ->
        {:error, :session_not_found}

      error ->
        error
    end
  end

  # Try to get cached summary or create new one
  defp get_or_create_summary(session_id, messages, budget, force_summarize) do
    message_count = length(messages)

    if force_summarize do
      # Force new summary
      create_and_cache_summary(session_id, messages, budget, message_count)
    else
      # Try cache first
      case get_cached_summary(session_id) do
        {:ok, cached} when cached.message_count == message_count ->
          # Cache is valid (same message count)
          Logger.debug("ContextBuilder: Using cached summary for session #{session_id}")
          {:ok, cached.summary}

        _ ->
          # Cache miss or stale - create new summary
          create_and_cache_summary(session_id, messages, budget, message_count)
      end
    end
  end

  defp create_and_cache_summary(session_id, messages, budget, message_count) do
    summary = Summarizer.summarize(messages, budget)
    cache_summary(session_id, summary, message_count)

    Logger.debug(
      "ContextBuilder: Summarized conversation from #{message_count} messages to #{length(summary)} for session #{session_id}"
    )

    emit_summarization_telemetry(session_id, message_count, length(summary))
    {:ok, summary}
  end

  defp get_cached_summary(session_id) do
    State.get_context(session_id, @summary_cache_key)
  end

  defp cache_summary(session_id, summary, message_count) do
    cache_data = %{
      summary: summary,
      message_count: message_count,
      created_at: DateTime.utc_now()
    }

    # Store as working context - will be automatically excluded from user-visible context
    State.update_context(session_id, @summary_cache_key, cache_data)
  end

  defp get_working_context(session_id) do
    case State.get_all_context(session_id) do
      {:ok, context} ->
        # Filter out internal cache keys (like conversation_summary)
        # that shouldn't be exposed in the working context
        filtered = Map.delete(context, @summary_cache_key)
        {:ok, filtered}

      {:error, :not_found} ->
        # Session doesn't exist - consistent with get_conversation
        {:error, :session_not_found}

      error ->
        error
    end
  end

  defp get_relevant_memories(_session_id, _query_hint, false, _budget) do
    {:ok, []}
  end

  defp get_relevant_memories(session_id, query_hint, true, budget) do
    # Determine query strategy based on whether we have a hint
    opts =
      if query_hint do
        # More memories when we have a query hint for relevance filtering
        [limit: @default_memory_limit]
      else
        # Fewer, higher confidence memories when no hint
        [min_confidence: @high_confidence_threshold, limit: @high_confidence_limit]
      end

    case Memory.query(session_id, opts) do
      {:ok, memories} ->
        truncated = truncate_memories_to_budget(memories, budget)
        {:ok, truncated}

      {:error, _reason} ->
        # Memory query errors shouldn't fail context building
        {:ok, []}
    end
  end

  # =============================================================================
  # Private Functions - Assembly
  # =============================================================================

  defp assemble_context(conversation, working, long_term) do
    conversation_tokens = estimate_conversation_tokens(conversation)
    working_tokens = estimate_working_tokens(working)
    long_term_tokens = estimate_memories_tokens(long_term)

    %{
      conversation: conversation,
      working_context: working,
      long_term_memories: long_term,
      system_context: nil,
      token_counts: %{
        conversation: conversation_tokens,
        working: working_tokens,
        long_term: long_term_tokens,
        total: conversation_tokens + working_tokens + long_term_tokens
      }
    }
  end

  # =============================================================================
  # Private Functions - Truncation
  # =============================================================================

  defp truncate_memories_to_budget(memories, budget) do
    # Keep highest confidence memories that fit within budget
    # Sort by confidence (descending) to preserve most reliable memories
    memories
    |> Enum.sort_by(&Map.get(&1, :confidence, 0), :desc)
    |> TokenCounter.select_within_budget(budget, &TokenCounter.count_memory/1)
  end

  # =============================================================================
  # Private Functions - Token Estimation
  # =============================================================================

  defp estimate_conversation_tokens(messages) do
    TokenCounter.count_messages(messages)
  end

  defp estimate_working_tokens(working) do
    TokenCounter.count_working_context(working)
  end

  defp estimate_memories_tokens(memories) do
    TokenCounter.count_memories(memories)
  end

  # =============================================================================
  # Private Functions - Formatting
  # =============================================================================

  defp format_working_context(working) do
    working
    |> Enum.map(fn {key, value} ->
      "- **#{format_key(key)}**: #{format_value(value)}"
    end)
    |> Enum.join("\n")
  end

  defp format_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp format_key(key), do: to_string(key)

  defp format_value(value) when is_binary(value), do: sanitize_content(value) |> truncate_content()
  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_number(value), do: to_string(value)
  defp format_value(value) when is_list(value), do: Enum.join(value, ", ") |> sanitize_content() |> truncate_content()
  defp format_value(value), do: inspect(value) |> truncate_content()

  defp format_memories(memories) do
    memories
    |> Enum.map(fn mem ->
      confidence_badge = confidence_badge(mem.confidence)
      type_badge = "[#{mem.memory_type}]"
      timestamp = format_timestamp(mem[:timestamp])
      # Sanitize memory content to prevent prompt injection
      content = mem.content |> sanitize_content() |> truncate_content()

      if timestamp do
        "- #{type_badge} #{confidence_badge} #{content} _(#{timestamp})_"
      else
        "- #{type_badge} #{confidence_badge} #{content}"
      end
    end)
    |> Enum.join("\n")
  end

  defp confidence_badge(c) when is_number(c) do
    case Types.confidence_to_level(c) do
      :high -> "(high confidence)"
      :medium -> "(medium confidence)"
      :low -> "(low confidence)"
    end
  end

  defp confidence_badge(_), do: "(low confidence)"

  defp format_timestamp(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d")
  end

  defp format_timestamp(_), do: nil

  # Truncates content to prevent overly long strings in formatted output
  defp truncate_content(content) when is_binary(content) do
    if String.length(content) > @max_content_display_length do
      String.slice(content, 0, @max_content_display_length) <> "..."
    else
      content
    end
  end

  defp truncate_content(content), do: to_string(content)

  # Sanitizes content to prevent markdown injection and potential prompt injection
  # Escapes markdown special characters and removes dangerous patterns
  # Note: Removed @spec from private function to match implementation (Concern #11)
  defp sanitize_content(content) when is_binary(content) do
    content
    # Escape markdown special characters that could affect formatting
    |> String.replace("**", "\\*\\*")
    |> String.replace("__", "\\_\\_")
    |> String.replace("```", "\\`\\`\\`")
    # Remove potential instruction injection patterns (common LLM jailbreak attempts)
    # Uses precompiled regexes for performance (Concern #5)
    |> String.replace(@regex_ignore_instructions, "[filtered]")
    |> String.replace(@regex_you_are_now, "[filtered]")
    |> String.replace(@regex_forget_previous, "[filtered]")
    |> String.replace(@regex_system_role, "system : ")
    |> String.replace(@regex_user_role, "user : ")
    |> String.replace(@regex_assistant_role, "assistant : ")
  end

  defp sanitize_content(content), do: to_string(content)

  # =============================================================================
  # Private Functions - Telemetry
  # =============================================================================

  defp emit_telemetry(session_id, token_counts, start_time) do
    duration_ms = System.monotonic_time(:millisecond) - start_time

    :telemetry.execute(
      [:jido_code, :memory, :context_build],
      %{duration_ms: duration_ms, tokens: token_counts.total},
      %{session_id: session_id}
    )
  end

  defp emit_summarization_telemetry(session_id, original_count, summarized_count) do
    # Concern #10: Standardized to [:jido_code, :memory, :context, :summarized]
    # to match the planning doc convention (using 4-element tuple like promotion events)
    :telemetry.execute(
      [:jido_code, :memory, :context, :summarized],
      %{original_messages: original_count, summarized_messages: summarized_count},
      %{session_id: session_id}
    )
  end
end
