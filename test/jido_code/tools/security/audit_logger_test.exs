defmodule JidoCode.Tools.Security.AuditLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias JidoCode.Tools.Security.AuditLogger

  # =============================================================================
  # Setup
  # =============================================================================

  setup do
    # Clear audit log before each test
    AuditLogger.clear_all()
    :ok
  end

  # =============================================================================
  # Tests: log_invocation/5
  # =============================================================================

  describe "log_invocation/5" do
    test "logs a successful invocation" do
      entry_id = AuditLogger.log_invocation("session1", "read_file", :ok, 1500)

      assert is_integer(entry_id)
      assert entry_id > 0
    end

    test "logs an error invocation" do
      entry_id = AuditLogger.log_invocation("session1", "write_file", :error, 500)

      assert is_integer(entry_id)
      log = AuditLogger.get_audit_log("session1")
      assert length(log) == 1
      assert hd(log).status == :error
    end

    test "logs a blocked invocation" do
      entry_id = AuditLogger.log_invocation("session1", "run_command", :blocked, 0)

      assert is_integer(entry_id)
      log = AuditLogger.get_audit_log("session1")
      assert length(log) == 1
      assert hd(log).status == :blocked
    end

    test "stores correct entry structure" do
      AuditLogger.log_invocation("session1", "read_file", :ok, 1500,
        args: %{"path" => "/tmp/test.txt"}
      )

      [entry] = AuditLogger.get_audit_log("session1")

      assert Map.has_key?(entry, :id)
      assert Map.has_key?(entry, :timestamp)
      assert Map.has_key?(entry, :session_id)
      assert Map.has_key?(entry, :tool)
      assert Map.has_key?(entry, :status)
      assert Map.has_key?(entry, :duration_us)
      assert Map.has_key?(entry, :args_hash)

      assert entry.session_id == "session1"
      assert entry.tool == "read_file"
      assert entry.status == :ok
      assert entry.duration_us == 1500
      assert is_binary(entry.args_hash)
      assert %DateTime{} = entry.timestamp
    end

    test "returns incrementing entry IDs" do
      id1 = AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      id2 = AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      id3 = AuditLogger.log_invocation("session1", "tool3", :ok, 100)

      assert id2 == id1 + 1
      assert id3 == id2 + 1
    end

    test "hashes arguments for privacy" do
      AuditLogger.log_invocation("session1", "read_file", :ok, 100,
        args: %{"path" => "/secret/file.txt", "password" => "hunter2"}
      )

      [entry] = AuditLogger.get_audit_log("session1")

      # Args hash should be present
      assert is_binary(entry.args_hash)
      # Should be a 16-character hex string (truncated SHA256)
      assert String.length(entry.args_hash) == 32
      assert Regex.match?(~r/^[0-9a-f]{32}$/, entry.args_hash)
    end

    test "handles nil args" do
      AuditLogger.log_invocation("session1", "read_file", :ok, 100)

      [entry] = AuditLogger.get_audit_log("session1")
      assert entry.args_hash == nil
    end

    test "logs multiple invocations for same session" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 200)
      AuditLogger.log_invocation("session1", "tool3", :error, 300)

      log = AuditLogger.get_audit_log("session1")
      assert length(log) == 3
    end

    test "logs invocations for different sessions" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session2", "tool1", :ok, 100)
      AuditLogger.log_invocation("session3", "tool1", :ok, 100)

      assert length(AuditLogger.get_audit_log("session1")) == 1
      assert length(AuditLogger.get_audit_log("session2")) == 1
      assert length(AuditLogger.get_audit_log("session3")) == 1
      assert length(AuditLogger.get_audit_log()) == 3
    end
  end

  # =============================================================================
  # Tests: Ring buffer behavior
  # =============================================================================

  describe "ring buffer behavior" do
    test "removes oldest entries when buffer is full" do
      # Use a small buffer for testing
      original_size = Application.get_env(:jido_code, :audit_buffer_size)
      Application.put_env(:jido_code, :audit_buffer_size, 5)

      try do
        # Clear and reset
        AuditLogger.clear_all()

        # Fill the buffer
        for i <- 1..5 do
          AuditLogger.log_invocation("session1", "tool#{i}", :ok, 100)
        end

        assert AuditLogger.count() == 5

        # Add one more - should evict oldest
        AuditLogger.log_invocation("session1", "tool6", :ok, 100)

        # Still at max size
        assert AuditLogger.count() == 5

        # Oldest entry (tool1) should be gone
        log = AuditLogger.get_audit_log()
        tools = Enum.map(log, & &1.tool)
        refute "tool1" in tools
        assert "tool6" in tools
      after
        if original_size do
          Application.put_env(:jido_code, :audit_buffer_size, original_size)
        else
          Application.delete_env(:jido_code, :audit_buffer_size)
        end
      end
    end

    test "buffer_size returns configured or default value" do
      original_size = Application.get_env(:jido_code, :audit_buffer_size)

      try do
        Application.delete_env(:jido_code, :audit_buffer_size)
        assert AuditLogger.buffer_size() == 10_000

        Application.put_env(:jido_code, :audit_buffer_size, 5000)
        assert AuditLogger.buffer_size() == 5000
      after
        if original_size do
          Application.put_env(:jido_code, :audit_buffer_size, original_size)
        else
          Application.delete_env(:jido_code, :audit_buffer_size)
        end
      end
    end
  end

  # =============================================================================
  # Tests: get_audit_log/1 and get_audit_log/2
  # =============================================================================

  describe "get_audit_log/1" do
    test "returns all entries when no session specified" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session2", "tool2", :ok, 100)
      AuditLogger.log_invocation("session3", "tool3", :ok, 100)

      log = AuditLogger.get_audit_log()
      assert length(log) == 3
    end

    test "filters by session when session_id provided" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      AuditLogger.log_invocation("session2", "tool3", :ok, 100)

      log = AuditLogger.get_audit_log("session1")
      assert length(log) == 2
      assert Enum.all?(log, &(&1.session_id == "session1"))
    end

    test "returns empty list for unknown session" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)

      log = AuditLogger.get_audit_log("unknown_session")
      assert log == []
    end

    test "accepts options when called with keyword list" do
      for i <- 1..10 do
        AuditLogger.log_invocation("session1", "tool#{i}", :ok, 100)
      end

      log = AuditLogger.get_audit_log(limit: 5)
      assert length(log) == 5
    end

    test "respects limit option" do
      for i <- 1..20 do
        AuditLogger.log_invocation("session1", "tool#{i}", :ok, 100)
      end

      log = AuditLogger.get_audit_log("session1", limit: 5)
      assert length(log) == 5
    end

    test "returns entries in descending order by default" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      Process.sleep(1)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      Process.sleep(1)
      AuditLogger.log_invocation("session1", "tool3", :ok, 100)

      log = AuditLogger.get_audit_log("session1")
      ids = Enum.map(log, & &1.id)
      assert ids == Enum.sort(ids, :desc)
    end

    test "respects order: :asc option" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      AuditLogger.log_invocation("session1", "tool3", :ok, 100)

      log = AuditLogger.get_audit_log("session1", order: :asc)
      ids = Enum.map(log, & &1.id)
      assert ids == Enum.sort(ids, :asc)
    end
  end

  # =============================================================================
  # Tests: clear_all/0
  # =============================================================================

  describe "clear_all/0" do
    test "removes all entries" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session2", "tool2", :ok, 100)

      assert AuditLogger.count() == 2

      AuditLogger.clear_all()

      assert AuditLogger.count() == 0
      assert AuditLogger.get_audit_log() == []
    end

    test "resets entry counter" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)

      AuditLogger.clear_all()

      # New entries should start from 1 again
      id = AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      assert id == 1
    end
  end

  # =============================================================================
  # Tests: clear_session/1
  # =============================================================================

  describe "clear_session/1" do
    test "removes entries for specified session only" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      AuditLogger.log_invocation("session2", "tool3", :ok, 100)

      AuditLogger.clear_session("session1")

      assert AuditLogger.get_audit_log("session1") == []
      assert length(AuditLogger.get_audit_log("session2")) == 1
    end

    test "handles non-existent session gracefully" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)

      assert :ok = AuditLogger.clear_session("non_existent")
      assert length(AuditLogger.get_audit_log("session1")) == 1
    end
  end

  # =============================================================================
  # Tests: count/0
  # =============================================================================

  describe "count/0" do
    test "returns 0 for empty log" do
      assert AuditLogger.count() == 0
    end

    test "returns correct count after logging" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)
      AuditLogger.log_invocation("session1", "tool2", :ok, 100)
      AuditLogger.log_invocation("session2", "tool3", :ok, 100)

      assert AuditLogger.count() == 3
    end
  end

  # =============================================================================
  # Tests: hash_args/1
  # =============================================================================

  describe "hash_args/1" do
    test "returns nil for nil args" do
      assert AuditLogger.hash_args(nil) == nil
    end

    test "returns 32-character hex string for map args" do
      hash = AuditLogger.hash_args(%{"key" => "value"})

      assert is_binary(hash)
      assert String.length(hash) == 32
      assert Regex.match?(~r/^[0-9a-f]{32}$/, hash)
    end

    test "returns consistent hash for same args" do
      args = %{"path" => "/tmp/test.txt", "content" => "hello"}

      hash1 = AuditLogger.hash_args(args)
      hash2 = AuditLogger.hash_args(args)

      assert hash1 == hash2
    end

    test "returns different hash for different args" do
      hash1 = AuditLogger.hash_args(%{"key" => "value1"})
      hash2 = AuditLogger.hash_args(%{"key" => "value2"})

      assert hash1 != hash2
    end

    test "handles complex nested args" do
      args = %{
        "nested" => %{"deep" => %{"value" => 123}},
        "list" => [1, 2, 3],
        "mixed" => [%{"a" => 1}, %{"b" => 2}]
      }

      hash = AuditLogger.hash_args(args)
      assert is_binary(hash)
      assert String.length(hash) == 32
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry on log_invocation" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-audit-logger-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :audit],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        AuditLogger.log_invocation("session1", "read_file", :ok, 1500)

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :audit], measurements, metadata}

        assert measurements.duration_us == 1500
        assert metadata.session_id == "session1"
        assert metadata.tool == "read_file"
        assert metadata.status == :ok
        assert is_integer(metadata.entry_id)
      after
        :telemetry.detach(handler_id)
      end
    end

    test "does not emit telemetry when emit_telemetry: false" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-audit-logger-no-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :audit],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        AuditLogger.log_invocation("session1", "read_file", :ok, 1500, emit_telemetry: false)

        refute_receive {:telemetry, ^ref, _, _, _}, 100
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Tests: Logger integration for blocked invocations
  # =============================================================================

  describe "Logger integration" do
    test "logs warning for blocked invocations" do
      log =
        capture_log(fn ->
          AuditLogger.log_invocation("session1", "run_command", :blocked, 0,
            args: %{"command" => "rm -rf /"}
          )
        end)

      assert log =~ "[AuditLogger] Blocked invocation"
      assert log =~ "session1"
      assert log =~ "run_command"
    end

    test "does not log for successful invocations" do
      log =
        capture_log(fn ->
          AuditLogger.log_invocation("session1", "read_file", :ok, 100)
        end)

      refute log =~ "[AuditLogger]"
    end

    test "does not log for error invocations" do
      log =
        capture_log(fn ->
          AuditLogger.log_invocation("session1", "read_file", :error, 100)
        end)

      refute log =~ "[AuditLogger]"
    end

    test "respects log_blocked: false option" do
      log =
        capture_log(fn ->
          AuditLogger.log_invocation("session1", "run_command", :blocked, 0, log_blocked: false)
        end)

      refute log =~ "[AuditLogger]"
    end
  end

  # =============================================================================
  # Tests: Edge cases
  # =============================================================================

  describe "edge cases" do
    test "handles special characters in session_id" do
      session_id = "session/with:special@chars#123"
      AuditLogger.log_invocation(session_id, "tool1", :ok, 100)

      log = AuditLogger.get_audit_log(session_id)
      assert length(log) == 1
      assert hd(log).session_id == session_id
    end

    test "handles special characters in tool name" do
      tool_name = "tool:with/special.chars"
      AuditLogger.log_invocation("session1", tool_name, :ok, 100)

      log = AuditLogger.get_audit_log("session1")
      assert length(log) == 1
      assert hd(log).tool == tool_name
    end

    test "handles zero duration" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 0)

      [entry] = AuditLogger.get_audit_log("session1")
      assert entry.duration_us == 0
    end

    test "handles very large duration" do
      large_duration = 1_000_000_000
      AuditLogger.log_invocation("session1", "tool1", :ok, large_duration)

      [entry] = AuditLogger.get_audit_log("session1")
      assert entry.duration_us == large_duration
    end

    test "handles empty args map" do
      AuditLogger.log_invocation("session1", "tool1", :ok, 100, args: %{})

      [entry] = AuditLogger.get_audit_log("session1")
      assert is_binary(entry.args_hash)
    end

    test "concurrent logging from multiple processes" do
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            AuditLogger.log_invocation("session#{rem(i, 5)}", "tool#{i}", :ok, 100)
          end)
        end

      Task.await_many(tasks)

      assert AuditLogger.count() == 50
    end
  end

  # =============================================================================
  # Tests: ETS table management
  # =============================================================================

  describe "ETS table management" do
    test "table is created on first use" do
      # Clear and verify table is recreated
      AuditLogger.clear_all()
      AuditLogger.log_invocation("session1", "tool1", :ok, 100)

      assert :ets.whereis(:jido_code_audit_log) != :undefined
    end

    test "multiple operations don't recreate table" do
      for i <- 1..10 do
        AuditLogger.log_invocation("session1", "tool#{i}", :ok, 100)
      end

      AuditLogger.get_audit_log()
      AuditLogger.count()

      assert AuditLogger.count() == 10
    end
  end
end
