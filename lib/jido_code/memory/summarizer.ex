defmodule JidoCode.Memory.Summarizer do
  @moduledoc """
  Extracts key information from conversation history for compression.

  Uses rule-based extractive summarization to identify and preserve
  the most important messages while reducing token count.

  ## Scoring Heuristics

  Messages are scored using multiple factors:

  - **Role weights**: User messages weighted higher than assistant
  - **Content indicators**: Questions and decisions score higher
  - **Recency**: More recent messages preferred over old
  - **Tool results**: Summarized to outcomes only

  ## Usage

      # Summarize a conversation to fit within a token budget
      summarized = Summarizer.summarize(messages, target_tokens)

      # Score messages without selecting
      scored = Summarizer.score_messages(messages)

  ## Algorithm

  1. Score each message based on role, content indicators, and recency
  2. Sort by score descending
  3. Select top messages that fit within token budget
  4. Restore chronological order
  5. Add summary marker to indicate compression occurred
  """

  alias JidoCode.Memory.TokenCounter

  # =============================================================================
  # Types
  # =============================================================================

  @typedoc """
  A conversation message with role and content.
  """
  @type message :: %{
          required(:role) => :user | :assistant | :tool | :system | atom(),
          required(:content) => String.t() | nil,
          optional(:timestamp) => DateTime.t(),
          optional(:id) => String.t()
        }

  @typedoc """
  A message with its computed importance score.
  """
  @type scored_message :: {message(), float()}

  # =============================================================================
  # Constants
  # =============================================================================

  # Role weights - higher = more important to preserve
  @role_weights %{
    user: 1.0,
    assistant: 0.6,
    tool: 0.4,
    system: 0.8
  }

  # Content indicators with their regex patterns and score boosts
  @content_indicators %{
    question: {~r/\?/, 0.3},
    decision: {~r/(?:decided|choosing|going with|will use|let's use|I'll use)/i, 0.4},
    error: {~r/(?:error|failed|exception|bug|issue|problem)/i, 0.3},
    important: {~r/(?:important|critical|must|required|essential|necessary)/i, 0.2},
    code_block: {~r/```/, 0.15},
    file_reference: {~r/(?:file|path|directory)[:\s]+\S+/i, 0.1}
  }

  # Weight distribution for final score calculation
  @role_weight_factor 0.3
  @recency_weight_factor 0.4
  @content_weight_factor 0.3

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Summarizes a list of messages to fit within a target token budget.

  Scores each message based on importance heuristics, selects the most
  important messages that fit within the budget, and adds a summary marker.

  ## Parameters

  - `messages` - List of conversation messages to summarize
  - `target_tokens` - Maximum token count for the result

  ## Returns

  List of selected messages with a summary marker prepended.

  ## Examples

      messages = [
        %{role: :user, content: "Hello", timestamp: ~U[2024-01-01 10:00:00Z]},
        %{role: :assistant, content: "Hi there!", timestamp: ~U[2024-01-01 10:01:00Z]},
        %{role: :user, content: "What is Elixir?", timestamp: ~U[2024-01-01 10:02:00Z]},
        %{role: :assistant, content: "Elixir is...", timestamp: ~U[2024-01-01 10:03:00Z]}
      ]

      Summarizer.summarize(messages, 100)
      # Returns the most important messages within 100 tokens

  """
  @spec summarize([message()], non_neg_integer()) :: [message()]
  def summarize([], _target_tokens), do: []

  def summarize(messages, target_tokens) when is_list(messages) and target_tokens > 0 do
    messages
    |> score_messages()
    |> select_top_messages(target_tokens)
    |> add_summary_markers()
  end

  def summarize(_messages, _target_tokens), do: []

  @doc """
  Scores all messages based on importance heuristics.

  Returns a list of tuples containing the original message and its score.
  Higher scores indicate more important messages.

  ## Parameters

  - `messages` - List of conversation messages

  ## Returns

  List of `{message, score}` tuples.

  ## Scoring Algorithm

  The final score combines three factors:
  - Role score (30%): Based on message role (user > system > assistant > tool)
  - Recency score (40%): More recent messages score higher
  - Content score (30%): Boosted for questions, decisions, errors, etc.

  ## Examples

      scored = Summarizer.score_messages(messages)
      # Returns [{%{role: :user, ...}, 0.85}, ...]

  """
  @spec score_messages([message()]) :: [scored_message()]
  def score_messages([]), do: []

  def score_messages(messages) when is_list(messages) do
    total = length(messages)

    messages
    |> Enum.with_index()
    |> Enum.map(fn {msg, idx} ->
      role_score = get_role_score(msg.role)
      # More recent messages (higher index) get higher recency scores
      recency_score = (idx + 1) / total
      content_score = score_content(msg[:content])

      score =
        role_score * @role_weight_factor +
          recency_score * @recency_weight_factor +
          content_score * @content_weight_factor

      {msg, score}
    end)
  end

  @doc """
  Scores message content based on indicator patterns.

  Checks for presence of questions, decisions, errors, and other
  important content markers.

  ## Parameters

  - `content` - The message content string

  ## Returns

  A float between 0.0 and 1.0 indicating content importance.

  ## Examples

      Summarizer.score_content("What is Elixir?")
      # Returns 0.3 (question boost)

      Summarizer.score_content("I've decided to use Phoenix")
      # Returns 0.4 (decision boost)

  """
  @spec score_content(String.t() | nil) :: float()
  def score_content(nil), do: 0.0
  def score_content(""), do: 0.0

  def score_content(content) when is_binary(content) do
    @content_indicators
    |> Enum.reduce(0.0, fn {_name, {pattern, boost}}, acc ->
      if Regex.match?(pattern, content), do: acc + boost, else: acc
    end)
    |> min(1.0)
  end

  @doc """
  Returns the role weights used for scoring.

  Useful for testing and debugging.
  """
  @spec role_weights() :: map()
  def role_weights, do: @role_weights

  @doc """
  Returns the content indicator patterns used for scoring.

  Useful for testing and debugging.
  """
  @spec content_indicators() :: map()
  def content_indicators, do: @content_indicators

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec get_role_score(atom()) :: float()
  defp get_role_score(role) when is_atom(role) do
    Map.get(@role_weights, role, 0.5)
  end

  defp get_role_score(_), do: 0.5

  @spec select_top_messages([scored_message()], non_neg_integer()) :: [message()]
  defp select_top_messages(scored_messages, target_tokens) do
    # Sort by score descending to prioritize highest-scoring messages
    scored_messages
    |> Enum.sort_by(fn {_msg, score} -> score end, :desc)
    |> Enum.reduce_while({[], 0}, fn {msg, _score}, {acc, tokens} ->
      msg_tokens = TokenCounter.count_message(msg)

      if tokens + msg_tokens <= target_tokens do
        {:cont, {[msg | acc], tokens + msg_tokens}}
      else
        {:halt, {acc, tokens}}
      end
    end)
    |> elem(0)
    |> sort_chronologically()
  end

  @spec sort_chronologically([message()]) :: [message()]
  defp sort_chronologically(messages) do
    # Sort by timestamp if available, otherwise maintain selection order
    Enum.sort_by(messages, fn msg ->
      case msg[:timestamp] do
        %DateTime{} = dt -> DateTime.to_unix(dt, :microsecond)
        _ -> 0
      end
    end)
  end

  @spec add_summary_markers([message()]) :: [message()]
  defp add_summary_markers([]), do: []

  defp add_summary_markers(messages) do
    summary_note = %{
      id: "summary-marker-#{:erlang.unique_integer([:positive])}",
      role: :system,
      content: "[Earlier conversation summarized to key points]",
      timestamp: DateTime.utc_now()
    }

    [summary_note | messages]
  end
end
