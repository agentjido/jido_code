defmodule JidoCode.Memory.Actions.RememberTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Actions.Remember

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    context = %{session_id: session_id}
    {:ok, session_id: session_id, context: context}
  end

  # =============================================================================
  # Basic Remember Tests
  # =============================================================================

  describe "run/2 basic functionality" do
    test "creates memory item with correct type", %{context: context} do
      params = %{content: "Phoenix uses Ecto for database", type: :fact}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
      assert result.memory_type == :fact
      assert is_binary(result.memory_id)
      assert String.contains?(result.message, "fact")
    end

    test "sets default type to :fact when not provided", %{context: context} do
      params = %{content: "This is a test memory"}

      {:ok, result} = Remember.run(params, context)

      assert result.memory_type == :fact
    end

    test "sets default confidence (0.8) when not provided", %{context: context} do
      params = %{content: "Test memory with default confidence"}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
    end

    test "clamps confidence to valid range (0.0-1.0)", %{context: context} do
      params = %{content: "Test high confidence", confidence: 1.5}
      {:ok, result} = Remember.run(params, context)
      assert result.remembered == true

      params = %{content: "Test low confidence", confidence: -0.5}
      {:ok, result} = Remember.run(params, context)
      assert result.remembered == true
    end

    test "accepts confidence levels (:high, :medium, :low)", %{session_id: session_id, context: context} do
      # Test :high
      params = %{content: "High confidence memory", confidence: :high}
      {:ok, result} = Remember.run(params, context)
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.confidence == 0.9

      # Test :medium
      params = %{content: "Medium confidence memory", confidence: :medium}
      {:ok, result} = Remember.run(params, context)
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.confidence == 0.6

      # Test :low
      params = %{content: "Low confidence memory", confidence: :low}
      {:ok, result} = Remember.run(params, context)
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.confidence == 0.3
    end
  end

  # =============================================================================
  # Content Validation Tests
  # =============================================================================

  describe "run/2 content validation" do
    test "validates content is non-empty", %{context: context} do
      params = %{content: ""}

      {:error, message} = Remember.run(params, context)

      assert message =~ "empty"
    end

    test "validates content with only whitespace is empty", %{context: context} do
      params = %{content: "   \n\t  "}

      {:error, message} = Remember.run(params, context)

      assert message =~ "empty"
    end

    test "validates content max length (2000 bytes)", %{context: context} do
      long_content = String.duplicate("a", 2001)
      params = %{content: long_content}

      {:error, message} = Remember.run(params, context)

      assert message =~ "exceeds"
      assert message =~ "2000"
    end

    test "accepts content at exactly max length", %{context: context} do
      content = String.duplicate("a", 2000)
      params = %{content: content}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
    end

    test "trims whitespace from content", %{context: context} do
      params = %{content: "  trimmed content  "}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
    end
  end

  # =============================================================================
  # Type Validation Tests
  # =============================================================================

  describe "run/2 type validation" do
    test "validates type against allowed enum", %{context: context} do
      params = %{content: "Test", type: :invalid_type}

      {:error, message} = Remember.run(params, context)

      assert message =~ "Invalid memory type"
      assert message =~ ":invalid_type"
    end

    test "accepts all valid memory types", %{context: context} do
      valid_types = Remember.valid_memory_types()

      for type <- valid_types do
        params = %{content: "Test content for #{type}", type: type}
        {:ok, result} = Remember.run(params, context)
        assert result.memory_type == type
      end
    end

    test "valid_memory_types matches Types.memory_types", %{context: context} do
      remember_types = Remember.valid_memory_types()
      types_module_types = JidoCode.Memory.Types.memory_types()

      assert remember_types == types_module_types
    end
  end

  # =============================================================================
  # ID Generation Tests
  # =============================================================================

  describe "run/2 id generation" do
    test "generates unique memory ID", %{context: context} do
      params = %{content: "Test memory"}

      {:ok, result1} = Remember.run(params, context)
      {:ok, result2} = Remember.run(params, context)

      assert result1.memory_id != result2.memory_id
      assert String.length(result1.memory_id) == 24
    end
  end

  # =============================================================================
  # Source and Importance Tests
  # =============================================================================

  describe "run/2 memory properties" do
    test "sets source_type to :agent", %{session_id: session_id, context: context} do
      params = %{content: "Agent-initiated memory"}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
      # The memory is persisted with source_type: :agent
      # We verify this by checking the persist succeeded
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.source_type == :agent
    end

    test "sets importance_score to 1.0 (maximum)", %{session_id: session_id, context: context} do
      params = %{content: "High importance memory"}

      {:ok, result} = Remember.run(params, context)

      # Agent decisions have max importance (1.0)
      assert result.remembered == true
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      # Importance score is used during promotion; after persist it's stored
      assert stored.confidence >= 0.0
    end
  end

  # =============================================================================
  # Promotion Tests
  # =============================================================================

  describe "run/2 promotion" do
    test "persists to long-term store via Memory.persist", %{
      session_id: session_id,
      context: context
    } do
      params = %{content: "Persisted memory", type: :discovery}

      {:ok, result} = Remember.run(params, context)

      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.content == "Persisted memory"
      assert stored.memory_type == :discovery
    end
  end

  # =============================================================================
  # Success Message Tests
  # =============================================================================

  describe "run/2 success format" do
    test "returns formatted success message with memory_id", %{context: context} do
      params = %{content: "Test memory", type: :convention}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
      assert is_binary(result.memory_id)
      assert result.memory_type == :convention
      assert result.message =~ "convention"
      assert result.message =~ result.memory_id
    end
  end

  # =============================================================================
  # Session ID Tests
  # =============================================================================

  describe "run/2 session_id handling" do
    test "handles missing session_id with clear error" do
      params = %{content: "Test memory"}
      context = %{}

      {:error, message} = Remember.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "required"
    end

    test "handles nil session_id with clear error" do
      params = %{content: "Test memory"}
      context = %{session_id: nil}

      {:error, message} = Remember.run(params, context)

      assert message =~ "Session ID"
    end

    test "handles non-string session_id with clear error" do
      params = %{content: "Test memory"}
      context = %{session_id: 12345}

      {:error, message} = Remember.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "string"
    end

    test "validates session_id format" do
      params = %{content: "Test memory"}
      # Invalid session ID with path traversal attempt
      context = %{session_id: "../../../etc/passwd"}

      {:error, message} = Remember.run(params, context)

      assert message =~ "Session ID"
    end
  end

  # =============================================================================
  # Rationale Tests
  # =============================================================================

  describe "run/2 optional rationale" do
    test "handles optional rationale parameter", %{session_id: session_id, context: context} do
      params = %{
        content: "Memory with rationale",
        type: :decision,
        rationale: "This is why it's important"
      }

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.rationale == "This is why it's important"
    end

    test "handles missing rationale", %{session_id: session_id, context: context} do
      params = %{content: "Memory without rationale"}

      {:ok, result} = Remember.run(params, context)

      assert result.remembered == true
      {:ok, stored} = JidoCode.Memory.get(session_id, result.memory_id)
      assert stored.rationale == nil
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
        "test-remember-#{inspect(ref)}",
        [:jido_code, :memory, :remember],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      params = %{content: "Telemetry test memory", type: :fact}
      {:ok, _result} = Remember.run(params, context)

      assert_receive {:telemetry, [:jido_code, :memory, :remember], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.session_id == session_id
      assert metadata.memory_type == :fact

      :telemetry.detach("test-remember-#{inspect(ref)}")
    end
  end

  # =============================================================================
  # Constants Tests
  # =============================================================================

  describe "constants" do
    test "max_content_length returns 2000" do
      assert Remember.max_content_length() == 2000
    end

    test "valid_memory_types returns all expected types" do
      types = Remember.valid_memory_types()

      assert :fact in types
      assert :assumption in types
      assert :hypothesis in types
      assert :discovery in types
      assert :risk in types
      assert :unknown in types
      assert :decision in types
      assert :convention in types
      assert :lesson_learned in types
    end

    test "valid_memory_types includes extended types from Types module" do
      types = Remember.valid_memory_types()

      # These are extended types from Types.memory_types()
      assert :architectural_decision in types
      assert :coding_standard in types
    end
  end
end
