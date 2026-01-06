defmodule JidoCode.Tools.Behaviours.SecureHandlerTest do
  use ExUnit.Case, async: true

  alias JidoCode.Tools.Behaviours.SecureHandler

  # =============================================================================
  # Test Fixtures - Sample handlers for testing
  # =============================================================================

  defmodule ReadOnlyHandler do
    @moduledoc false
    use JidoCode.Tools.Behaviours.SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :read_only,
        rate_limit: {100, 60_000},
        timeout_ms: 5000,
        requires_consent: false
      }
    end

    def execute(_args, _context), do: {:ok, "result"}
  end

  defmodule WriteHandler do
    @moduledoc false
    use JidoCode.Tools.Behaviours.SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :write,
        rate_limit: {30, 60_000}
      }
    end

    @impl true
    def validate_security(%{"path" => path}, _context) do
      if String.contains?(path, "..") do
        {:error, "path traversal not allowed"}
      else
        :ok
      end
    end

    def execute(_args, _context), do: {:ok, "written"}
  end

  defmodule ExecuteHandler do
    @moduledoc false
    use JidoCode.Tools.Behaviours.SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :execute,
        timeout_ms: 30_000,
        requires_consent: true
      }
    end

    @impl true
    def sanitize_output(result) when is_binary(result) do
      # Redact API keys from output
      result
      |> String.replace(~r/sk-[a-zA-Z0-9]{48,}/, "[REDACTED_API_KEY]")
      |> String.replace(~r/password\s*[:=]\s*\S+/i, "password: [REDACTED]")
    end

    def sanitize_output(result), do: result

    def execute(_args, _context), do: {:ok, "executed"}
  end

  defmodule PrivilegedHandler do
    @moduledoc false
    use JidoCode.Tools.Behaviours.SecureHandler

    @impl true
    def security_properties do
      %{
        tier: :privileged,
        rate_limit: {5, 60_000},
        timeout_ms: 10_000,
        requires_consent: true
      }
    end

    def execute(_args, _context), do: {:ok, "privileged result"}
  end

  defmodule MinimalHandler do
    @moduledoc false
    use JidoCode.Tools.Behaviours.SecureHandler

    @impl true
    def security_properties do
      %{tier: :read_only}
    end

    def execute(_args, _context), do: {:ok, "minimal"}
  end

  # =============================================================================
  # Tests: security_properties/0 callback
  # =============================================================================

  describe "security_properties/0 callback" do
    test "returns complete properties for ReadOnlyHandler" do
      props = ReadOnlyHandler.security_properties()

      assert props.tier == :read_only
      assert props.rate_limit == {100, 60_000}
      assert props.timeout_ms == 5000
      assert props.requires_consent == false
    end

    test "returns properties for WriteHandler" do
      props = WriteHandler.security_properties()

      assert props.tier == :write
      assert props.rate_limit == {30, 60_000}
      refute Map.has_key?(props, :timeout_ms)
      refute Map.has_key?(props, :requires_consent)
    end

    test "returns properties for ExecuteHandler" do
      props = ExecuteHandler.security_properties()

      assert props.tier == :execute
      assert props.timeout_ms == 30_000
      assert props.requires_consent == true
      refute Map.has_key?(props, :rate_limit)
    end

    test "returns properties for PrivilegedHandler" do
      props = PrivilegedHandler.security_properties()

      assert props.tier == :privileged
      assert props.rate_limit == {5, 60_000}
      assert props.timeout_ms == 10_000
      assert props.requires_consent == true
    end

    test "minimal handler only requires tier" do
      props = MinimalHandler.security_properties()

      assert props.tier == :read_only
      assert map_size(props) == 1
    end
  end

  # =============================================================================
  # Tests: validate_security/2 callback
  # =============================================================================

  describe "validate_security/2 callback" do
    test "default implementation returns :ok" do
      assert :ok == ReadOnlyHandler.validate_security(%{}, %{})
      assert :ok == MinimalHandler.validate_security(%{"any" => "args"}, %{session_id: "123"})
    end

    test "WriteHandler validates path traversal" do
      assert :ok == WriteHandler.validate_security(%{"path" => "file.txt"}, %{})
      assert :ok == WriteHandler.validate_security(%{"path" => "subdir/file.txt"}, %{})

      assert {:error, "path traversal not allowed"} ==
               WriteHandler.validate_security(%{"path" => "../secret.txt"}, %{})

      assert {:error, "path traversal not allowed"} ==
               WriteHandler.validate_security(%{"path" => "foo/../bar"}, %{})
    end

    test "validates with context" do
      context = %{session_id: "sess_123", project_root: "/home/user/project"}
      assert :ok == WriteHandler.validate_security(%{"path" => "src/main.ex"}, context)
    end
  end

  # =============================================================================
  # Tests: sanitize_output/1 callback
  # =============================================================================

  describe "sanitize_output/1 callback" do
    test "default implementation returns result unchanged" do
      assert "hello" == ReadOnlyHandler.sanitize_output("hello")
      assert %{foo: "bar"} == ReadOnlyHandler.sanitize_output(%{foo: "bar"})
      assert [1, 2, 3] == ReadOnlyHandler.sanitize_output([1, 2, 3])
    end

    test "ExecuteHandler redacts API keys" do
      input = "API key: sk-abcdefghijklmnopqrstuvwxyz012345678901234567890123"
      result = ExecuteHandler.sanitize_output(input)

      assert result == "API key: [REDACTED_API_KEY]"
    end

    test "ExecuteHandler redacts passwords" do
      input = "Config: password: supersecret123"
      result = ExecuteHandler.sanitize_output(input)

      assert result == "Config: password: [REDACTED]"
    end

    test "ExecuteHandler handles non-string input" do
      assert %{data: 123} == ExecuteHandler.sanitize_output(%{data: 123})
      assert [1, 2] == ExecuteHandler.sanitize_output([1, 2])
    end

    test "multiple sensitive patterns in one string" do
      input =
        "password=secret123 and key sk-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

      result = ExecuteHandler.sanitize_output(input)

      assert result == "password: [REDACTED] and key [REDACTED_API_KEY]"
    end
  end

  # =============================================================================
  # Tests: tier_hierarchy/0
  # =============================================================================

  describe "tier_hierarchy/0" do
    test "returns tiers in order of privilege" do
      hierarchy = SecureHandler.tier_hierarchy()

      assert hierarchy == [:read_only, :write, :execute, :privileged]
    end
  end

  # =============================================================================
  # Tests: tier_allowed?/2
  # =============================================================================

  describe "tier_allowed?/2" do
    test "same tier is allowed" do
      assert SecureHandler.tier_allowed?(:read_only, :read_only)
      assert SecureHandler.tier_allowed?(:write, :write)
      assert SecureHandler.tier_allowed?(:execute, :execute)
      assert SecureHandler.tier_allowed?(:privileged, :privileged)
    end

    test "lower tier is allowed with higher granted tier" do
      # read_only allowed with any tier
      assert SecureHandler.tier_allowed?(:read_only, :write)
      assert SecureHandler.tier_allowed?(:read_only, :execute)
      assert SecureHandler.tier_allowed?(:read_only, :privileged)

      # write allowed with execute or privileged
      assert SecureHandler.tier_allowed?(:write, :execute)
      assert SecureHandler.tier_allowed?(:write, :privileged)

      # execute allowed with privileged
      assert SecureHandler.tier_allowed?(:execute, :privileged)
    end

    test "higher tier is not allowed with lower granted tier" do
      refute SecureHandler.tier_allowed?(:write, :read_only)
      refute SecureHandler.tier_allowed?(:execute, :read_only)
      refute SecureHandler.tier_allowed?(:execute, :write)
      refute SecureHandler.tier_allowed?(:privileged, :read_only)
      refute SecureHandler.tier_allowed?(:privileged, :write)
      refute SecureHandler.tier_allowed?(:privileged, :execute)
    end
  end

  # =============================================================================
  # Tests: valid_tier?/1
  # =============================================================================

  describe "valid_tier?/1" do
    test "returns true for valid tiers" do
      assert SecureHandler.valid_tier?(:read_only)
      assert SecureHandler.valid_tier?(:write)
      assert SecureHandler.valid_tier?(:execute)
      assert SecureHandler.valid_tier?(:privileged)
    end

    test "returns false for invalid tiers" do
      refute SecureHandler.valid_tier?(:invalid)
      refute SecureHandler.valid_tier?(:admin)
      refute SecureHandler.valid_tier?("read_only")
      refute SecureHandler.valid_tier?(nil)
      refute SecureHandler.valid_tier?(1)
    end
  end

  # =============================================================================
  # Tests: validate_properties/1
  # =============================================================================

  describe "validate_properties/1" do
    test "valid minimal properties" do
      assert :ok == SecureHandler.validate_properties(%{tier: :read_only})
      assert :ok == SecureHandler.validate_properties(%{tier: :write})
      assert :ok == SecureHandler.validate_properties(%{tier: :execute})
      assert :ok == SecureHandler.validate_properties(%{tier: :privileged})
    end

    test "valid complete properties" do
      props = %{
        tier: :write,
        rate_limit: {30, 60_000},
        timeout_ms: 5000,
        requires_consent: true
      }

      assert :ok == SecureHandler.validate_properties(props)
    end

    test "missing tier returns error" do
      assert {:error, "tier is required"} == SecureHandler.validate_properties(%{})

      assert {:error, "tier is required"} ==
               SecureHandler.validate_properties(%{rate_limit: {10, 1000}})
    end

    test "invalid tier returns error" do
      assert {:error, "invalid tier: :invalid"} ==
               SecureHandler.validate_properties(%{tier: :invalid})

      assert {:error, "invalid tier: \"read_only\""} ==
               SecureHandler.validate_properties(%{tier: "read_only"})
    end

    test "invalid rate_limit returns error" do
      assert {:error, msg} = SecureHandler.validate_properties(%{tier: :read_only, rate_limit: {0, 1000}})
      assert msg =~ "rate_limit must be"

      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, rate_limit: {10, 0}})
      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, rate_limit: {10, -1}})
      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, rate_limit: "invalid"})
      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, rate_limit: {10}})
    end

    test "invalid timeout_ms returns error" do
      assert {:error, msg} = SecureHandler.validate_properties(%{tier: :read_only, timeout_ms: 0})
      assert msg =~ "timeout_ms must be a positive integer"

      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, timeout_ms: -1})
      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, timeout_ms: "5000"})
    end

    test "invalid requires_consent returns error" do
      assert {:error, msg} = SecureHandler.validate_properties(%{tier: :read_only, requires_consent: "yes"})
      assert msg =~ "requires_consent must be a boolean"

      assert {:error, _} = SecureHandler.validate_properties(%{tier: :read_only, requires_consent: 1})
    end

    test "non-map input returns error" do
      assert {:error, "security_properties must return a map"} ==
               SecureHandler.validate_properties([tier: :read_only])

      assert {:error, "security_properties must return a map"} ==
               SecureHandler.validate_properties(nil)
    end
  end

  # =============================================================================
  # Tests: __using__ macro and behavior implementation
  # =============================================================================

  describe "__using__ macro" do
    test "handlers implement the behavior" do
      # Check that modules have the expected callbacks
      assert function_exported?(ReadOnlyHandler, :security_properties, 0)
      assert function_exported?(ReadOnlyHandler, :validate_security, 2)
      assert function_exported?(ReadOnlyHandler, :sanitize_output, 1)
    end

    test "default callbacks can be overridden" do
      # WriteHandler overrides validate_security
      assert {:error, _} = WriteHandler.validate_security(%{"path" => "../foo"}, %{})

      # ExecuteHandler overrides sanitize_output
      assert "[REDACTED_API_KEY]" ==
               ExecuteHandler.sanitize_output("sk-" <> String.duplicate("a", 50))
    end

    test "handlers have __secure_handler_loaded__ function" do
      assert function_exported?(ReadOnlyHandler, :__secure_handler_loaded__, 0)
      assert function_exported?(WriteHandler, :__secure_handler_loaded__, 0)
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "__secure_handler_loaded__ emits telemetry event" do
      ref = make_ref()
      test_pid = self()

      handler_id = "test-handler-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :handler_loaded],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        # Call the function that emits telemetry
        ReadOnlyHandler.__secure_handler_loaded__()

        assert_receive {:telemetry_event, ^ref, [:jido_code, :security, :handler_loaded],
                        measurements, metadata}

        assert is_integer(measurements.system_time)
        assert metadata.module == ReadOnlyHandler
        assert metadata.tier == :read_only
      after
        :telemetry.detach(handler_id)
      end
    end

    test "telemetry includes correct tier for each handler" do
      ref = make_ref()
      test_pid = self()

      handler_id = "test-handler-tier-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :handler_loaded],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:tier, ref, metadata.tier})
        end,
        nil
      )

      try do
        ReadOnlyHandler.__secure_handler_loaded__()
        assert_receive {:tier, ^ref, :read_only}

        WriteHandler.__secure_handler_loaded__()
        assert_receive {:tier, ^ref, :write}

        ExecuteHandler.__secure_handler_loaded__()
        assert_receive {:tier, ^ref, :execute}

        PrivilegedHandler.__secure_handler_loaded__()
        assert_receive {:tier, ^ref, :privileged}
      after
        :telemetry.detach(handler_id)
      end
    end
  end
end
