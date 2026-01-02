defmodule JidoCode.Memory.TokenCounterTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.TokenCounter

  # =============================================================================
  # estimate_tokens/1 Tests
  # =============================================================================

  describe "estimate_tokens/1" do
    test "produces reasonable estimates for English text" do
      # 4 chars per token approximation
      # "Hello, world!" = 13 chars = 3 tokens
      assert TokenCounter.estimate_tokens("Hello, world!") == 3
    end

    test "handles empty string" do
      assert TokenCounter.estimate_tokens("") == 0
    end

    test "handles nil" do
      assert TokenCounter.estimate_tokens(nil) == 0
    end

    test "handles single character" do
      # Less than 4 chars = 0 tokens (integer division)
      assert TokenCounter.estimate_tokens("a") == 0
      assert TokenCounter.estimate_tokens("abc") == 0
    end

    test "handles exactly 4 characters" do
      assert TokenCounter.estimate_tokens("abcd") == 1
    end

    test "handles longer text" do
      # 40 chars = 10 tokens
      text = String.duplicate("a", 40)
      assert TokenCounter.estimate_tokens(text) == 10
    end

    test "handles unicode characters" do
      # Each emoji counts as 1 character in String.length
      # 4 emojis = 4 chars = 1 token
      assert TokenCounter.estimate_tokens("🎉🎉🎉🎉") == 1
    end

    test "handles multiline text" do
      text = "Line 1\nLine 2\nLine 3"
      # 20 chars = 5 tokens
      assert TokenCounter.estimate_tokens(text) == 5
    end

    test "handles code snippets" do
      code = """
      def hello do
        IO.puts("Hello")
      end
      """
      # Code has predictable character counts
      tokens = TokenCounter.estimate_tokens(code)
      assert tokens > 0
      assert tokens == div(String.length(code), 4)
    end
  end

  # =============================================================================
  # chars_per_token/0 Tests
  # =============================================================================

  describe "chars_per_token/0" do
    test "returns the expected constant" do
      assert TokenCounter.chars_per_token() == 4
    end
  end

  # =============================================================================
  # count_message/1 Tests
  # =============================================================================

  describe "count_message/1" do
    test "includes overhead for message structure" do
      message = %{role: :user, content: "Hi"}
      # "Hi" = 0 tokens + 4 overhead = 4
      assert TokenCounter.count_message(message) == 4
    end

    test "counts content tokens plus overhead" do
      message = %{role: :user, content: "Hello, world!"}
      # 13 chars = 3 tokens + 4 overhead = 7
      assert TokenCounter.count_message(message) == 7
    end

    test "handles nil content" do
      message = %{role: :assistant, content: nil}
      # nil = 0 tokens + 4 overhead = 4
      assert TokenCounter.count_message(message) == 4
    end

    test "handles empty content" do
      message = %{role: :system, content: ""}
      assert TokenCounter.count_message(message) == 4
    end

    test "handles long messages" do
      content = String.duplicate("word ", 100)
      message = %{role: :user, content: content}
      expected = div(String.length(content), 4) + 4
      assert TokenCounter.count_message(message) == expected
    end

    test "handles message without content key" do
      # Should return just overhead
      assert TokenCounter.count_message(%{role: :user}) == 4
    end

    test "handles invalid input" do
      assert TokenCounter.count_message(nil) == 4
      assert TokenCounter.count_message("string") == 4
    end
  end

  # =============================================================================
  # message_overhead/0 Tests
  # =============================================================================

  describe "message_overhead/0" do
    test "returns the expected constant" do
      assert TokenCounter.message_overhead() == 4
    end
  end

  # =============================================================================
  # count_messages/1 Tests
  # =============================================================================

  describe "count_messages/1" do
    test "sums token counts correctly" do
      messages = [
        %{role: :user, content: "Hi"},       # 0 + 4 = 4
        %{role: :assistant, content: "Hello!"}  # 1 + 4 = 5
      ]
      assert TokenCounter.count_messages(messages) == 9
    end

    test "handles empty list" do
      assert TokenCounter.count_messages([]) == 0
    end

    test "handles single message" do
      messages = [%{role: :user, content: "Hello, world!"}]
      assert TokenCounter.count_messages(messages) == 7
    end

    test "handles many messages" do
      messages = for i <- 1..10 do
        %{role: :user, content: "Message #{i}"}
      end
      # Each "Message N" is ~9 chars = 2 tokens + 4 overhead = 6
      # 10 messages * 6 = 60
      total = TokenCounter.count_messages(messages)
      assert total > 0
      assert total == Enum.sum(Enum.map(messages, &TokenCounter.count_message/1))
    end

    test "handles nil input" do
      assert TokenCounter.count_messages(nil) == 0
    end

    test "handles non-list input" do
      assert TokenCounter.count_messages("not a list") == 0
    end
  end

  # =============================================================================
  # count_memory/1 Tests
  # =============================================================================

  describe "count_memory/1" do
    test "includes metadata overhead" do
      memory = %{content: "Uses Phoenix", memory_type: :fact, confidence: 0.9}
      # "Uses Phoenix" = 12 chars = 3 tokens + 10 overhead = 13
      assert TokenCounter.count_memory(memory) == 13
    end

    test "handles nil content" do
      memory = %{content: nil, memory_type: :fact}
      assert TokenCounter.count_memory(memory) == 10
    end

    test "handles empty content" do
      memory = %{content: "", memory_type: :fact}
      assert TokenCounter.count_memory(memory) == 10
    end

    test "handles long memory content" do
      content = "This is a very detailed memory about the project structure and architecture"
      memory = %{content: content, memory_type: :discovery}
      expected = div(String.length(content), 4) + 10
      assert TokenCounter.count_memory(memory) == expected
    end

    test "handles memory without content key" do
      assert TokenCounter.count_memory(%{memory_type: :fact}) == 10
    end

    test "handles invalid input" do
      assert TokenCounter.count_memory(nil) == 10
      assert TokenCounter.count_memory("string") == 10
    end
  end

  # =============================================================================
  # memory_overhead/0 Tests
  # =============================================================================

  describe "memory_overhead/0" do
    test "returns the expected constant" do
      assert TokenCounter.memory_overhead() == 10
    end
  end

  # =============================================================================
  # count_memories/1 Tests
  # =============================================================================

  describe "count_memories/1" do
    test "sums token counts correctly" do
      memories = [
        %{content: "Uses Phoenix", memory_type: :fact},      # 3 + 10 = 13
        %{content: "Prefers tabs", memory_type: :preference} # 3 + 10 = 13
      ]
      assert TokenCounter.count_memories(memories) == 26
    end

    test "handles empty list" do
      assert TokenCounter.count_memories([]) == 0
    end

    test "handles single memory" do
      memories = [%{content: "Uses Phoenix", memory_type: :fact}]
      assert TokenCounter.count_memories(memories) == 13
    end

    test "handles many memories" do
      memories = for i <- 1..5 do
        %{content: "Memory item #{i}", memory_type: :fact}
      end
      total = TokenCounter.count_memories(memories)
      assert total > 0
      assert total == Enum.sum(Enum.map(memories, &TokenCounter.count_memory/1))
    end

    test "handles nil input" do
      assert TokenCounter.count_memories(nil) == 0
    end

    test "handles non-list input" do
      assert TokenCounter.count_memories("not a list") == 0
    end
  end

  # =============================================================================
  # count_working_context/1 Tests
  # =============================================================================

  describe "count_working_context/1" do
    test "counts key-value pairs with overhead" do
      context = %{framework: "Phoenix"}
      # "framework" = 9 chars = 2 tokens
      # "Phoenix" = 7 chars = 1 token
      # + 2 overhead = 5
      assert TokenCounter.count_working_context(context) == 5
    end

    test "handles multiple pairs" do
      context = %{framework: "Phoenix", language: "Elixir"}
      # framework: 2, Phoenix: 1, +2 = 5
      # language: 2, Elixir: 1, +2 = 5
      # Total: 10
      total = TokenCounter.count_working_context(context)
      assert total > 0
    end

    test "handles empty map" do
      assert TokenCounter.count_working_context(%{}) == 0
    end

    test "handles atom values" do
      context = %{status: :active}
      total = TokenCounter.count_working_context(context)
      assert total > 0
    end

    test "handles nil input" do
      assert TokenCounter.count_working_context(nil) == 0
    end

    test "handles non-map input" do
      assert TokenCounter.count_working_context("not a map") == 0
    end
  end

  # =============================================================================
  # Edge Cases and Integration Tests
  # =============================================================================

  describe "edge cases" do
    test "very large text doesn't overflow" do
      # 1 million characters
      large_text = String.duplicate("a", 1_000_000)
      result = TokenCounter.estimate_tokens(large_text)
      assert result == 250_000
    end

    test "consistent results across multiple calls" do
      text = "This is a test message"
      first = TokenCounter.estimate_tokens(text)
      second = TokenCounter.estimate_tokens(text)
      assert first == second
    end

    test "overhead constants are positive" do
      assert TokenCounter.message_overhead() > 0
      assert TokenCounter.memory_overhead() > 0
      assert TokenCounter.chars_per_token() > 0
    end
  end
end
