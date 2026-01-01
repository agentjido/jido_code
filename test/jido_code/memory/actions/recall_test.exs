defmodule JidoCode.Memory.Actions.RecallTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.{Recall, Remember}
  alias JidoCode.Memory.Actions.Helpers

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    context = %{session_id: session_id}

    # Create some test memories for recall tests
    {:ok, _} =
      Remember.run(
        %{content: "Phoenix uses Ecto for database access", type: :fact, confidence: 0.95},
        context
      )

    {:ok, _} =
      Remember.run(
        %{content: "Users prefer dark mode theme", type: :convention, confidence: 0.8},
        context
      )

    {:ok, _} =
      Remember.run(
        %{content: "The API might need rate limiting", type: :assumption, confidence: 0.6},
        context
      )

    {:ok, _} =
      Remember.run(
        %{content: "Database connection pool size should be increased", type: :discovery, confidence: 0.75},
        context
      )

    {:ok, _} =
      Remember.run(
        %{content: "Low confidence memory item", type: :hypothesis, confidence: 0.3},
        context
      )

    {:ok, session_id: session_id, context: context}
  end

  # =============================================================================
  # Type Filter Tests
  # =============================================================================

  describe "run/2 type filtering" do
    test "returns memories matching type filter", %{context: context} do
      params = %{type: :fact}

      {:ok, result} = Recall.run(params, context)

      assert result.count >= 1
      assert Enum.all?(result.memories, fn m -> m.type == :fact end)
    end

    test "with type :all returns all memory types", %{context: context} do
      params = %{type: :all}

      {:ok, result} = Recall.run(params, context)

      # Should have memories of different types
      types = Enum.map(result.memories, & &1.type) |> Enum.uniq()
      assert length(types) > 1
    end

    test "returns empty list when type has no matches", %{context: context} do
      params = %{type: :risk}

      {:ok, result} = Recall.run(params, context)

      assert result.count == 0
      assert result.memories == []
    end
  end

  # =============================================================================
  # Confidence Filter Tests
  # =============================================================================

  describe "run/2 confidence filtering" do
    test "filters by min_confidence correctly", %{context: context} do
      params = %{min_confidence: 0.7}

      {:ok, result} = Recall.run(params, context)

      assert result.count >= 1
      assert Enum.all?(result.memories, fn m -> m.confidence >= 0.7 end)
    end

    test "returns all memories when min_confidence is 0", %{context: context} do
      params = %{min_confidence: 0.0}

      {:ok, result} = Recall.run(params, context)

      # Should include the low confidence memory
      assert result.count >= 5
    end

    test "returns fewer memories with higher min_confidence", %{context: context} do
      {:ok, low_result} = Recall.run(%{min_confidence: 0.5}, context)
      {:ok, high_result} = Recall.run(%{min_confidence: 0.9}, context)

      assert low_result.count >= high_result.count
    end

    test "clamps min_confidence to valid range", %{context: context} do
      # Above 1.0 should be clamped to 1.0
      {:ok, result} = Recall.run(%{min_confidence: 1.5}, context)
      # All memories have confidence <= 1.0, so this effectively filters all
      assert result.count == 0

      # Below 0.0 should be clamped to 0.0
      {:ok, result} = Recall.run(%{min_confidence: -0.5}, context)
      assert result.count >= 5
    end

    test "accepts confidence levels (:high, :medium, :low)", %{context: context} do
      # :high maps to 0.9
      {:ok, high_result} = Recall.run(%{min_confidence: :high}, context)
      assert Enum.all?(high_result.memories, fn m -> m.confidence >= 0.9 end)

      # :medium maps to 0.6
      {:ok, medium_result} = Recall.run(%{min_confidence: :medium}, context)
      assert Enum.all?(medium_result.memories, fn m -> m.confidence >= 0.6 end)

      # :low maps to 0.3
      {:ok, low_result} = Recall.run(%{min_confidence: :low}, context)
      assert low_result.count >= 5
    end
  end

  # =============================================================================
  # Limit Tests
  # =============================================================================

  describe "run/2 limit parameter" do
    test "respects limit parameter", %{context: context} do
      params = %{limit: 2}

      {:ok, result} = Recall.run(params, context)

      assert result.count <= 2
    end

    test "validates limit range (1-50)", %{context: context} do
      {:error, message} = Recall.run(%{limit: 0}, context)
      assert message =~ "at least 1"

      {:error, message} = Recall.run(%{limit: 51}, context)
      assert message =~ "cannot exceed 50"
    end

    test "uses default limit when not provided", %{context: context} do
      params = %{min_confidence: 0.0}

      {:ok, result} = Recall.run(params, context)

      # Default limit is 10, we have 5 memories, so should return all 5
      # Using min_confidence: 0.0 to include the low confidence memory
      assert result.count == 5
    end
  end

  # =============================================================================
  # Query Text Search Tests
  # =============================================================================

  describe "run/2 text query" do
    test "with query performs text search (case-insensitive)", %{context: context} do
      params = %{query: "phoenix"}

      {:ok, result} = Recall.run(params, context)

      assert result.count >= 1
      assert Enum.all?(result.memories, fn m ->
        String.contains?(String.downcase(m.content), "phoenix")
      end)
    end

    test "query is case-insensitive", %{context: context} do
      {:ok, lower} = Recall.run(%{query: "ecto"}, context)
      {:ok, upper} = Recall.run(%{query: "ECTO"}, context)
      {:ok, mixed} = Recall.run(%{query: "EcTo"}, context)

      assert lower.count == upper.count
      assert lower.count == mixed.count
    end

    test "with query filters results after type/confidence", %{context: context} do
      params = %{type: :fact, query: "phoenix", min_confidence: 0.9}

      {:ok, result} = Recall.run(params, context)

      assert result.count >= 1
      assert Enum.all?(result.memories, fn m ->
        m.type == :fact and m.confidence >= 0.9 and
          String.contains?(String.downcase(m.content), "phoenix")
      end)
    end

    test "returns empty when query has no matches", %{context: context} do
      params = %{query: "nonexistent_term_xyz123"}

      {:ok, result} = Recall.run(params, context)

      assert result.count == 0
    end

    test "handles empty query string", %{context: context} do
      params = %{query: "   ", min_confidence: 0.0}

      {:ok, result} = Recall.run(params, context)

      # Empty query should be treated as no query filter
      # Using min_confidence: 0.0 to include all memories
      assert result.count == 5
    end

    test "validates query max length", %{context: context} do
      long_query = String.duplicate("a", 1001)
      params = %{query: long_query}

      {:error, message} = Recall.run(params, context)

      assert message =~ "exceeds"
      assert message =~ "1000"
    end

    test "accepts query at exactly max length", %{context: context} do
      query = String.duplicate("a", 1000)
      params = %{query: query}

      {:ok, result} = Recall.run(params, context)

      # Should not find matches but should succeed
      assert result.count == 0
    end
  end

  # =============================================================================
  # Access Recording Tests
  # =============================================================================

  describe "run/2 access tracking" do
    test "records access for all returned memories", %{context: context} do
      # First recall
      {:ok, result1} = Recall.run(%{type: :fact}, context)
      memory_id = hd(result1.memories).id

      # Record should have been updated
      {:ok, memory} = Memory.get(context.session_id, memory_id)
      assert memory.access_count >= 1
    end
  end

  # =============================================================================
  # Result Format Tests
  # =============================================================================

  describe "run/2 result formatting" do
    test "returns empty list when no matches", %{session_id: session_id} do
      # Use a fresh session with no memories
      fresh_session = "empty-#{session_id}"
      context = %{session_id: fresh_session}

      {:ok, result} = Recall.run(%{}, context)

      assert result.count == 0
      assert result.memories == []
    end

    test "formats results with count and memory list", %{context: context} do
      {:ok, result} = Recall.run(%{}, context)

      assert is_integer(result.count)
      assert is_list(result.memories)
      assert result.count == length(result.memories)
    end

    test "each memory has expected fields", %{context: context} do
      {:ok, result} = Recall.run(%{}, context)

      assert result.count > 0

      Enum.each(result.memories, fn mem ->
        assert is_binary(mem.id)
        assert is_binary(mem.content)
        assert is_atom(mem.type)
        assert is_number(mem.confidence)
        assert is_binary(mem.timestamp) or is_nil(mem.timestamp)
      end)
    end

    test "formats timestamps as ISO8601 strings", %{context: context} do
      {:ok, result} = Recall.run(%{}, context)

      assert result.count > 0

      # Check that timestamps are properly formatted ISO8601 strings
      Enum.each(result.memories, fn mem ->
        if mem.timestamp do
          # Should be able to parse as ISO8601
          assert {:ok, _, _} = DateTime.from_iso8601(mem.timestamp)
        end
      end)
    end
  end

  # =============================================================================
  # Session ID Tests
  # =============================================================================

  describe "run/2 session_id handling" do
    test "handles missing session_id with clear error" do
      params = %{}
      context = %{}

      {:error, message} = Recall.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "required"
    end

    test "handles nil session_id with clear error" do
      params = %{}
      context = %{session_id: nil}

      {:error, message} = Recall.run(params, context)

      assert message =~ "Session ID"
    end

    test "handles non-string session_id with clear error" do
      params = %{}
      context = %{session_id: 12345}

      {:error, message} = Recall.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "string"
    end

    test "validates session_id format" do
      params = %{}
      # Invalid session ID with path traversal attempt
      context = %{session_id: "../../../etc/passwd"}

      {:error, message} = Recall.run(params, context)

      assert message =~ "Session ID"
    end
  end

  # =============================================================================
  # Telemetry Tests
  # =============================================================================

  describe "run/2 telemetry" do
    test "emits telemetry event", %{session_id: session_id, context: context} do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-recall-#{inspect(ref)}",
        [:jido_code, :memory, :recall],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      params = %{type: :fact, min_confidence: 0.5}
      {:ok, _result} = Recall.run(params, context)

      assert_receive {:telemetry, [:jido_code, :memory, :recall], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert is_integer(measurements.result_count)
      assert metadata.session_id == session_id
      assert metadata.memory_type == :fact
      assert metadata.min_confidence == 0.5
      assert metadata.has_query == false

      :telemetry.detach("test-recall-#{inspect(ref)}")
    end

    test "telemetry includes query flag", %{context: context} do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-recall-query-#{inspect(ref)}",
        [:jido_code, :memory, :recall],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _result} = Recall.run(%{query: "phoenix"}, context)

      assert_receive {:telemetry, [:jido_code, :memory, :recall], _measurements, metadata}
      assert metadata.has_query == true

      :telemetry.detach("test-recall-query-#{inspect(ref)}")
    end
  end

  # =============================================================================
  # Type Validation Tests
  # =============================================================================

  describe "run/2 type validation" do
    test "validates type against allowed enum", %{context: context} do
      params = %{type: :invalid_type}

      {:error, message} = Recall.run(params, context)

      assert message =~ "Invalid memory type"
      assert message =~ ":invalid_type"
    end

    test "accepts all valid types", %{context: context} do
      valid_types = Recall.valid_types()

      for type <- valid_types do
        {:ok, result} = Recall.run(%{type: type}, context)
        assert is_map(result)
      end
    end
  end

  # =============================================================================
  # Constants Tests
  # =============================================================================

  describe "constants" do
    test "max_limit returns 50" do
      assert Recall.max_limit() == 50
    end

    test "min_limit returns 1" do
      assert Recall.min_limit() == 1
    end

    test "default_limit returns 10" do
      assert Recall.default_limit() == 10
    end

    test "max_query_length returns 1000" do
      assert Recall.max_query_length() == 1000
    end

    test "valid_types includes expected types" do
      types = Recall.valid_types()

      assert :all in types
      assert :fact in types
      assert :assumption in types
      assert :hypothesis in types
      assert :discovery in types
      assert :risk in types
      assert :decision in types
      assert :convention in types
      assert :lesson_learned in types
    end

    test "valid_types includes all Types.memory_types plus :all" do
      recall_types = Recall.valid_types()
      memory_types = JidoCode.Memory.Types.memory_types()

      # :all is only in Recall, not in Types.memory_types
      assert :all in recall_types
      refute :all in memory_types

      # All memory types should be in recall types
      for type <- memory_types do
        assert type in recall_types
      end
    end
  end

  # =============================================================================
  # Helpers Module Tests
  # =============================================================================

  describe "Helpers module" do
    test "format_timestamp handles DateTime" do
      dt = DateTime.utc_now()
      result = Helpers.format_timestamp(dt)

      assert is_binary(result)
      assert {:ok, _, _} = DateTime.from_iso8601(result)
    end

    test "format_timestamp handles nil" do
      assert Helpers.format_timestamp(nil) == nil
    end

    test "format_timestamp handles other values" do
      result = Helpers.format_timestamp(:something_else)
      assert result == ":something_else"
    end

    test "get_session_id validates format" do
      # Valid session ID
      {:ok, id} = Helpers.get_session_id(%{session_id: "valid-session-123"})
      assert id == "valid-session-123"

      # Invalid format
      {:error, :invalid_session_id} = Helpers.get_session_id(%{session_id: "../path/traversal"})

      # Missing
      {:error, :missing_session_id} = Helpers.get_session_id(%{})

      # Nil
      {:error, :missing_session_id} = Helpers.get_session_id(%{session_id: nil})
    end

    test "format_common_error handles known errors" do
      assert Helpers.format_common_error(:missing_session_id) =~ "required"
      assert Helpers.format_common_error(:invalid_session_id) =~ "valid string"
      assert Helpers.format_common_error(:unknown_error) == nil
    end

    test "validate_confidence handles numeric values" do
      {:ok, conf} = Helpers.validate_confidence(%{confidence: 0.7}, :confidence, 0.8)
      assert conf == 0.7
    end

    test "validate_confidence handles confidence levels" do
      {:ok, high} = Helpers.validate_confidence(%{confidence: :high}, :confidence, 0.5)
      assert high == 0.9

      {:ok, medium} = Helpers.validate_confidence(%{confidence: :medium}, :confidence, 0.5)
      assert medium == 0.6

      {:ok, low} = Helpers.validate_confidence(%{confidence: :low}, :confidence, 0.5)
      assert low == 0.3
    end

    test "validate_confidence uses default for missing values" do
      {:ok, conf} = Helpers.validate_confidence(%{}, :confidence, 0.8)
      assert conf == 0.8
    end

    test "validate_non_empty_string handles valid strings" do
      {:ok, result} = Helpers.validate_non_empty_string("hello")
      assert result == "hello"

      {:ok, trimmed} = Helpers.validate_non_empty_string("  hello  ")
      assert trimmed == "hello"
    end

    test "validate_non_empty_string rejects empty strings" do
      {:error, :empty_string} = Helpers.validate_non_empty_string("")
      {:error, :empty_string} = Helpers.validate_non_empty_string("   ")
    end

    test "validate_non_empty_string rejects non-strings" do
      {:error, :not_a_string} = Helpers.validate_non_empty_string(nil)
      {:error, :not_a_string} = Helpers.validate_non_empty_string(123)
    end

    test "validate_bounded_string handles valid strings within limit" do
      {:ok, result} = Helpers.validate_bounded_string("hello", 100)
      assert result == "hello"
    end

    test "validate_bounded_string rejects strings over limit" do
      {:error, {:too_long, 5, 3}} = Helpers.validate_bounded_string("hello", 3)
    end

    test "validate_bounded_string rejects empty strings" do
      {:error, :empty_string} = Helpers.validate_bounded_string("", 100)
      {:error, :empty_string} = Helpers.validate_bounded_string("   ", 100)
    end

    test "validate_optional_string handles valid strings" do
      {:ok, "hello"} = Helpers.validate_optional_string("hello")
    end

    test "validate_optional_string returns nil for empty/missing" do
      {:ok, nil} = Helpers.validate_optional_string("")
      {:ok, nil} = Helpers.validate_optional_string("   ")
      {:ok, nil} = Helpers.validate_optional_string(nil)
    end

    test "validate_optional_bounded_string handles valid strings" do
      {:ok, "hello"} = Helpers.validate_optional_bounded_string("hello", 100)
    end

    test "validate_optional_bounded_string returns nil for empty" do
      {:ok, nil} = Helpers.validate_optional_bounded_string("", 100)
      {:ok, nil} = Helpers.validate_optional_bounded_string(nil, 100)
    end

    test "validate_optional_bounded_string rejects over limit" do
      {:error, {:too_long, 5, 3}} = Helpers.validate_optional_bounded_string("hello", 3)
    end
  end
end
