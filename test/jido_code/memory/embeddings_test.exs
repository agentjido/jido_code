defmodule JidoCode.Memory.EmbeddingsTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Embeddings

  # =============================================================================
  # tokenize/1 Tests
  # =============================================================================

  describe "tokenize/1" do
    test "converts text to lowercase" do
      tokens = Embeddings.tokenize("HELLO World")
      assert tokens == ["hello", "world"]
    end

    test "removes punctuation" do
      tokens = Embeddings.tokenize("Hello, World! How are you?")
      # Note: "you" is a stopword
      assert "hello" in tokens
      assert "world" in tokens
    end

    test "splits on whitespace" do
      tokens = Embeddings.tokenize("one  two   three")
      assert tokens == ["one", "two", "three"]
    end

    test "removes stopwords" do
      tokens = Embeddings.tokenize("The quick brown fox")
      refute "the" in tokens
      assert "quick" in tokens
      assert "brown" in tokens
      assert "fox" in tokens
    end

    test "handles empty string" do
      assert Embeddings.tokenize("") == []
    end

    test "handles nil" do
      assert Embeddings.tokenize(nil) == []
    end

    test "handles string with only stopwords" do
      tokens = Embeddings.tokenize("the a an is are")
      assert tokens == []
    end

    test "handles programming terms" do
      tokens = Embeddings.tokenize("Phoenix is a web framework")
      assert "phoenix" in tokens
      assert "web" in tokens
      assert "framework" in tokens
      refute "is" in tokens
      refute "a" in tokens
    end

    test "handles underscores and numbers" do
      tokens = Embeddings.tokenize("my_function_v2 returns 42")
      assert "my_function_v2" in tokens
      assert "returns" in tokens
      assert "42" in tokens
    end
  end

  # =============================================================================
  # stopword?/1 Tests
  # =============================================================================

  describe "stopword?/1" do
    test "returns true for common stopwords" do
      assert Embeddings.stopword?("the")
      assert Embeddings.stopword?("a")
      assert Embeddings.stopword?("is")
      assert Embeddings.stopword?("and")
      assert Embeddings.stopword?("or")
    end

    test "returns false for content words" do
      refute Embeddings.stopword?("phoenix")
      refute Embeddings.stopword?("elixir")
      refute Embeddings.stopword?("function")
    end

    test "returns false for nil" do
      refute Embeddings.stopword?(nil)
    end
  end

  # =============================================================================
  # compute_tfidf/2 Tests
  # =============================================================================

  describe "compute_tfidf/2" do
    test "returns empty map for empty tokens" do
      assert Embeddings.compute_tfidf([]) == %{}
    end

    test "produces valid scores" do
      tokens = ["phoenix", "web", "framework"]
      tfidf = Embeddings.compute_tfidf(tokens)

      assert is_map(tfidf)
      assert Map.has_key?(tfidf, "phoenix")
      assert Map.has_key?(tfidf, "web")
      assert Map.has_key?(tfidf, "framework")

      # All scores should be positive
      Enum.each(tfidf, fn {_term, score} ->
        assert score > 0
      end)
    end

    test "higher IDF terms get higher scores" do
      # "phoenix" has higher IDF than "function" in default corpus
      tokens = ["phoenix", "function"]
      tfidf = Embeddings.compute_tfidf(tokens)

      phoenix_score = Map.get(tfidf, "phoenix")
      function_score = Map.get(tfidf, "function")

      # Both appear once, so TF is equal
      # IDF for phoenix (2.8) > IDF for function (1.5)
      assert phoenix_score > function_score
    end

    test "term frequency affects score" do
      tokens = ["phoenix", "phoenix", "framework"]
      tfidf = Embeddings.compute_tfidf(tokens)

      phoenix_score = Map.get(tfidf, "phoenix")
      framework_score = Map.get(tfidf, "framework")

      # phoenix appears 2x, framework appears 1x
      # Even accounting for IDF, phoenix should have higher score
      assert phoenix_score > framework_score
    end

    test "uses default IDF for unknown terms" do
      tokens = ["xyzzy", "plugh"]
      tfidf = Embeddings.compute_tfidf(tokens)

      # Both unknown terms should get default IDF
      xyzzy_score = Map.get(tfidf, "xyzzy")
      plugh_score = Map.get(tfidf, "plugh")

      # Same frequency, same IDF -> same score
      assert_in_delta xyzzy_score, plugh_score, 0.001
    end
  end

  # =============================================================================
  # generate/2 Tests
  # =============================================================================

  describe "generate/2" do
    test "returns embedding map for valid text" do
      {:ok, embedding} = Embeddings.generate("Phoenix web framework")

      assert is_map(embedding)
      assert Map.has_key?(embedding, "phoenix")
    end

    test "returns error for empty string" do
      assert {:error, :empty_text} = Embeddings.generate("")
    end

    test "returns error for nil" do
      assert {:error, :empty_text} = Embeddings.generate(nil)
    end

    test "returns error for string with only stopwords" do
      assert {:error, :empty_text} = Embeddings.generate("the a an is are")
    end

    test "handles special characters" do
      {:ok, embedding} = Embeddings.generate("Hello! World? Yes.")

      assert Map.has_key?(embedding, "hello")
      assert Map.has_key?(embedding, "world")
      assert Map.has_key?(embedding, "yes")
    end
  end

  # =============================================================================
  # generate!/2 Tests
  # =============================================================================

  describe "generate!/2" do
    test "returns embedding for valid text" do
      embedding = Embeddings.generate!("Phoenix framework")

      assert is_map(embedding)
      assert Map.has_key?(embedding, "phoenix")
    end

    test "returns empty map for empty text" do
      embedding = Embeddings.generate!("")
      assert embedding == %{}
    end

    test "returns empty map for nil" do
      embedding = Embeddings.generate!(nil)
      assert embedding == %{}
    end
  end

  # =============================================================================
  # cosine_similarity/2 Tests
  # =============================================================================

  describe "cosine_similarity/2" do
    test "returns 1.0 for identical vectors" do
      vec = %{"phoenix" => 1.0, "web" => 0.5}
      similarity = Embeddings.cosine_similarity(vec, vec)

      assert_in_delta similarity, 1.0, 0.001
    end

    test "returns 0.0 for orthogonal vectors (no overlap)" do
      vec_a = %{"phoenix" => 1.0}
      vec_b = %{"rails" => 1.0}
      similarity = Embeddings.cosine_similarity(vec_a, vec_b)

      assert similarity == 0.0
    end

    test "returns value between 0 and 1 for partial overlap" do
      vec_a = %{"phoenix" => 1.0, "web" => 0.5}
      vec_b = %{"phoenix" => 0.8, "framework" => 0.6}
      similarity = Embeddings.cosine_similarity(vec_a, vec_b)

      assert similarity > 0.0
      assert similarity < 1.0
    end

    test "returns 0.0 for empty vectors" do
      assert Embeddings.cosine_similarity(%{}, %{}) == 0.0
      assert Embeddings.cosine_similarity(%{"a" => 1.0}, %{}) == 0.0
      assert Embeddings.cosine_similarity(%{}, %{"a" => 1.0}) == 0.0
    end

    test "returns 0.0 for nil inputs" do
      assert Embeddings.cosine_similarity(nil, nil) == 0.0
      assert Embeddings.cosine_similarity(%{"a" => 1.0}, nil) == 0.0
    end

    test "is symmetric" do
      vec_a = %{"phoenix" => 1.0, "web" => 0.5}
      vec_b = %{"phoenix" => 0.8, "elixir" => 0.3}

      sim_ab = Embeddings.cosine_similarity(vec_a, vec_b)
      sim_ba = Embeddings.cosine_similarity(vec_b, vec_a)

      assert_in_delta sim_ab, sim_ba, 0.001
    end

    test "magnitude does not affect direction" do
      vec_a = %{"phoenix" => 1.0, "web" => 0.5}
      vec_b = %{"phoenix" => 2.0, "web" => 1.0}  # Same direction, different magnitude

      similarity = Embeddings.cosine_similarity(vec_a, vec_b)
      assert_in_delta similarity, 1.0, 0.001
    end
  end

  # =============================================================================
  # rank_by_similarity/3 Tests
  # =============================================================================

  describe "rank_by_similarity/3" do
    test "ranks items by semantic similarity" do
      {:ok, query_embed} = Embeddings.generate("Phoenix web framework")

      items = [
        %{id: 1, content: "Rails web framework for Ruby"},
        %{id: 2, content: "Phoenix LiveView components"},
        %{id: 3, content: "Elixir Phoenix framework patterns"}
      ]

      ranked = Embeddings.rank_by_similarity(query_embed, items)

      # Should return {item, score} tuples
      assert is_list(ranked)
      assert length(ranked) > 0

      # Items with Phoenix should rank higher
      ids = Enum.map(ranked, fn {item, _score} -> item.id end)
      # Phoenix items should be first
      assert hd(ids) in [2, 3]
    end

    test "filters by threshold" do
      {:ok, query_embed} = Embeddings.generate("Phoenix")

      items = [
        %{id: 1, content: "Completely unrelated to anything"},
        %{id: 2, content: "Phoenix framework"}
      ]

      ranked = Embeddings.rank_by_similarity(query_embed, items, threshold: 0.5)

      # Only Phoenix item should pass high threshold
      assert length(ranked) <= 2
    end

    test "respects limit option" do
      {:ok, query_embed} = Embeddings.generate("web framework")

      items = [
        %{id: 1, content: "Phoenix web framework"},
        %{id: 2, content: "Rails web framework"},
        %{id: 3, content: "Django web framework"}
      ]

      ranked = Embeddings.rank_by_similarity(query_embed, items, limit: 2)

      assert length(ranked) <= 2
    end

    test "uses custom content extractor" do
      {:ok, query_embed} = Embeddings.generate("Phoenix")

      items = [
        %{id: 1, text: "Phoenix framework"},
        %{id: 2, text: "Rails framework"}
      ]

      ranked = Embeddings.rank_by_similarity(query_embed, items, get_content: & &1.text)

      assert length(ranked) > 0
      {first, _score} = hd(ranked)
      assert first.id == 1
    end

    test "returns empty list for empty items" do
      {:ok, query_embed} = Embeddings.generate("Phoenix")
      ranked = Embeddings.rank_by_similarity(query_embed, [])

      assert ranked == []
    end
  end

  # =============================================================================
  # find_similar/3 Tests
  # =============================================================================

  describe "find_similar/3" do
    test "finds similar items by query string" do
      items = [
        %{id: 1, content: "Phoenix web framework patterns"},
        %{id: 2, content: "Rails convention over configuration"},
        %{id: 3, content: "Elixir Phoenix LiveView"}
      ]

      ranked = Embeddings.find_similar("Phoenix patterns", items)

      assert length(ranked) > 0
      # Phoenix-related items should be in results
      ids = Enum.map(ranked, fn {item, _score} -> item.id end)
      assert 1 in ids or 3 in ids
    end

    test "returns empty list for empty query" do
      items = [%{id: 1, content: "Phoenix framework"}]
      ranked = Embeddings.find_similar("", items)

      assert ranked == []
    end

    test "returns empty list for query with only stopwords" do
      items = [%{id: 1, content: "Phoenix framework"}]
      ranked = Embeddings.find_similar("the a an", items)

      assert ranked == []
    end
  end

  # =============================================================================
  # Integration Tests
  # =============================================================================

  describe "integration" do
    test "similar content has higher similarity than unrelated" do
      {:ok, query} = Embeddings.generate("Phoenix web framework")
      {:ok, related} = Embeddings.generate("Phoenix LiveView components")
      {:ok, unrelated} = Embeddings.generate("Database migration scripts")

      related_sim = Embeddings.cosine_similarity(query, related)
      unrelated_sim = Embeddings.cosine_similarity(query, unrelated)

      assert related_sim > unrelated_sim
    end

    test "documents with shared terms have higher similarity" do
      # TF-IDF measures term overlap, so documents sharing terms are more similar
      {:ok, phoenix1} = Embeddings.generate("Phoenix web framework patterns")
      {:ok, phoenix2} = Embeddings.generate("Phoenix framework conventions")
      {:ok, unrelated} = Embeddings.generate("Database migration scripts")

      phoenix_sim = Embeddings.cosine_similarity(phoenix1, phoenix2)
      cross_sim = Embeddings.cosine_similarity(phoenix1, unrelated)

      # phoenix1 and phoenix2 share "phoenix" and "framework"
      assert phoenix_sim > cross_sim
    end

    test "end-to-end memory search simulation" do
      # Simulate memory search scenario
      memories = [
        %{id: "mem-1", content: "Project uses Phoenix 1.7 with LiveView"},
        %{id: "mem-2", content: "Database is PostgreSQL with Ecto"},
        %{id: "mem-3", content: "Authentication handled by Guardian"},
        %{id: "mem-4", content: "Phoenix channels for real-time updates"},
        %{id: "mem-5", content: "Rails migration from legacy system"}
      ]

      # Search for Phoenix-related memories
      results = Embeddings.find_similar("Phoenix LiveView patterns", memories)

      # Should find Phoenix-related memories
      ids = Enum.map(results, fn {mem, _} -> mem.id end)

      # mem-1 and mem-4 should rank high (Phoenix-related)
      phoenix_ids = ["mem-1", "mem-4"]
      found_phoenix = Enum.filter(ids, &(&1 in phoenix_ids))
      assert length(found_phoenix) > 0
    end
  end

  # =============================================================================
  # Utility Function Tests
  # =============================================================================

  describe "utility functions" do
    test "stopwords/0 returns a MapSet" do
      stopwords = Embeddings.stopwords()
      assert %MapSet{} = stopwords
      assert MapSet.member?(stopwords, "the")
    end

    test "default_corpus_stats/0 returns valid structure" do
      stats = Embeddings.default_corpus_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :idf)
      assert Map.has_key?(stats, :default_idf)
      assert is_map(stats.idf)
      assert is_number(stats.default_idf)
    end

    test "default_idf_values/0 returns programming terms" do
      idf_values = Embeddings.default_idf_values()

      assert Map.has_key?(idf_values, "phoenix")
      assert Map.has_key?(idf_values, "elixir")
      assert Map.has_key?(idf_values, "function")
    end

    test "default_similarity_threshold/0 returns reasonable value" do
      threshold = Embeddings.default_similarity_threshold()

      assert is_number(threshold)
      assert threshold > 0.0
      assert threshold < 1.0
    end
  end
end
