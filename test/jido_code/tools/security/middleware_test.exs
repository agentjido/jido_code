defmodule JidoCode.Tools.Security.MiddlewareTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Security.{Middleware, RateLimiter}
  alias JidoCode.Tools.Behaviours.SecureHandler

  # =============================================================================
  # Test Fixtures - Sample handlers for testing
  # =============================================================================

  defmodule ReadOnlyHandler do
    @moduledoc false
    use SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :read_only,
        rate_limit: {5, 1000},
        requires_consent: false
      }
    end
  end

  defmodule WriteHandler do
    @moduledoc false
    use SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :write,
        rate_limit: {3, 1000}
      }
    end
  end

  defmodule PrivilegedHandler do
    @moduledoc false
    use SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :privileged,
        rate_limit: {2, 1000},
        requires_consent: true
      }
    end
  end

  # =============================================================================
  # Setup/Teardown
  # =============================================================================

  setup do
    # Clear rate limits before each test
    RateLimiter.clear_all()

    # Reset middleware config
    original = Application.get_env(:jido_code, :security_middleware)
    Application.put_env(:jido_code, :security_middleware, true)

    on_exit(fn ->
      if original do
        Application.put_env(:jido_code, :security_middleware, original)
      else
        Application.delete_env(:jido_code, :security_middleware)
      end

      RateLimiter.clear_all()
    end)

    :ok
  end

  # =============================================================================
  # Tests: enabled?/0
  # =============================================================================

  describe "enabled?/0" do
    test "returns true when security_middleware is enabled" do
      Application.put_env(:jido_code, :security_middleware, true)
      assert Middleware.enabled?()
    end

    test "returns false when security_middleware is disabled" do
      Application.put_env(:jido_code, :security_middleware, false)
      refute Middleware.enabled?()
    end

    test "returns false when security_middleware is not set" do
      Application.delete_env(:jido_code, :security_middleware)
      refute Middleware.enabled?()
    end
  end

  # =============================================================================
  # Tests: run_checks/3
  # =============================================================================

  describe "run_checks/3" do
    test "returns :ok when all checks pass" do
      tool = %{name: "test_tool", handler: ReadOnlyHandler}
      context = %{session_id: "sess_123", granted_tier: :read_only}

      assert :ok = Middleware.run_checks(tool, %{}, context)
    end

    test "returns :ok for read_only tool with write tier" do
      tool = %{name: "test_tool", handler: ReadOnlyHandler}
      context = %{session_id: "sess_123", granted_tier: :write}

      assert :ok = Middleware.run_checks(tool, %{}, context)
    end

    test "returns :ok for privileged tool with consent" do
      tool = %{name: "test_tool", handler: PrivilegedHandler}
      context = %{session_id: "sess_123", granted_tier: :privileged, consented_tools: ["test_tool"]}

      assert :ok = Middleware.run_checks(tool, %{}, context)
    end

    test "returns rate_limited error when limit exceeded" do
      tool = %{name: "test_tool", handler: ReadOnlyHandler}
      context = %{session_id: "sess_rate_test", granted_tier: :read_only}

      # Exhaust rate limit (5 calls allowed)
      for _ <- 1..5 do
        assert :ok = Middleware.run_checks(tool, %{}, context)
      end

      # Next call should be rate limited
      assert {:error, {:rate_limited, details}} = Middleware.run_checks(tool, %{}, context)
      assert details.tool == "test_tool"
      assert details.limit == 5
      assert details.window_ms == 1000
      assert is_integer(details.retry_after_ms)
    end

    test "returns permission_denied when tier insufficient" do
      tool = %{name: "test_tool", handler: WriteHandler}
      context = %{session_id: "sess_123", granted_tier: :read_only}

      assert {:error, {:permission_denied, details}} = Middleware.run_checks(tool, %{}, context)
      assert details.tool == "test_tool"
      assert details.required_tier == :write
      assert details.granted_tier == :read_only
    end

    test "returns consent_required when consent not given" do
      tool = %{name: "test_tool", handler: PrivilegedHandler}
      context = %{session_id: "sess_123", granted_tier: :privileged, consented_tools: []}

      assert {:error, {:consent_required, details}} = Middleware.run_checks(tool, %{}, context)
      assert details.tool == "test_tool"
      assert details.tier == :privileged
    end
  end

  # =============================================================================
  # Tests: check_rate_limit/2
  # =============================================================================

  describe "check_rate_limit/2" do
    test "returns :ok when under limit" do
      tool = %{name: "rate_tool", handler: ReadOnlyHandler}
      context = %{session_id: "sess_rate_1"}

      assert :ok = Middleware.check_rate_limit(tool, context)
    end

    test "returns :ok when no session_id (no rate limiting)" do
      tool = %{name: "rate_tool", handler: ReadOnlyHandler}
      context = %{}

      # Should never rate limit without session
      for _ <- 1..10 do
        assert :ok = Middleware.check_rate_limit(tool, context)
      end
    end

    test "returns error with retry_after when limit exceeded" do
      tool = %{name: "rate_tool_2", handler: ReadOnlyHandler}
      context = %{session_id: "sess_rate_2"}

      # Exhaust rate limit
      for _ <- 1..5 do
        assert :ok = Middleware.check_rate_limit(tool, context)
      end

      assert {:error, {:rate_limited, details}} = Middleware.check_rate_limit(tool, context)
      assert details.retry_after_ms > 0
    end

    test "uses handler's rate limit when available" do
      tool = %{name: "write_tool", handler: WriteHandler}
      context = %{session_id: "sess_rate_3"}

      # WriteHandler has limit of 3
      for _ <- 1..3 do
        assert :ok = Middleware.check_rate_limit(tool, context)
      end

      assert {:error, {:rate_limited, details}} = Middleware.check_rate_limit(tool, context)
      assert details.limit == 3
    end

    test "uses default rate limit for tools without handler" do
      tool = %{name: "read_file"}
      context = %{session_id: "sess_rate_4"}

      # Default for read_only is 100
      assert :ok = Middleware.check_rate_limit(tool, context)
    end

    test "rate limits are per-session" do
      tool = %{name: "rate_tool_3", handler: ReadOnlyHandler}

      # Session 1 exhausts limit
      context1 = %{session_id: "sess_a"}

      for _ <- 1..5 do
        assert :ok = Middleware.check_rate_limit(tool, context1)
      end

      assert {:error, _} = Middleware.check_rate_limit(tool, context1)

      # Session 2 should still work
      context2 = %{session_id: "sess_b"}
      assert :ok = Middleware.check_rate_limit(tool, context2)
    end

    test "rate limits are per-tool" do
      context = %{session_id: "sess_rate_5"}

      tool1 = %{name: "tool_a", handler: ReadOnlyHandler}
      tool2 = %{name: "tool_b", handler: ReadOnlyHandler}

      # Exhaust limit for tool1
      for _ <- 1..5 do
        assert :ok = Middleware.check_rate_limit(tool1, context)
      end

      assert {:error, _} = Middleware.check_rate_limit(tool1, context)

      # tool2 should still work
      assert :ok = Middleware.check_rate_limit(tool2, context)
    end
  end

  # =============================================================================
  # Tests: check_permission_tier/2
  # =============================================================================

  describe "check_permission_tier/2" do
    test "returns :ok when granted tier >= required tier" do
      tool = %{name: "test", handler: ReadOnlyHandler}

      assert :ok = Middleware.check_permission_tier(tool, %{granted_tier: :read_only})
      assert :ok = Middleware.check_permission_tier(tool, %{granted_tier: :write})
      assert :ok = Middleware.check_permission_tier(tool, %{granted_tier: :execute})
      assert :ok = Middleware.check_permission_tier(tool, %{granted_tier: :privileged})
    end

    test "returns error when granted tier < required tier" do
      tool = %{name: "test", handler: WriteHandler}

      assert {:error, {:permission_denied, details}} =
               Middleware.check_permission_tier(tool, %{granted_tier: :read_only})

      assert details.required_tier == :write
      assert details.granted_tier == :read_only
    end

    test "defaults to :read_only when no granted_tier in context" do
      tool = %{name: "test", handler: ReadOnlyHandler}
      assert :ok = Middleware.check_permission_tier(tool, %{})

      tool2 = %{name: "test2", handler: WriteHandler}

      assert {:error, _} = Middleware.check_permission_tier(tool2, %{})
    end

    test "uses Permissions.get_tool_tier for tools without handler" do
      # read_file is mapped to :read_only in Permissions
      tool = %{name: "read_file"}
      assert :ok = Middleware.check_permission_tier(tool, %{granted_tier: :read_only})

      # run_command is mapped to :execute
      tool2 = %{name: "run_command"}

      assert {:error, {:permission_denied, details}} =
               Middleware.check_permission_tier(tool2, %{granted_tier: :read_only})

      assert details.required_tier == :execute
    end
  end

  # =============================================================================
  # Tests: check_consent_requirement/2
  # =============================================================================

  describe "check_consent_requirement/2" do
    test "returns :ok when consent not required" do
      tool = %{name: "test", handler: ReadOnlyHandler}
      assert :ok = Middleware.check_consent_requirement(tool, %{})
    end

    test "returns :ok when consent required and given" do
      tool = %{name: "priv_tool", handler: PrivilegedHandler}
      context = %{consented_tools: ["priv_tool"]}

      assert :ok = Middleware.check_consent_requirement(tool, context)
    end

    test "returns error when consent required but not given" do
      tool = %{name: "priv_tool", handler: PrivilegedHandler}
      context = %{consented_tools: []}

      assert {:error, {:consent_required, details}} =
               Middleware.check_consent_requirement(tool, context)

      assert details.tool == "priv_tool"
      assert details.tier == :privileged
    end

    test "returns error when consented_tools not in context" do
      tool = %{name: "priv_tool", handler: PrivilegedHandler}

      assert {:error, {:consent_required, _}} =
               Middleware.check_consent_requirement(tool, %{})
    end

    test "tools without handler don't require consent" do
      tool = %{name: "unknown_tool"}
      assert :ok = Middleware.check_consent_requirement(tool, %{})
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry on successful check" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-middleware-telemetry-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :middleware_check],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        tool = %{name: "telemetry_tool", handler: ReadOnlyHandler}
        context = %{session_id: "sess_telem", granted_tier: :read_only}

        assert :ok = Middleware.run_checks(tool, %{}, context)

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :middleware_check], measurements,
                        metadata}

        assert is_integer(measurements.duration)
        assert measurements.duration >= 0
        assert metadata.tool == "telemetry_tool"
        assert metadata.session_id == "sess_telem"
        assert metadata.result == :allowed
        assert metadata.reason == nil
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits telemetry on blocked check with reason" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-middleware-blocked-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :middleware_check],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        tool = %{name: "blocked_tool", handler: WriteHandler}
        context = %{session_id: "sess_blocked", granted_tier: :read_only}

        assert {:error, _} = Middleware.run_checks(tool, %{}, context)

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :middleware_check], _,
                        metadata}

        assert metadata.result == :blocked
        assert metadata.reason == :permission_denied
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits telemetry with rate_limited reason" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-middleware-rate-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :middleware_check],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, metadata})
        end,
        nil
      )

      try do
        tool = %{name: "rate_telem_tool", handler: ReadOnlyHandler}
        context = %{session_id: "sess_rate_telem", granted_tier: :read_only}

        # Exhaust rate limit
        for _ <- 1..5 do
          Middleware.run_checks(tool, %{}, context)
        end

        # Clear received messages
        flush_mailbox()

        # This should be rate limited
        assert {:error, {:rate_limited, _}} = Middleware.run_checks(tool, %{}, context)

        assert_receive {:telemetry, ^ref, metadata}
        assert metadata.result == :blocked
        assert metadata.reason == :rate_limited
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  defp flush_mailbox do
    receive do
      _ -> flush_mailbox()
    after
      0 -> :ok
    end
  end
end
