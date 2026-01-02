defmodule JidoCode.Memory.TypesTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Types

  describe "memory_type" do
    test "memory_types/0 returns all valid memory types matching Jido ontology" do
      expected = [
        :fact,
        :assumption,
        :hypothesis,
        :discovery,
        :risk,
        :unknown,
        :decision,
        :architectural_decision,
        :convention,
        :coding_standard,
        :lesson_learned
      ]

      assert Types.memory_types() == expected
    end

    test "valid_memory_type?/1 returns true for all valid types" do
      for type <- Types.memory_types() do
        assert Types.valid_memory_type?(type),
               "Expected #{inspect(type)} to be a valid memory type"
      end
    end

    test "valid_memory_type?/1 returns false for invalid types" do
      refute Types.valid_memory_type?(:invalid)
      refute Types.valid_memory_type?("fact")
      refute Types.valid_memory_type?(nil)
      refute Types.valid_memory_type?(123)
    end
  end

  describe "confidence_level" do
    test "confidence_levels/0 returns all valid confidence levels" do
      assert Types.confidence_levels() == [:high, :medium, :low]
    end

    test "valid_confidence_level?/1 returns true for all valid levels" do
      for level <- Types.confidence_levels() do
        assert Types.valid_confidence_level?(level),
               "Expected #{inspect(level)} to be a valid confidence level"
      end
    end

    test "valid_confidence_level?/1 returns false for invalid levels" do
      refute Types.valid_confidence_level?(:very_high)
      refute Types.valid_confidence_level?("high")
      refute Types.valid_confidence_level?(nil)
    end
  end

  describe "confidence_to_level/1" do
    test "returns :high for confidence >= 0.8" do
      assert Types.confidence_to_level(1.0) == :high
      assert Types.confidence_to_level(0.95) == :high
      assert Types.confidence_to_level(0.9) == :high
      assert Types.confidence_to_level(0.8) == :high
    end

    test "returns :medium for 0.5 <= confidence < 0.8" do
      assert Types.confidence_to_level(0.79) == :medium
      assert Types.confidence_to_level(0.7) == :medium
      assert Types.confidence_to_level(0.6) == :medium
      assert Types.confidence_to_level(0.5) == :medium
    end

    test "returns :low for confidence < 0.5" do
      assert Types.confidence_to_level(0.49) == :low
      assert Types.confidence_to_level(0.3) == :low
      assert Types.confidence_to_level(0.1) == :low
      assert Types.confidence_to_level(0.0) == :low
    end

    test "handles boundary values correctly" do
      # Exact boundaries
      assert Types.confidence_to_level(0.8) == :high
      assert Types.confidence_to_level(0.5) == :medium

      # Just below boundaries
      assert Types.confidence_to_level(0.7999999) == :medium
      assert Types.confidence_to_level(0.4999999) == :low
    end
  end

  describe "level_to_confidence/1" do
    test "returns 0.9 for :high" do
      assert Types.level_to_confidence(:high) == 0.9
    end

    test "returns 0.6 for :medium" do
      assert Types.level_to_confidence(:medium) == 0.6
    end

    test "returns 0.3 for :low" do
      assert Types.level_to_confidence(:low) == 0.3
    end

    test "round-trip conversion maintains level" do
      for level <- Types.confidence_levels() do
        confidence = Types.level_to_confidence(level)
        assert Types.confidence_to_level(confidence) == level,
               "Round-trip failed for level #{inspect(level)}"
      end
    end
  end

  describe "clamp_to_unit/1" do
    test "clamps negative values to 0.0" do
      assert Types.clamp_to_unit(-0.5) == 0.0
      assert Types.clamp_to_unit(-100) == 0.0
      assert Types.clamp_to_unit(-0.001) == 0.0
    end

    test "clamps values > 1.0 to 1.0" do
      assert Types.clamp_to_unit(1.5) == 1.0
      assert Types.clamp_to_unit(100) == 1.0
      assert Types.clamp_to_unit(1.001) == 1.0
    end

    test "passes through values in [0.0, 1.0]" do
      assert Types.clamp_to_unit(0.0) == 0.0
      assert Types.clamp_to_unit(0.5) == 0.5
      assert Types.clamp_to_unit(1.0) == 1.0
      assert Types.clamp_to_unit(0.333) == 0.333
    end

    test "converts integers to floats" do
      result = Types.clamp_to_unit(0)
      assert result == 0.0
      assert is_float(result)

      result = Types.clamp_to_unit(1)
      assert result == 1.0
      assert is_float(result)
    end
  end

  describe "source_type" do
    test "source_types/0 returns all valid source types matching Jido SourceType" do
      expected = [:user, :agent, :tool, :external_document]
      assert Types.source_types() == expected
    end

    test "valid_source_type?/1 returns true for all valid types" do
      for type <- Types.source_types() do
        assert Types.valid_source_type?(type),
               "Expected #{inspect(type)} to be a valid source type"
      end
    end

    test "valid_source_type?/1 returns false for invalid types" do
      refute Types.valid_source_type?(:system)
      refute Types.valid_source_type?("user")
      refute Types.valid_source_type?(nil)
    end
  end

  describe "context_key" do
    test "context_keys/0 returns all valid context keys matching design specification" do
      expected = [
        :active_file,
        :project_root,
        :primary_language,
        :framework,
        :current_task,
        :user_intent,
        :discovered_patterns,
        :active_errors,
        :pending_questions,
        :file_relationships,
        :conversation_summary
      ]

      assert Types.context_keys() == expected
    end

    test "valid_context_key?/1 returns true for all valid keys" do
      for key <- Types.context_keys() do
        assert Types.valid_context_key?(key),
               "Expected #{inspect(key)} to be a valid context key"
      end
    end

    test "valid_context_key?/1 returns false for invalid keys" do
      refute Types.valid_context_key?(:invalid_key)
      refute Types.valid_context_key?("active_file")
      refute Types.valid_context_key?(nil)
    end

    test "context_keys exhaustiveness - all 11 keys are defined" do
      assert length(Types.context_keys()) == 11
    end
  end

  describe "pending_item type structure" do
    test "can create a pending_item with all required fields" do
      now = DateTime.utc_now()

      item = %{
        id: "test-id-123",
        content: "The project uses Phoenix 1.7",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: ["mix.exs:5", "config/config.exs:10"],
        rationale: "Discovered from dependency analysis",
        suggested_by: :implicit,
        importance_score: 0.85,
        created_at: now,
        access_count: 0
      }

      assert item.id == "test-id-123"
      assert item.content == "The project uses Phoenix 1.7"
      assert item.memory_type == :fact
      assert item.confidence == 0.9
      assert item.source_type == :tool
      assert item.evidence == ["mix.exs:5", "config/config.exs:10"]
      assert item.rationale == "Discovered from dependency analysis"
      assert item.suggested_by == :implicit
      assert item.importance_score == 0.85
      assert item.created_at == now
      assert item.access_count == 0
    end

    test "can create a pending_item with optional rationale as nil" do
      now = DateTime.utc_now()

      item = %{
        id: "test-id-456",
        content: "User prefers explicit types",
        memory_type: :assumption,
        confidence: 0.6,
        source_type: :agent,
        evidence: [],
        rationale: nil,
        suggested_by: :agent,
        importance_score: 1.0,
        created_at: now,
        access_count: 1
      }

      assert item.rationale == nil
      assert item.suggested_by == :agent
      assert item.importance_score == 1.0
    end

    test "pending_item memory_type uses valid memory_type" do
      item = %{
        id: "id",
        content: "content",
        memory_type: :decision,
        confidence: 0.8,
        source_type: :user,
        evidence: [],
        rationale: nil,
        suggested_by: :agent,
        importance_score: 0.9,
        created_at: DateTime.utc_now(),
        access_count: 0
      }

      assert Types.valid_memory_type?(item.memory_type)
    end

    test "pending_item source_type uses valid source_type" do
      item = %{
        id: "id",
        content: "content",
        memory_type: :fact,
        confidence: 0.8,
        source_type: :external_document,
        evidence: [],
        rationale: nil,
        suggested_by: :implicit,
        importance_score: 0.5,
        created_at: DateTime.utc_now(),
        access_count: 0
      }

      assert Types.valid_source_type?(item.source_type)
    end
  end

  describe "access_entry type structure" do
    test "can create an access_entry with context_key" do
      now = DateTime.utc_now()

      entry = %{
        key: :active_file,
        timestamp: now,
        access_type: :read
      }

      assert entry.key == :active_file
      assert entry.timestamp == now
      assert entry.access_type == :read
    end

    test "can create an access_entry with memory tuple key" do
      now = DateTime.utc_now()

      entry = %{
        key: {:memory, "memory-id-123"},
        timestamp: now,
        access_type: :query
      }

      assert entry.key == {:memory, "memory-id-123"}
      assert entry.access_type == :query
    end

    test "access_entry supports all access_type values" do
      now = DateTime.utc_now()

      for access_type <- [:read, :write, :query] do
        entry = %{
          key: :project_root,
          timestamp: now,
          access_type: access_type
        }

        assert entry.access_type == access_type
      end
    end

    test "access_entry key can be any valid context_key" do
      now = DateTime.utc_now()

      for context_key <- Types.context_keys() do
        entry = %{
          key: context_key,
          timestamp: now,
          access_type: :read
        }

        assert Types.valid_context_key?(entry.key)
      end
    end
  end
end
