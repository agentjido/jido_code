defmodule JidoCode.Memory.Promotion.ImportanceScorerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Promotion.ImportanceScorer

  # Reset config after each test to avoid test pollution
  setup do
    on_exit(fn -> ImportanceScorer.reset_config() end)
    :ok
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp create_item(overrides \\ %{}) do
    Map.merge(
      %{
        last_accessed: DateTime.utc_now(),
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      },
      overrides
    )
  end

  defp minutes_ago(minutes) do
    DateTime.add(DateTime.utc_now(), -minutes * 60, :second)
  end

  # =============================================================================
  # score/1 Tests
  # =============================================================================

  describe "score/1" do
    test "returns value between 0 and 1" do
      item = create_item()
      score = ImportanceScorer.score(item)

      assert score >= 0.0
      assert score <= 1.0
    end

    test "returns maximum (1.0) for ideal item" do
      # Ideal item: accessed now, frequently accessed, high confidence, high salience type
      item = create_item(%{
        last_accessed: DateTime.utc_now(),
        access_count: 10,
        confidence: 1.0,
        suggested_type: :decision
      })

      score = ImportanceScorer.score(item)
      # With default weights (0.2 + 0.3 + 0.25 + 0.25 = 1.0), all components at 1.0 gives 1.0
      assert_in_delta score, 1.0, 0.01
    end

    test "returns low value for old, unaccessed, low confidence item" do
      item = create_item(%{
        last_accessed: minutes_ago(120),
        access_count: 0,
        confidence: 0.1,
        suggested_type: nil
      })

      score = ImportanceScorer.score(item)
      # All components should be low, resulting in a low overall score
      assert score < 0.3
    end

    test "correctly weighs all factors" do
      item = create_item(%{
        last_accessed: DateTime.utc_now(),
        access_count: 5,
        confidence: 0.8,
        suggested_type: :fact
      })

      breakdown = ImportanceScorer.score_with_breakdown(item)

      # Verify the total is the weighted sum
      config = ImportanceScorer.get_config()

      expected_total =
        config.recency_weight * breakdown.recency +
          config.frequency_weight * breakdown.frequency +
          config.confidence_weight * breakdown.confidence +
          config.salience_weight * breakdown.salience

      assert_in_delta breakdown.total, expected_total, 0.001
    end
  end

  # =============================================================================
  # recency_score/1 Tests
  # =============================================================================

  describe "recency_score/1" do
    test "returns 1.0 for item accessed now" do
      score = ImportanceScorer.recency_score(DateTime.utc_now())
      assert_in_delta score, 1.0, 0.01
    end

    test "returns ~0.5 for item accessed 30 minutes ago" do
      last_accessed = minutes_ago(30)
      score = ImportanceScorer.recency_score(last_accessed)
      # 1 / (1 + 30/30) = 1/2 = 0.5
      assert_in_delta score, 0.5, 0.01
    end

    test "returns ~0.33 for item accessed 60 minutes ago" do
      last_accessed = minutes_ago(60)
      score = ImportanceScorer.recency_score(last_accessed)
      # 1 / (1 + 60/30) = 1/3 ≈ 0.333
      assert_in_delta score, 0.333, 0.01
    end

    test "decays correctly over hours" do
      # 2 hours = 120 minutes
      last_accessed = minutes_ago(120)
      score = ImportanceScorer.recency_score(last_accessed)
      # 1 / (1 + 120/30) = 1/5 = 0.2
      assert_in_delta score, 0.2, 0.01

      # 3 hours = 180 minutes
      last_accessed = minutes_ago(180)
      score = ImportanceScorer.recency_score(last_accessed)
      # 1 / (1 + 180/30) = 1/7 ≈ 0.143
      assert_in_delta score, 0.143, 0.01
    end

    test "handles items accessed in the future gracefully" do
      # Edge case: future timestamp should return 1.0
      future = DateTime.add(DateTime.utc_now(), 3600, :second)
      score = ImportanceScorer.recency_score(future)
      assert_in_delta score, 1.0, 0.01
    end
  end

  # =============================================================================
  # frequency_score/2 Tests
  # =============================================================================

  describe "frequency_score/2" do
    test "returns 0 for 0 accesses" do
      score = ImportanceScorer.frequency_score(0, 10)
      assert score == 0.0
    end

    test "returns 0.5 for 5 accesses with cap 10" do
      score = ImportanceScorer.frequency_score(5, 10)
      assert score == 0.5
    end

    test "caps at 1.0 for accesses >= cap" do
      assert ImportanceScorer.frequency_score(10, 10) == 1.0
      assert ImportanceScorer.frequency_score(15, 10) == 1.0
      assert ImportanceScorer.frequency_score(100, 10) == 1.0
    end

    test "uses default cap when not specified" do
      # Default cap is 10
      score = ImportanceScorer.frequency_score(5)
      assert score == 0.5
    end

    test "scales linearly up to cap" do
      for count <- 0..10 do
        expected = count / 10
        actual = ImportanceScorer.frequency_score(count, 10)
        assert_in_delta actual, expected, 0.001
      end
    end
  end

  # =============================================================================
  # salience_score/1 Tests
  # =============================================================================

  describe "salience_score/1" do
    test "returns 1.0 for :decision" do
      assert ImportanceScorer.salience_score(:decision) == 1.0
    end

    test "returns 1.0 for :lesson_learned" do
      assert ImportanceScorer.salience_score(:lesson_learned) == 1.0
    end

    test "returns 1.0 for :convention" do
      assert ImportanceScorer.salience_score(:convention) == 1.0
    end

    test "returns 1.0 for :risk" do
      assert ImportanceScorer.salience_score(:risk) == 1.0
    end

    test "returns 1.0 for :architectural_decision" do
      assert ImportanceScorer.salience_score(:architectural_decision) == 1.0
    end

    test "returns 1.0 for :coding_standard" do
      assert ImportanceScorer.salience_score(:coding_standard) == 1.0
    end

    test "returns 0.8 for :discovery" do
      assert ImportanceScorer.salience_score(:discovery) == 0.8
    end

    test "returns 0.7 for :fact" do
      assert ImportanceScorer.salience_score(:fact) == 0.7
    end

    test "returns 0.5 for :hypothesis" do
      assert ImportanceScorer.salience_score(:hypothesis) == 0.5
    end

    test "returns 0.4 for :assumption" do
      assert ImportanceScorer.salience_score(:assumption) == 0.4
    end

    test "returns 0.3 for nil" do
      assert ImportanceScorer.salience_score(nil) == 0.3
    end

    test "returns 0.3 for :unknown" do
      assert ImportanceScorer.salience_score(:unknown) == 0.3
    end

    test "returns 0.3 for unrecognized types" do
      assert ImportanceScorer.salience_score(:some_unknown_type) == 0.3
    end
  end

  # =============================================================================
  # score_with_breakdown/1 Tests
  # =============================================================================

  describe "score_with_breakdown/1" do
    test "returns all component scores" do
      item = create_item()
      breakdown = ImportanceScorer.score_with_breakdown(item)

      assert Map.has_key?(breakdown, :total)
      assert Map.has_key?(breakdown, :recency)
      assert Map.has_key?(breakdown, :frequency)
      assert Map.has_key?(breakdown, :confidence)
      assert Map.has_key?(breakdown, :salience)
    end

    test "components sum to total (within float precision)" do
      item = create_item()
      breakdown = ImportanceScorer.score_with_breakdown(item)
      config = ImportanceScorer.get_config()

      weighted_sum =
        config.recency_weight * breakdown.recency +
          config.frequency_weight * breakdown.frequency +
          config.confidence_weight * breakdown.confidence +
          config.salience_weight * breakdown.salience

      assert_in_delta breakdown.total, weighted_sum, 0.001
    end

    test "individual components are between 0 and 1" do
      item = create_item()
      breakdown = ImportanceScorer.score_with_breakdown(item)

      for {key, value} <- breakdown do
        assert value >= 0.0, "#{key} should be >= 0, got #{value}"
        assert value <= 1.0, "#{key} should be <= 1, got #{value}"
      end
    end

    test "breakdown matches individual scoring functions" do
      item = create_item()
      breakdown = ImportanceScorer.score_with_breakdown(item)
      config = ImportanceScorer.get_config()

      assert_in_delta breakdown.recency,
                       ImportanceScorer.recency_score(item.last_accessed),
                       0.001

      assert_in_delta breakdown.frequency,
                       ImportanceScorer.frequency_score(item.access_count, config.frequency_cap),
                       0.001

      assert breakdown.salience == ImportanceScorer.salience_score(item.suggested_type)
    end
  end

  # =============================================================================
  # configure/1 Tests
  # =============================================================================

  describe "configure/1" do
    test "changes weight values" do
      ImportanceScorer.configure(recency_weight: 0.5, frequency_weight: 0.1)

      config = ImportanceScorer.get_config()
      assert config.recency_weight == 0.5
      assert config.frequency_weight == 0.1
      # Unchanged values should remain at defaults
      assert config.confidence_weight == 0.25
      assert config.salience_weight == 0.25
    end

    test "changes frequency cap" do
      ImportanceScorer.configure(frequency_cap: 20)

      config = ImportanceScorer.get_config()
      assert config.frequency_cap == 20
    end

    test "affects score calculations" do
      item = create_item(%{
        last_accessed: DateTime.utc_now(),
        access_count: 10,
        confidence: 0.5,
        suggested_type: :fact
      })

      # Get score with default weights
      default_score = ImportanceScorer.score(item)

      # Change weights to heavily favor confidence
      ImportanceScorer.configure(
        recency_weight: 0.0,
        frequency_weight: 0.0,
        confidence_weight: 1.0,
        salience_weight: 0.0
      )

      # New score should equal confidence (0.5)
      new_score = ImportanceScorer.score(item)
      assert_in_delta new_score, 0.5, 0.01

      # Scores should be different
      refute_in_delta default_score, new_score, 0.01
    end

    test "preserves values not specified" do
      ImportanceScorer.configure(recency_weight: 0.1)
      ImportanceScorer.configure(frequency_weight: 0.2)

      config = ImportanceScorer.get_config()
      # First configure should still be in effect
      assert config.recency_weight == 0.1
      assert config.frequency_weight == 0.2
    end
  end

  # =============================================================================
  # reset_config/0 Tests
  # =============================================================================

  describe "reset_config/0" do
    test "restores default values" do
      ImportanceScorer.configure(
        recency_weight: 0.1,
        frequency_weight: 0.1,
        confidence_weight: 0.1,
        salience_weight: 0.1,
        frequency_cap: 100
      )

      ImportanceScorer.reset_config()

      config = ImportanceScorer.get_config()
      assert config.recency_weight == 0.2
      assert config.frequency_weight == 0.3
      assert config.confidence_weight == 0.25
      assert config.salience_weight == 0.25
      assert config.frequency_cap == 10
    end
  end

  # =============================================================================
  # get_config/0 Tests
  # =============================================================================

  describe "get_config/0" do
    test "returns default configuration" do
      config = ImportanceScorer.get_config()

      assert config.recency_weight == 0.2
      assert config.frequency_weight == 0.3
      assert config.confidence_weight == 0.25
      assert config.salience_weight == 0.25
      assert config.frequency_cap == 10
    end

    test "returns all expected keys" do
      config = ImportanceScorer.get_config()

      expected_keys = [:recency_weight, :frequency_weight, :confidence_weight, :salience_weight, :frequency_cap]

      for key <- expected_keys do
        assert Map.has_key?(config, key), "Missing key: #{key}"
      end
    end
  end

  # =============================================================================
  # high_salience_types/0 Tests
  # =============================================================================

  describe "high_salience_types/0" do
    test "returns list of high salience types" do
      types = ImportanceScorer.high_salience_types()

      assert is_list(types)
      assert :decision in types
      assert :lesson_learned in types
      assert :convention in types
      assert :risk in types
    end

    test "all returned types score 1.0" do
      for type <- ImportanceScorer.high_salience_types() do
        assert ImportanceScorer.salience_score(type) == 1.0,
               "Expected #{type} to have salience score 1.0"
      end
    end
  end

  # =============================================================================
  # Edge Cases
  # =============================================================================

  describe "edge cases" do
    test "handles zero confidence" do
      item = create_item(%{confidence: 0.0})
      score = ImportanceScorer.score(item)
      assert score >= 0.0
    end

    test "handles confidence above 1.0 (clamps to 1.0)" do
      item = create_item(%{confidence: 1.5})
      breakdown = ImportanceScorer.score_with_breakdown(item)
      assert breakdown.confidence == 1.0
    end

    test "handles negative confidence (clamps to 0.0)" do
      item = create_item(%{confidence: -0.5})
      breakdown = ImportanceScorer.score_with_breakdown(item)
      assert breakdown.confidence == 0.0
    end

    test "handles very large access counts" do
      item = create_item(%{access_count: 1_000_000})
      breakdown = ImportanceScorer.score_with_breakdown(item)
      assert breakdown.frequency == 1.0
    end

    test "handles very old items" do
      # 1 year ago
      old_time = DateTime.add(DateTime.utc_now(), -365 * 24 * 60 * 60, :second)
      item = create_item(%{last_accessed: old_time})
      breakdown = ImportanceScorer.score_with_breakdown(item)
      # Score should be very low but still positive
      assert breakdown.recency > 0.0
      assert breakdown.recency < 0.01
    end
  end

  # =============================================================================
  # Integration with Types module
  # =============================================================================

  describe "integration with Types module" do
    test "handles all valid memory types from Types module" do
      for type <- JidoCode.Memory.Types.memory_types() do
        item = create_item(%{suggested_type: type})
        score = ImportanceScorer.score(item)
        assert score >= 0.0 and score <= 1.0, "Invalid score for type #{type}"
      end
    end
  end
end
