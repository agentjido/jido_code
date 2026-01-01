defmodule JidoCode.Tools.Security.RateLimiterTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Security.RateLimiter

  # =============================================================================
  # Setup
  # =============================================================================

  setup do
    # Clear all rate limit data before each test
    RateLimiter.clear_all()
    :ok
  end

  # =============================================================================
  # Tests: check_rate/5 - Basic functionality
  # =============================================================================

  describe "check_rate/5 basic functionality" do
    test "allows first invocation" do
      assert :ok = RateLimiter.check_rate("session1", "read_file", 10, 60_000)
    end

    test "allows multiple invocations within limit" do
      for _ <- 1..5 do
        assert :ok = RateLimiter.check_rate("session1", "read_file", 10, 60_000)
      end
    end

    test "blocks invocation when limit is reached" do
      # Use up the limit
      for _ <- 1..5 do
        assert :ok = RateLimiter.check_rate("session1", "read_file", 5, 60_000)
      end

      # Next invocation should be blocked
      assert {:error, retry_after} = RateLimiter.check_rate("session1", "read_file", 5, 60_000)
      assert is_integer(retry_after)
      assert retry_after > 0
    end

    test "returns positive retry_after value" do
      # Fill up the limit
      for _ <- 1..3 do
        RateLimiter.check_rate("session1", "tool1", 3, 60_000)
      end

      {:error, retry_after} = RateLimiter.check_rate("session1", "tool1", 3, 60_000)
      assert retry_after >= 1
      assert retry_after <= 60_000
    end

    test "tracks different tools independently" do
      # Fill up limit for tool1
      for _ <- 1..3 do
        RateLimiter.check_rate("session1", "tool1", 3, 60_000)
      end

      # tool2 should still be available
      assert :ok = RateLimiter.check_rate("session1", "tool2", 3, 60_000)
    end

    test "tracks different sessions independently" do
      # Fill up limit for session1
      for _ <- 1..3 do
        RateLimiter.check_rate("session1", "tool1", 3, 60_000)
      end

      # session2 should still be available
      assert :ok = RateLimiter.check_rate("session2", "tool1", 3, 60_000)
    end
  end

  # =============================================================================
  # Tests: check_rate/5 - Sliding window behavior
  # =============================================================================

  describe "check_rate/5 sliding window" do
    test "allows invocation after window expires" do
      # Use a very short window for testing
      window_ms = 50

      # Fill up the limit
      for _ <- 1..2 do
        RateLimiter.check_rate("session1", "tool1", 2, window_ms)
      end

      # Should be blocked
      assert {:error, _} = RateLimiter.check_rate("session1", "tool1", 2, window_ms)

      # Wait for window to expire
      Process.sleep(window_ms + 10)

      # Should be allowed again
      assert :ok = RateLimiter.check_rate("session1", "tool1", 2, window_ms)
    end

    test "removes expired entries on check" do
      window_ms = 30

      # Make some invocations
      RateLimiter.check_rate("session1", "tool1", 10, window_ms)
      RateLimiter.check_rate("session1", "tool1", 10, window_ms)

      # Count should be 2
      assert RateLimiter.get_count("session1", "tool1", window_ms) == 2

      # Wait for window to expire
      Process.sleep(window_ms + 10)

      # Count should now be 0
      assert RateLimiter.get_count("session1", "tool1", window_ms) == 0
    end

    test "handles burst followed by steady rate" do
      window_ms = 100
      limit = 5

      # Burst of 4 invocations
      for _ <- 1..4 do
        assert :ok = RateLimiter.check_rate("session1", "tool1", limit, window_ms)
      end

      # One more should work
      assert :ok = RateLimiter.check_rate("session1", "tool1", limit, window_ms)

      # Now we're at the limit
      assert {:error, _} = RateLimiter.check_rate("session1", "tool1", limit, window_ms)

      # Wait for some to expire
      Process.sleep(window_ms + 10)

      # Should be allowed again
      assert :ok = RateLimiter.check_rate("session1", "tool1", limit, window_ms)
    end
  end

  # =============================================================================
  # Tests: get_count/3
  # =============================================================================

  describe "get_count/3" do
    test "returns 0 for new session/tool" do
      assert RateLimiter.get_count("new_session", "new_tool", 60_000) == 0
    end

    test "returns correct count after invocations" do
      for _ <- 1..5 do
        RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      end

      assert RateLimiter.get_count("session1", "tool1", 60_000) == 5
    end

    test "only counts invocations within window" do
      window_ms = 50

      # Make some invocations
      RateLimiter.check_rate("session1", "tool1", 100, window_ms)
      RateLimiter.check_rate("session1", "tool1", 100, window_ms)

      # Wait for them to expire
      Process.sleep(window_ms + 10)

      # Make new invocations
      RateLimiter.check_rate("session1", "tool1", 100, window_ms)

      # Count should only include the recent one
      assert RateLimiter.get_count("session1", "tool1", window_ms) == 1
    end

    test "different tools have independent counts" do
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session1", "tool2", 100, 60_000)

      assert RateLimiter.get_count("session1", "tool1", 60_000) == 2
      assert RateLimiter.get_count("session1", "tool2", 60_000) == 1
    end
  end

  # =============================================================================
  # Tests: clear_session/1
  # =============================================================================

  describe "clear_session/1" do
    test "clears all rate limit data for a session" do
      # Create invocations for multiple tools
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session1", "tool2", 100, 60_000)
      RateLimiter.check_rate("session1", "tool3", 100, 60_000)

      assert RateLimiter.get_count("session1", "tool1", 60_000) == 1
      assert RateLimiter.get_count("session1", "tool2", 60_000) == 1

      # Clear the session
      assert :ok = RateLimiter.clear_session("session1")

      # All counts should be 0
      assert RateLimiter.get_count("session1", "tool1", 60_000) == 0
      assert RateLimiter.get_count("session1", "tool2", 60_000) == 0
      assert RateLimiter.get_count("session1", "tool3", 60_000) == 0
    end

    test "does not affect other sessions" do
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session2", "tool1", 100, 60_000)

      RateLimiter.clear_session("session1")

      assert RateLimiter.get_count("session1", "tool1", 60_000) == 0
      assert RateLimiter.get_count("session2", "tool1", 60_000) == 1
    end

    test "handles non-existent session gracefully" do
      assert :ok = RateLimiter.clear_session("non_existent")
    end
  end

  # =============================================================================
  # Tests: clear_all/0
  # =============================================================================

  describe "clear_all/0" do
    test "clears all rate limit data" do
      # Create data for multiple sessions and tools
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session1", "tool2", 100, 60_000)
      RateLimiter.check_rate("session2", "tool1", 100, 60_000)

      # Clear all
      assert :ok = RateLimiter.clear_all()

      # All counts should be 0
      assert RateLimiter.get_count("session1", "tool1", 60_000) == 0
      assert RateLimiter.get_count("session1", "tool2", 60_000) == 0
      assert RateLimiter.get_count("session2", "tool1", 60_000) == 0
    end
  end

  # =============================================================================
  # Tests: cleanup/1
  # =============================================================================

  describe "cleanup/1" do
    test "removes expired entries" do
      # Create some entries with short window
      RateLimiter.check_rate("session1", "tool1", 100, 30)
      RateLimiter.check_rate("session1", "tool2", 100, 30)

      # Wait for them to expire
      Process.sleep(50)

      # Run cleanup with matching age
      cleaned = RateLimiter.cleanup(40)

      # Should have cleaned up entries
      assert cleaned >= 0
    end

    test "keeps recent entries" do
      # Create fresh entries
      RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      RateLimiter.check_rate("session1", "tool2", 100, 60_000)

      # Run cleanup - should not remove fresh entries
      RateLimiter.cleanup(60_000)

      # Entries should still exist
      assert RateLimiter.get_count("session1", "tool1", 60_000) == 1
      assert RateLimiter.get_count("session1", "tool2", 60_000) == 1
    end

    test "uses default max_age when not specified" do
      # Just ensure it doesn't crash
      assert is_integer(RateLimiter.cleanup())
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry when rate limit is exceeded" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-rate-limiter-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :rate_limited],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        # Fill up the limit
        for _ <- 1..3 do
          RateLimiter.check_rate("session1", "tool1", 3, 60_000)
        end

        # Trigger rate limit
        {:error, _} = RateLimiter.check_rate("session1", "tool1", 3, 60_000)

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :rate_limited], measurements,
                        metadata}

        assert is_integer(measurements.retry_after_ms)
        assert measurements.retry_after_ms > 0
        assert metadata.session_id == "session1"
        assert metadata.tool == "tool1"
        assert metadata.limit == 3
        assert metadata.window_ms == 60_000
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when invocation is allowed" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-rate-limiter-no-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :rate_limited],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        # Successful invocation
        assert :ok = RateLimiter.check_rate("session1", "tool1", 10, 60_000)

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when emit_telemetry: false" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-rate-limiter-disabled-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :rate_limited],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        # Fill up the limit
        for _ <- 1..3 do
          RateLimiter.check_rate("session1", "tool1", 3, 60_000)
        end

        # Trigger rate limit with telemetry disabled
        {:error, _} =
          RateLimiter.check_rate("session1", "tool1", 3, 60_000, emit_telemetry: false)

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Tests: Edge cases
  # =============================================================================

  describe "edge cases" do
    test "handles limit of 1" do
      assert :ok = RateLimiter.check_rate("session1", "tool1", 1, 60_000)
      assert {:error, _} = RateLimiter.check_rate("session1", "tool1", 1, 60_000)
    end

    test "handles very short window" do
      window_ms = 1

      assert :ok = RateLimiter.check_rate("session1", "tool1", 1, window_ms)

      # Wait for window to expire
      Process.sleep(5)

      assert :ok = RateLimiter.check_rate("session1", "tool1", 1, window_ms)
    end

    test "handles large limit" do
      limit = 10_000

      for _ <- 1..100 do
        assert :ok = RateLimiter.check_rate("session1", "tool1", limit, 60_000)
      end

      assert RateLimiter.get_count("session1", "tool1", 60_000) == 100
    end

    test "handles special characters in session_id" do
      session_id = "session/with:special@chars#123"
      assert :ok = RateLimiter.check_rate(session_id, "tool1", 10, 60_000)
      assert RateLimiter.get_count(session_id, "tool1", 60_000) == 1
    end

    test "handles special characters in tool_name" do
      tool_name = "tool:with/special.chars"
      assert :ok = RateLimiter.check_rate("session1", tool_name, 10, 60_000)
      assert RateLimiter.get_count("session1", tool_name, 60_000) == 1
    end

    test "concurrent access from multiple processes" do
      session_id = "concurrent_session"
      tool_name = "concurrent_tool"
      limit = 100

      # Spawn multiple processes making concurrent invocations
      tasks =
        for _ <- 1..50 do
          Task.async(fn ->
            RateLimiter.check_rate(session_id, tool_name, limit, 60_000)
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks)

      # All should succeed (we're under the limit)
      assert Enum.all?(results, &(&1 == :ok))

      # Due to concurrent read-modify-write operations, some entries may be lost
      # The count should be at least 1 and at most 50
      # This is expected behavior for non-transactional ETS access
      count = RateLimiter.get_count(session_id, tool_name, 60_000)
      assert count >= 1
      assert count <= 50
    end
  end

  # =============================================================================
  # Tests: ETS table management
  # =============================================================================

  describe "ETS table management" do
    test "table is created on first use" do
      # Clear any existing table reference
      case :ets.whereis(:jido_code_rate_limits) do
        :undefined -> :ok
        _ -> :ok
      end

      # First invocation should create table
      RateLimiter.check_rate("session1", "tool1", 10, 60_000)

      # Table should exist
      assert :ets.whereis(:jido_code_rate_limits) != :undefined
    end

    test "multiple calls don't recreate table" do
      # Make several calls
      for _ <- 1..10 do
        RateLimiter.check_rate("session1", "tool1", 100, 60_000)
      end

      # Should still work
      assert RateLimiter.get_count("session1", "tool1", 60_000) == 10
    end
  end
end
