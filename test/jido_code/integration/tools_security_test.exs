defmodule JidoCode.Integration.ToolsSecurityTest do
  @moduledoc """
  Integration tests for Section 5.8 Handler Security Infrastructure.

  These tests verify that security components work correctly together:
  - Middleware integration with Executor
  - Rate limiting blocks rapid calls
  - Output sanitization removes secrets
  - Permission tier enforcement
  - Audit logging captures blocked invocations

  ## Test Coverage

  - 5.8.9.2: Executor applies middleware when enabled
  - 5.8.9.3: Rate limiting blocks rapid calls
  - 5.8.9.4: Output sanitization removes secrets
  - 5.8.9.5: Process isolation (tested separately via IsolatedExecutor unit tests)
  - 5.8.9.6: Permission tier blocks privileged tools
  - 5.8.9.7: Audit log captures blocked invocations

  ## Why async: false

  These tests cannot run async because they:
  1. Modify application environment (security_middleware config)
  2. Use shared ETS tables for rate limiting and audit logging
  3. Require deterministic cleanup between test runs
  """
  use ExUnit.Case, async: false

  alias JidoCode.Session
  alias JidoCode.SessionRegistry
  alias JidoCode.SessionSupervisor
  alias JidoCode.Test.SessionTestHelpers
  alias JidoCode.Tools.Definitions.FileSystem, as: FSDefs
  alias JidoCode.Tools.Executor
  alias JidoCode.Tools.Registry, as: ToolsRegistry
  alias JidoCode.Tools.Security.{AuditLogger, Middleware, RateLimiter}

  @moduletag :integration
  @moduletag :security
  @moduletag :phase5

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Process.flag(:trap_exit, true)

    # Ensure the application is started
    {:ok, _} = Application.ensure_all_started(:jido_code)

    # Suppress deprecation warnings for tests
    Application.put_env(:jido_code, :suppress_global_manager_warnings, true)

    # Store original security middleware setting
    original_middleware = Application.get_env(:jido_code, :security_middleware)

    # Wait for SessionSupervisor to be available
    wait_for_supervisor()

    # Clear any existing test sessions from Registry
    SessionRegistry.clear()

    # Stop any running sessions under SessionSupervisor
    for {_id, pid, _type, _modules} <- DynamicSupervisor.which_children(SessionSupervisor) do
      DynamicSupervisor.terminate_child(SessionSupervisor, pid)
    end

    # Clear security state
    RateLimiter.clear_all()
    AuditLogger.clear_all()

    # Create temp base directory for test sessions
    tmp_base = Path.join(System.tmp_dir!(), "security_integration_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_base)

    # Register tools for testing
    register_test_tools()

    on_exit(fn ->
      # Restore original security middleware setting
      if original_middleware do
        Application.put_env(:jido_code, :security_middleware, original_middleware)
      else
        Application.delete_env(:jido_code, :security_middleware)
      end

      # Restore deprecation warnings
      Application.delete_env(:jido_code, :suppress_global_manager_warnings)

      # Stop all test sessions
      if Process.whereis(SessionSupervisor) do
        for session <- SessionRegistry.list_all() do
          SessionSupervisor.stop_session(session.id)
        end
      end

      SessionRegistry.clear()
      RateLimiter.clear_all()
      AuditLogger.clear_all()
      File.rm_rf!(tmp_base)
    end)

    {:ok, tmp_base: tmp_base, original_middleware: original_middleware}
  end

  defp wait_for_supervisor(retries \\ 50) do
    if Process.whereis(SessionSupervisor) do
      :ok
    else
      if retries > 0 do
        Process.sleep(10)
        wait_for_supervisor(retries - 1)
      else
        raise "SessionSupervisor not available after waiting"
      end
    end
  end

  defp register_test_tools do
    # Register filesystem tools for testing
    ToolsRegistry.register(FSDefs.read_file())
    ToolsRegistry.register(FSDefs.write_file())
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp create_test_dir(base, name) do
    path = Path.join(base, name)
    File.mkdir_p!(path)
    path
  end

  defp create_session(project_path) do
    config = SessionTestHelpers.valid_session_config()
    {:ok, session} = Session.new(project_path: project_path, config: config)
    {:ok, _pid} = SessionSupervisor.start_session(session)
    session
  end

  defp tool_call(name, args) do
    %{
      id: "tc-#{:rand.uniform(100_000)}",
      name: name,
      arguments: args
    }
  end

  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :ok, content: content}}),
    do: {:ok, content}

  defp unwrap_result({:ok, %JidoCode.Tools.Result{status: :error, content: content}}),
    do: {:error, content}

  defp unwrap_result({:error, reason}),
    do: {:error, reason}

  defp enable_security_middleware do
    Application.put_env(:jido_code, :security_middleware, true)
  end

  defp disable_security_middleware do
    Application.put_env(:jido_code, :security_middleware, false)
  end

  # ============================================================================
  # Section 5.8.9.2: Middleware Integration Tests
  # ============================================================================

  describe "Executor applies middleware when enabled" do
    test "middleware is bypassed when disabled", %{tmp_base: tmp_base} do
      disable_security_middleware()

      project_dir = create_test_dir(tmp_base, "middleware_disabled_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Should succeed without middleware checks
      call = tool_call("read_file", %{"path" => "test.txt"})
      result = Executor.execute(call, context: context)

      assert {:ok, _content} = unwrap_result(result)

      # No audit entries since middleware is disabled
      # (Audit logging is part of the security middleware)
    end

    test "middleware is applied when enabled", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "middleware_enabled_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Should succeed with middleware checks passing
      call = tool_call("read_file", %{"path" => "test.txt"})
      result = Executor.execute(call, context: context)

      assert {:ok, _content} = unwrap_result(result)
    end
  end

  # ============================================================================
  # Section 5.8.9.3: Rate Limiting Tests
  # ============================================================================

  describe "Rate limiting blocks rapid calls" do
    test "allows calls within rate limit", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "rate_limit_allow_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # read_file is :read_only tier with limit of 100 per minute
      # Making a few calls should succeed
      for _ <- 1..5 do
        call = tool_call("read_file", %{"path" => "test.txt"})
        result = Executor.execute(call, context: context)
        assert {:ok, _} = unwrap_result(result)
      end
    end

    test "blocks calls exceeding rate limit", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "rate_limit_block_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Simulate hitting rate limit by pre-filling the rate limiter
      # Default :read_only limit is 100 per 60 seconds
      for _ <- 1..100 do
        RateLimiter.check_rate(session.id, "read_file", 100, 60_000)
      end

      # Next call should be rate limited
      call = tool_call("read_file", %{"path" => "test.txt"})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "Rate limit" or error_msg =~ "rate limited"
    end
  end

  # ============================================================================
  # Section 5.8.9.4: Output Sanitization Tests
  # ============================================================================

  describe "Output sanitization removes secrets" do
    test "sanitizes API keys in file content", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "sanitize_api_key_test")

      # Create a file with a secret
      File.write!(Path.join(project_dir, "config.txt"), """
      # Configuration
      OPENAI_API_KEY=sk-1234567890abcdef1234567890abcdef1234567890abcdef
      OTHER_VALUE=safe
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("read_file", %{"path" => "config.txt"})
      result = Executor.execute(call, context: context)

      {:ok, content} = unwrap_result(result)

      # The API key should be redacted
      assert content =~ "[REDACTED"
      # But safe values should remain
      assert content =~ "OTHER_VALUE=safe"
    end

    test "sanitizes bearer tokens in file content", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "sanitize_bearer_test")

      File.write!(Path.join(project_dir, "auth.txt"), """
      Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("read_file", %{"path" => "auth.txt"})
      result = Executor.execute(call, context: context)

      {:ok, content} = unwrap_result(result)

      # Bearer token or JWT should be redacted
      assert content =~ "[REDACTED" or not (content =~ "eyJ")
    end

    test "sanitizes password assignments in file content", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "sanitize_password_test")

      File.write!(Path.join(project_dir, "secrets.txt"), """
      database_password=super_secret_123
      username=admin
      """)

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      call = tool_call("read_file", %{"path" => "secrets.txt"})
      result = Executor.execute(call, context: context)

      {:ok, content} = unwrap_result(result)

      # Password should be redacted
      assert content =~ "[REDACTED]"
      # Username should remain
      assert content =~ "username=admin"
    end
  end

  # ============================================================================
  # Section 5.8.9.6: Permission Tier Tests
  # ============================================================================

  describe "Permission tier blocks privileged tools" do
    test "allows read_only tools with read_only tier", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "tier_read_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      # Build context with read_only tier
      {:ok, base_context} = Executor.build_context(session.id)
      context = Map.put(base_context, :granted_tier, :read_only)

      call = tool_call("read_file", %{"path" => "test.txt"})
      result = Executor.execute(call, context: context)

      assert {:ok, _content} = unwrap_result(result)
    end

    test "blocks write tools with read_only tier", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "tier_block_test")

      session = create_session(project_dir)
      # Build context with read_only tier
      {:ok, base_context} = Executor.build_context(session.id)
      context = Map.put(base_context, :granted_tier, :read_only)

      call = tool_call("write_file", %{"path" => "new.txt", "content" => "test"})
      result = Executor.execute(call, context: context)

      {:error, error_msg} = unwrap_result(result)
      assert error_msg =~ "permission" or error_msg =~ "Permission denied"
    end

    test "allows write tools with write tier", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "tier_write_test")

      session = create_session(project_dir)
      # Build context with write tier
      {:ok, base_context} = Executor.build_context(session.id)
      context = Map.put(base_context, :granted_tier, :write)

      call = tool_call("write_file", %{"path" => "new.txt", "content" => "test"})
      result = Executor.execute(call, context: context)

      assert {:ok, _content} = unwrap_result(result)
    end
  end

  # ============================================================================
  # Section 5.8.9.7: Audit Logging Tests
  # ============================================================================

  describe "Audit log captures blocked invocations" do
    test "logs blocked rate-limited invocations", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "audit_rate_limit_test")
      File.write!(Path.join(project_dir, "test.txt"), "content")

      session = create_session(project_dir)
      {:ok, context} = Executor.build_context(session.id)

      # Pre-fill rate limiter to cause blocking
      for _ <- 1..100 do
        RateLimiter.check_rate(session.id, "read_file", 100, 60_000)
      end

      # This should be blocked and logged
      call = tool_call("read_file", %{"path" => "test.txt"})
      _result = Executor.execute(call, context: context)

      # Check audit log for blocked entry
      audit_log = AuditLogger.get_audit_log(session.id)

      # Should have at least one blocked entry
      blocked_entries = Enum.filter(audit_log, &(&1.status == :blocked))
      assert length(blocked_entries) >= 1

      blocked_entry = hd(blocked_entries)
      assert blocked_entry.tool == "read_file"
      assert blocked_entry.session_id == session.id
    end

    test "logs blocked permission-denied invocations", %{tmp_base: tmp_base} do
      enable_security_middleware()

      project_dir = create_test_dir(tmp_base, "audit_permission_test")

      session = create_session(project_dir)
      {:ok, base_context} = Executor.build_context(session.id)
      context = Map.put(base_context, :granted_tier, :read_only)

      # This should be blocked due to insufficient permissions
      call = tool_call("write_file", %{"path" => "new.txt", "content" => "test"})
      _result = Executor.execute(call, context: context)

      # Check audit log for blocked entry
      audit_log = AuditLogger.get_audit_log(session.id)

      blocked_entries = Enum.filter(audit_log, &(&1.status == :blocked))
      assert length(blocked_entries) >= 1

      blocked_entry = hd(blocked_entries)
      assert blocked_entry.tool == "write_file"
    end
  end

  # ============================================================================
  # Global Session Rate Limiting
  # ============================================================================

  describe "Global rate limiting for missing session" do
    test "uses global session ID when session_id is nil" do
      enable_security_middleware()

      # Test with a mock tool and context without session_id
      tool = %{name: "read_file"}
      context = %{}

      # Should not crash and should use __global__ session
      result = Middleware.check_rate_limit(tool, context)
      assert result == :ok

      # Verify it's tracking under __global__
      count = RateLimiter.get_count("__global__", "read_file", 60_000)
      assert count == 1
    end
  end
end
