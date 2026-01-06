defmodule JidoCode.Memory.Actions.ForgetTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory
  alias JidoCode.Memory.Actions.{Forget, Remember}

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    session_id = "test-session-#{System.unique_integer([:positive])}"
    context = %{session_id: session_id}

    # Create a test memory to forget
    {:ok, result} =
      Remember.run(
        %{content: "This memory will be forgotten", type: :fact, confidence: 0.9},
        context
      )

    {:ok, session_id: session_id, context: context, memory_id: result.memory_id}
  end

  # =============================================================================
  # Basic Forget Tests
  # =============================================================================

  describe "run/2 basic functionality" do
    test "marks memory as superseded", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      assert result.memory_id == memory_id
      assert result.message =~ "superseded"
    end

    test "forgotten memory excluded from normal recall queries", %{
      context: context,
      memory_id: memory_id
    } do
      # First verify the memory exists in recall
      {:ok, before_result} = Memory.Actions.Recall.run(%{min_confidence: 0.0}, context)
      assert Enum.any?(before_result.memories, fn m -> m.id == memory_id end)

      # Forget the memory
      {:ok, _} = Forget.run(%{memory_id: memory_id}, context)

      # Verify the memory is no longer in recall results
      {:ok, after_result} = Memory.Actions.Recall.run(%{min_confidence: 0.0}, context)
      refute Enum.any?(after_result.memories, fn m -> m.id == memory_id end)
    end

    test "forgotten memory still exists in store", %{
      session_id: session_id,
      context: context,
      memory_id: memory_id
    } do
      # Forget the memory
      {:ok, _} = Forget.run(%{memory_id: memory_id}, context)

      # Verify the memory still exists (can be retrieved with include_superseded)
      {:ok, memories} = Memory.query(session_id, include_superseded: true)
      memory = Enum.find(memories, fn m -> m.id == memory_id end)
      assert memory != nil
      assert memory.id == memory_id
    end
  end

  # =============================================================================
  # Replacement Tests
  # =============================================================================

  describe "run/2 with replacement_id" do
    test "creates supersededBy relation", %{context: context, memory_id: old_memory_id} do
      # Create replacement memory
      {:ok, replacement} =
        Remember.run(
          %{content: "This is the replacement memory", type: :fact},
          context
        )

      # Forget with replacement
      params = %{memory_id: old_memory_id, replacement_id: replacement.memory_id}
      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      assert result.memory_id == old_memory_id
      assert result.replacement_id == replacement.memory_id
      assert result.message =~ "superseded by"
    end

    test "validates replacement_id exists", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id, replacement_id: "nonexistent-id-123"}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Replacement memory not found"
      assert message =~ "nonexistent-id-123"
    end

    test "handles empty replacement_id as nil", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id, replacement_id: "   "}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      refute Map.has_key?(result, :replacement_id)
    end
  end

  # =============================================================================
  # Memory ID Validation Tests
  # =============================================================================

  describe "run/2 memory_id validation" do
    test "validates memory_id exists", %{context: context} do
      params = %{memory_id: "nonexistent-memory-id-xyz"}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Memory not found"
      assert message =~ "nonexistent-memory-id-xyz"
    end

    test "handles non-existent memory_id with clear error", %{context: context} do
      params = %{memory_id: "does-not-exist"}

      {:error, message} = Forget.run(params, context)

      assert message =~ "not found"
    end

    test "validates memory_id is non-empty", %{context: context} do
      params = %{memory_id: ""}

      {:error, message} = Forget.run(params, context)

      assert message =~ "empty"
    end

    test "validates memory_id with only whitespace", %{context: context} do
      params = %{memory_id: "   "}

      {:error, message} = Forget.run(params, context)

      assert message =~ "empty"
    end

    test "validates memory_id is a string", %{context: context} do
      params = %{memory_id: 12345}

      {:error, message} = Forget.run(params, context)

      assert message =~ "string"
    end

    test "validates memory_id is required", %{context: context} do
      params = %{}

      {:error, message} = Forget.run(params, context)

      assert message =~ "required"
    end
  end

  # =============================================================================
  # Reason Tests
  # =============================================================================

  describe "run/2 optional reason" do
    test "stores reason if provided", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id, reason: "Information is outdated"}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      assert result.reason == "Information is outdated"
    end

    test "handles missing reason", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      refute Map.has_key?(result, :reason)
    end

    test "handles empty reason as nil", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id, reason: "   "}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      refute Map.has_key?(result, :reason)
    end

    test "validates reason max length", %{context: context, memory_id: memory_id} do
      long_reason = String.duplicate("a", 501)
      params = %{memory_id: memory_id, reason: long_reason}

      {:error, message} = Forget.run(params, context)

      assert message =~ "exceeds"
      assert message =~ "500"
    end

    test "accepts reason at exactly max length", %{context: context, memory_id: memory_id} do
      reason = String.duplicate("a", 500)
      params = %{memory_id: memory_id, reason: reason}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      assert result.reason == reason
    end
  end

  # =============================================================================
  # Success Message Tests
  # =============================================================================

  describe "run/2 success format" do
    test "returns formatted success message", %{context: context, memory_id: memory_id} do
      params = %{memory_id: memory_id}

      {:ok, result} = Forget.run(params, context)

      assert result.forgotten == true
      assert is_binary(result.memory_id)
      assert result.message =~ memory_id
      assert result.message =~ "superseded"
    end

    test "includes replacement in message when provided", %{context: context, memory_id: memory_id} do
      # Create replacement
      {:ok, replacement} =
        Remember.run(%{content: "Replacement", type: :fact}, context)

      params = %{memory_id: memory_id, replacement_id: replacement.memory_id}
      {:ok, result} = Forget.run(params, context)

      assert result.message =~ "superseded by"
      assert result.message =~ replacement.memory_id
    end
  end

  # =============================================================================
  # Session ID Tests
  # =============================================================================

  describe "run/2 session_id handling" do
    test "handles missing session_id with clear error" do
      params = %{memory_id: "some-id"}
      context = %{}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "required"
    end

    test "handles nil session_id with clear error" do
      params = %{memory_id: "some-id"}
      context = %{session_id: nil}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Session ID"
    end

    test "handles non-string session_id with clear error" do
      params = %{memory_id: "some-id"}
      context = %{session_id: 12345}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Session ID"
      assert message =~ "string"
    end

    test "validates session_id format" do
      params = %{memory_id: "some-id"}
      context = %{session_id: "../../../etc/passwd"}

      {:error, message} = Forget.run(params, context)

      assert message =~ "Session ID"
    end
  end

  # =============================================================================
  # Telemetry Tests
  # =============================================================================

  describe "run/2 telemetry" do
    test "emits telemetry event", %{session_id: session_id, context: context, memory_id: memory_id} do
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-forget-#{inspect(ref)}",
        [:jido_code, :memory, :forget],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _result} = Forget.run(%{memory_id: memory_id}, context)

      assert_receive {:telemetry, [:jido_code, :memory, :forget], measurements, metadata}
      assert is_integer(measurements.duration)
      assert measurements.duration >= 0
      assert metadata.session_id == session_id
      assert metadata.memory_id == memory_id
      assert metadata.has_replacement == false
      assert metadata.has_reason == false

      :telemetry.detach("test-forget-#{inspect(ref)}")
    end

    test "telemetry includes replacement and reason flags", %{
      context: context,
      memory_id: memory_id
    } do
      ref = make_ref()
      test_pid = self()

      # Create replacement
      {:ok, replacement} =
        Remember.run(%{content: "Replacement", type: :fact}, context)

      :telemetry.attach(
        "test-forget-flags-#{inspect(ref)}",
        [:jido_code, :memory, :forget],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      params = %{
        memory_id: memory_id,
        replacement_id: replacement.memory_id,
        reason: "Testing telemetry"
      }

      {:ok, _result} = Forget.run(params, context)

      assert_receive {:telemetry, [:jido_code, :memory, :forget], _measurements, metadata}
      assert metadata.has_replacement == true
      assert metadata.has_reason == true

      :telemetry.detach("test-forget-flags-#{inspect(ref)}")
    end
  end

  # =============================================================================
  # Constants Tests
  # =============================================================================

  describe "constants" do
    test "max_reason_length returns 500" do
      assert Forget.max_reason_length() == 500
    end
  end

  # =============================================================================
  # Include Superseded Tests
  # =============================================================================

  describe "forgotten memories with include_superseded" do
    test "forgotten memories still retrievable with include_superseded option", %{
      session_id: session_id,
      context: context,
      memory_id: memory_id
    } do
      # Forget the memory
      {:ok, _} = Forget.run(%{memory_id: memory_id}, context)

      # Query with include_superseded
      {:ok, memories} = Memory.query(session_id, include_superseded: true)

      # Should find the superseded memory
      assert Enum.any?(memories, fn m -> m.id == memory_id end)
    end
  end
end
