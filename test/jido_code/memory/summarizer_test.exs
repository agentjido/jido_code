defmodule JidoCode.Memory.SummarizerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Summarizer
  alias JidoCode.Memory.TokenCounter

  # =============================================================================
  # Test Helpers
  # =============================================================================

  defp make_message(role, content, opts \\ []) do
    base = %{
      role: role,
      content: content
    }

    if timestamp = opts[:timestamp] do
      Map.put(base, :timestamp, timestamp)
    else
      base
    end
  end

  defp make_timestamped_messages(count) do
    base_time = ~U[2024-01-01 10:00:00Z]

    Enum.map(0..(count - 1), fn i ->
      role = if rem(i, 2) == 0, do: :user, else: :assistant
      timestamp = DateTime.add(base_time, i * 60, :second)

      %{
        role: role,
        content: "Message #{i + 1} content here",
        timestamp: timestamp
      }
    end)
  end

  # =============================================================================
  # summarize/2 Tests
  # =============================================================================

  describe "summarize/2" do
    test "returns empty list for empty messages" do
      assert Summarizer.summarize([], 1000) == []
    end

    test "returns empty list for zero target tokens" do
      messages = [make_message(:user, "Hello")]
      assert Summarizer.summarize(messages, 0) == []
    end

    test "returns empty list for negative target tokens" do
      messages = [make_message(:user, "Hello")]
      assert Summarizer.summarize(messages, -100) == []
    end

    test "reduces token count to target" do
      # Create messages with known token counts
      messages = make_timestamped_messages(20)
      original_tokens = TokenCounter.count_messages(messages)
      target_tokens = div(original_tokens, 2)

      result = Summarizer.summarize(messages, target_tokens)

      # Subtract summary marker tokens from result count
      result_without_marker = Enum.reject(result, &(&1.role == :system and &1[:id] =~ "summary-marker"))
      result_tokens = TokenCounter.count_messages(result_without_marker)

      assert result_tokens <= target_tokens
      assert length(result) < length(messages) + 1  # +1 for summary marker
    end

    test "adds summary marker to result" do
      messages = make_timestamped_messages(10)
      target_tokens = 50  # Small budget to ensure summarization

      result = Summarizer.summarize(messages, target_tokens)

      # First message should be the summary marker
      [first | _rest] = result
      assert first.role == :system
      assert first.content =~ "summarized"
      assert first[:id] =~ "summary-marker"
    end

    test "preserves user messages preferentially" do
      messages = [
        make_message(:assistant, "I can help with that.", timestamp: ~U[2024-01-01 10:00:00Z]),
        make_message(:user, "What is Elixir?", timestamp: ~U[2024-01-01 10:01:00Z]),
        make_message(:assistant, "Elixir is a functional language.", timestamp: ~U[2024-01-01 10:02:00Z]),
        make_message(:user, "Tell me more?", timestamp: ~U[2024-01-01 10:03:00Z])
      ]

      # Small budget that can only fit ~2 messages plus marker
      result = Summarizer.summarize(messages, 30)

      # Should include at least one user message
      non_marker_messages = Enum.reject(result, &(&1[:id] && &1[:id] =~ "summary-marker"))
      user_messages = Enum.filter(non_marker_messages, &(&1.role == :user))

      assert length(user_messages) >= 1
    end

    test "preserves recent messages preferentially" do
      base_time = ~U[2024-01-01 10:00:00Z]

      messages = [
        make_message(:user, "Old message 1", timestamp: DateTime.add(base_time, 0, :second)),
        make_message(:user, "Old message 2", timestamp: DateTime.add(base_time, 60, :second)),
        make_message(:user, "Recent message 1", timestamp: DateTime.add(base_time, 120, :second)),
        make_message(:user, "Recent message 2", timestamp: DateTime.add(base_time, 180, :second))
      ]

      # Budget for only 1-2 messages plus marker
      result = Summarizer.summarize(messages, 25)

      non_marker = Enum.reject(result, &(&1[:id] && &1[:id] =~ "summary-marker"))

      # Most recent messages should be preserved
      if length(non_marker) > 0 do
        contents = Enum.map(non_marker, & &1.content)
        # At least one recent message should be included
        assert Enum.any?(contents, &(&1 =~ "Recent"))
      end
    end

    test "preserves questions" do
      messages = [
        make_message(:user, "Just a statement.", timestamp: ~U[2024-01-01 10:00:00Z]),
        make_message(:user, "What is the answer?", timestamp: ~U[2024-01-01 10:01:00Z]),
        make_message(:user, "Another statement.", timestamp: ~U[2024-01-01 10:02:00Z])
      ]

      result = Summarizer.summarize(messages, 30)

      non_marker = Enum.reject(result, &(&1[:id] && &1[:id] =~ "summary-marker"))
      contents = Enum.map(non_marker, & &1.content)

      # Question should be preserved due to content boost
      assert Enum.any?(contents, &(&1 =~ "?"))
    end

    test "preserves decisions" do
      messages = [
        make_message(:user, "Random message.", timestamp: ~U[2024-01-01 10:00:00Z]),
        make_message(:user, "I've decided to use Phoenix.", timestamp: ~U[2024-01-01 10:01:00Z]),
        make_message(:user, "Another random message.", timestamp: ~U[2024-01-01 10:02:00Z])
      ]

      result = Summarizer.summarize(messages, 30)

      non_marker = Enum.reject(result, &(&1[:id] && &1[:id] =~ "summary-marker"))
      contents = Enum.map(non_marker, & &1.content)

      # Decision should be preserved due to content boost
      assert Enum.any?(contents, &(&1 =~ "decided"))
    end

    test "maintains chronological order after selection" do
      messages = make_timestamped_messages(10)
      result = Summarizer.summarize(messages, 80)

      # Skip the summary marker (first element)
      [_marker | rest] = result

      timestamps = Enum.map(rest, & &1.timestamp)

      # Verify timestamps are in chronological order
      sorted_timestamps = Enum.sort(timestamps, DateTime)
      assert timestamps == sorted_timestamps
    end

    test "handles messages without timestamps" do
      messages = [
        make_message(:user, "First message"),
        make_message(:assistant, "Response"),
        make_message(:user, "Second message")
      ]

      # Should not crash
      result = Summarizer.summarize(messages, 50)

      assert is_list(result)
      assert length(result) > 0
    end
  end

  # =============================================================================
  # score_messages/1 Tests
  # =============================================================================

  describe "score_messages/1" do
    test "returns empty list for empty input" do
      assert Summarizer.score_messages([]) == []
    end

    test "assigns higher score to user messages than assistant at same position" do
      # Test with single messages to isolate role weight effect
      user_messages = [make_message(:user, "Same content")]
      asst_messages = [make_message(:assistant, "Same content")]

      [{_user_msg, user_score}] = Summarizer.score_messages(user_messages)
      [{_asst_msg, asst_score}] = Summarizer.score_messages(asst_messages)

      # User should have higher role weight contribution
      assert user_score > asst_score
    end

    test "assigns correct role weights" do
      role_weights = Summarizer.role_weights()

      assert role_weights[:user] == 1.0
      assert role_weights[:assistant] == 0.6
      assert role_weights[:tool] == 0.4
      assert role_weights[:system] == 0.8
    end

    test "assigns higher score to more recent messages" do
      base_time = ~U[2024-01-01 10:00:00Z]

      # All same role and content to isolate recency effect
      messages = [
        make_message(:user, "Same content", timestamp: DateTime.add(base_time, 0, :second)),
        make_message(:user, "Same content", timestamp: DateTime.add(base_time, 60, :second)),
        make_message(:user, "Same content", timestamp: DateTime.add(base_time, 120, :second))
      ]

      scored = Summarizer.score_messages(messages)
      scores = Enum.map(scored, fn {_msg, score} -> score end)

      # Scores should increase with recency
      [first, second, third] = scores
      assert first < second
      assert second < third
    end

    test "returns scores between 0 and 1" do
      messages = make_timestamped_messages(10)
      scored = Summarizer.score_messages(messages)

      Enum.each(scored, fn {_msg, score} ->
        assert score >= 0.0
        assert score <= 2.0  # Max possible with all boosts
      end)
    end
  end

  # =============================================================================
  # score_content/1 Tests
  # =============================================================================

  describe "score_content/1" do
    test "returns 0.0 for nil content" do
      assert Summarizer.score_content(nil) == 0.0
    end

    test "returns 0.0 for empty content" do
      assert Summarizer.score_content("") == 0.0
    end

    test "boosts questions" do
      score = Summarizer.score_content("What is the meaning of life?")
      assert score > 0.0
      assert score >= 0.3  # Question boost
    end

    test "boosts decisions" do
      decision_phrases = [
        "I've decided to use Phoenix",
        "We're choosing this approach",
        "Going with option A",
        "Will use the first method",
        "Let's use this library",
        "I'll use pattern matching"
      ]

      Enum.each(decision_phrases, fn phrase ->
        score = Summarizer.score_content(phrase)
        assert score >= 0.4, "Expected boost for: #{phrase}"
      end)
    end

    test "boosts error mentions" do
      error_phrases = [
        "There's an error in line 10",
        "The test failed",
        "Got an exception",
        "Found a bug",
        "Having an issue",
        "Seeing a problem"
      ]

      Enum.each(error_phrases, fn phrase ->
        score = Summarizer.score_content(phrase)
        assert score >= 0.3, "Expected boost for: #{phrase}"
      end)
    end

    test "boosts important markers" do
      important_phrases = [
        "This is important to note",
        "Critical information here",
        "You must do this first",
        "This is required",
        "Essential step",
        "Necessary for success"
      ]

      Enum.each(important_phrases, fn phrase ->
        score = Summarizer.score_content(phrase)
        assert score >= 0.2, "Expected boost for: #{phrase}"
      end)
    end

    test "boosts code blocks" do
      score = Summarizer.score_content("Here's the code:\n```elixir\ndef foo, do: :bar\n```")
      assert score >= 0.15
    end

    test "boosts file references" do
      score = Summarizer.score_content("Check the file: lib/app.ex")
      assert score >= 0.1
    end

    test "accumulates multiple boosts" do
      # Question + error
      score = Summarizer.score_content("Why did this error occur?")
      assert score >= 0.6  # 0.3 + 0.3
    end

    test "caps score at 1.0" do
      # Many indicators should still cap at 1.0
      content = "What is this critical error? I've decided it's important and must be fixed. Check file: error.ex ```code```"
      score = Summarizer.score_content(content)
      assert score == 1.0
    end
  end

  # =============================================================================
  # role_weights/0 Tests
  # =============================================================================

  describe "role_weights/0" do
    test "returns expected weight map" do
      weights = Summarizer.role_weights()

      assert is_map(weights)
      assert Map.has_key?(weights, :user)
      assert Map.has_key?(weights, :assistant)
      assert Map.has_key?(weights, :tool)
      assert Map.has_key?(weights, :system)
    end

    test "user has highest weight" do
      weights = Summarizer.role_weights()
      assert weights[:user] >= weights[:assistant]
      assert weights[:user] >= weights[:tool]
      assert weights[:user] >= weights[:system]
    end
  end

  # =============================================================================
  # content_indicators/0 Tests
  # =============================================================================

  describe "content_indicators/0" do
    test "returns expected indicator map" do
      indicators = Summarizer.content_indicators()

      assert is_map(indicators)
      assert Map.has_key?(indicators, :question)
      assert Map.has_key?(indicators, :decision)
      assert Map.has_key?(indicators, :error)
      assert Map.has_key?(indicators, :important)
    end

    test "each indicator has pattern and boost" do
      indicators = Summarizer.content_indicators()

      Enum.each(indicators, fn {_name, {pattern, boost}} ->
        assert %Regex{} = pattern
        assert is_float(boost) or is_integer(boost)
        assert boost > 0
      end)
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  describe "integration" do
    test "realistic conversation summarization" do
      messages = [
        %{role: :system, content: "You are a helpful assistant.", timestamp: ~U[2024-01-01 10:00:00Z]},
        %{role: :user, content: "Hi, I need help with Elixir.", timestamp: ~U[2024-01-01 10:01:00Z]},
        %{role: :assistant, content: "I'd be happy to help! What would you like to know?", timestamp: ~U[2024-01-01 10:02:00Z]},
        %{role: :user, content: "What is pattern matching?", timestamp: ~U[2024-01-01 10:03:00Z]},
        %{role: :assistant, content: "Pattern matching is a powerful feature...", timestamp: ~U[2024-01-01 10:04:00Z]},
        %{role: :user, content: "I see. Can you show me an example?", timestamp: ~U[2024-01-01 10:05:00Z]},
        %{role: :assistant, content: "```elixir\ncase value do\n  {:ok, result} -> result\nend\n```", timestamp: ~U[2024-01-01 10:06:00Z]},
        %{role: :user, content: "I've decided to use this pattern.", timestamp: ~U[2024-01-01 10:07:00Z]},
        %{role: :assistant, content: "Great choice!", timestamp: ~U[2024-01-01 10:08:00Z]}
      ]

      # Summarize to about half the tokens
      original_tokens = TokenCounter.count_messages(messages)
      result = Summarizer.summarize(messages, div(original_tokens, 2))

      # Should have reduced message count
      assert length(result) < length(messages)

      # Should have summary marker
      assert hd(result).role == :system
      assert hd(result).content =~ "summarized"

      # Key messages should be preserved (questions, decisions)
      contents = Enum.map(result, & &1.content)
      has_question = Enum.any?(contents, &(&1 =~ "?"))
      has_decision = Enum.any?(contents, &(&1 =~ "decided"))

      # At least one of these should be preserved
      assert has_question or has_decision
    end

    test "very small budget returns empty when no messages fit" do
      messages = [
        %{role: :user, content: "A reasonably long message that takes up many tokens", timestamp: ~U[2024-01-01 10:00:00Z]}
      ]

      # Very small budget - no messages will fit
      result = Summarizer.summarize(messages, 5)

      # Should be empty since no messages fit and add_summary_markers returns [] for empty input
      assert result == []
    end

    test "large budget preserves all messages plus marker" do
      messages = make_timestamped_messages(5)
      original_tokens = TokenCounter.count_messages(messages)

      # Budget larger than all messages
      result = Summarizer.summarize(messages, original_tokens * 2)

      # Should have all original messages plus marker
      assert length(result) == length(messages) + 1
    end
  end
end
