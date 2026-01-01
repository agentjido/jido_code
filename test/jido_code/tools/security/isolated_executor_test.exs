defmodule JidoCode.Tools.Security.IsolatedExecutorTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.Security.IsolatedExecutor

  # =============================================================================
  # Test Fixtures - Sample handlers for testing
  # =============================================================================

  defmodule SuccessHandler do
    @moduledoc false
    def execute(args, _context) do
      {:ok, Map.get(args, "value", "default")}
    end
  end

  defmodule SlowHandler do
    @moduledoc false
    def execute(%{"sleep_ms" => ms}, _context) do
      Process.sleep(ms)
      {:ok, "completed after #{ms}ms"}
    end

    def execute(_args, _context) do
      Process.sleep(5000)
      {:ok, "completed"}
    end
  end

  defmodule CrashHandler do
    @moduledoc false
    def execute(%{"type" => "raise"}, _context) do
      raise "intentional crash"
    end

    def execute(%{"type" => "throw"}, _context) do
      throw(:intentional_throw)
    end

    def execute(%{"type" => "exit"}, _context) do
      exit(:intentional_exit)
    end

    def execute(_args, _context) do
      raise "default crash"
    end
  end

  defmodule MemoryHogHandler do
    @moduledoc false
    def execute(%{"size" => size}, _context) do
      # Create a large list to consume memory
      # Each element is ~8 bytes on 64-bit
      _data = :lists.seq(1, size)
      {:ok, "allocated #{size} elements"}
    end

    def execute(_args, _context) do
      # Default: try to allocate a lot
      _data = :lists.seq(1, 10_000_000)
      {:ok, "allocated"}
    end
  end

  defmodule ErrorHandler do
    @moduledoc false
    def execute(_args, _context) do
      {:error, "intentional error"}
    end
  end

  # =============================================================================
  # Setup
  # =============================================================================

  setup do
    # Ensure supervisor is available
    unless IsolatedExecutor.supervisor_available?() do
      start_supervised!({Task.Supervisor, name: JidoCode.TaskSupervisor})
    end

    :ok
  end

  # =============================================================================
  # Tests: execute_isolated/4 - Success cases
  # =============================================================================

  describe "execute_isolated/4 success cases" do
    test "executes handler and returns result" do
      assert {:ok, "test_value"} =
               IsolatedExecutor.execute_isolated(
                 SuccessHandler,
                 %{"value" => "test_value"},
                 %{}
               )
    end

    test "executes handler with default args" do
      assert {:ok, "default"} =
               IsolatedExecutor.execute_isolated(SuccessHandler, %{}, %{})
    end

    test "passes context to handler" do
      defmodule ContextHandler do
        def execute(_args, context) do
          {:ok, context[:session_id]}
        end
      end

      assert {:ok, "sess_123"} =
               IsolatedExecutor.execute_isolated(
                 ContextHandler,
                 %{},
                 %{session_id: "sess_123"}
               )
    end

    test "handler can return error tuple" do
      assert {:error, "intentional error"} =
               IsolatedExecutor.execute_isolated(ErrorHandler, %{}, %{})
    end
  end

  # =============================================================================
  # Tests: execute_isolated/4 - Timeout enforcement
  # =============================================================================

  describe "execute_isolated/4 timeout enforcement" do
    test "returns :timeout when handler exceeds timeout" do
      assert {:error, :timeout} =
               IsolatedExecutor.execute_isolated(
                 SlowHandler,
                 %{"sleep_ms" => 500},
                 %{},
                 timeout: 100
               )
    end

    test "completes within timeout" do
      assert {:ok, _} =
               IsolatedExecutor.execute_isolated(
                 SlowHandler,
                 %{"sleep_ms" => 50},
                 %{},
                 timeout: 500
               )
    end

    test "uses default timeout when not specified" do
      defaults = IsolatedExecutor.defaults()
      assert defaults.timeout == 30_000
    end
  end

  # =============================================================================
  # Tests: execute_isolated/4 - Memory limit enforcement
  # =============================================================================

  describe "execute_isolated/4 memory limit" do
    @tag :memory_intensive
    test "kills process when exceeding max_heap_size" do
      # Set a very small heap limit
      result =
        IsolatedExecutor.execute_isolated(
          MemoryHogHandler,
          %{"size" => 1_000_000},
          %{},
          max_heap_size: 1000,
          timeout: 5000
        )

      # Should either be killed for heap size or crash trying
      assert match?({:error, {:killed, :max_heap_size}}, result) or
               match?({:error, {:crashed, _}}, result)
    end

    test "completes when within memory limit" do
      # Small allocation within limit
      assert {:ok, _} =
               IsolatedExecutor.execute_isolated(
                 MemoryHogHandler,
                 %{"size" => 100},
                 %{},
                 max_heap_size: 100_000
               )
    end

    test "uses default max_heap_size when not specified" do
      defaults = IsolatedExecutor.defaults()
      assert defaults.max_heap_size == 1_000_000
    end
  end

  # =============================================================================
  # Tests: execute_isolated/4 - Crash handling
  # =============================================================================

  describe "execute_isolated/4 crash handling" do
    test "handles raised exceptions" do
      result = IsolatedExecutor.execute_isolated(CrashHandler, %{"type" => "raise"}, %{})

      assert {:error, {:crashed, {:exception, %RuntimeError{message: "intentional crash"}, _}}} =
               result
    end

    test "handles thrown values" do
      result = IsolatedExecutor.execute_isolated(CrashHandler, %{"type" => "throw"}, %{})

      assert {:error, {:crashed, {:throw, :intentional_throw}}} = result
    end

    test "handles exit signals" do
      result = IsolatedExecutor.execute_isolated(CrashHandler, %{"type" => "exit"}, %{})

      assert {:error, {:crashed, {:exit, :intentional_exit}}} = result
    end

    test "crash does not affect caller process" do
      caller_pid = self()

      # Execute a crashing handler
      _result = IsolatedExecutor.execute_isolated(CrashHandler, %{}, %{})

      # Caller should still be alive
      assert Process.alive?(caller_pid)
    end

    test "multiple crashes in sequence don't accumulate" do
      for _ <- 1..5 do
        result = IsolatedExecutor.execute_isolated(CrashHandler, %{}, %{})
        assert {:error, {:crashed, _}} = result
      end

      # System should still be stable
      assert {:ok, "default"} =
               IsolatedExecutor.execute_isolated(SuccessHandler, %{}, %{})
    end
  end

  # =============================================================================
  # Tests: supervisor_available?/1
  # =============================================================================

  describe "supervisor_available?/1" do
    test "returns true when default supervisor is running" do
      assert IsolatedExecutor.supervisor_available?()
    end

    test "returns false for non-existent supervisor" do
      refute IsolatedExecutor.supervisor_available?(:NonExistentSupervisor)
    end
  end

  # =============================================================================
  # Tests: defaults/0
  # =============================================================================

  describe "defaults/0" do
    test "returns default configuration" do
      defaults = IsolatedExecutor.defaults()

      assert Map.has_key?(defaults, :timeout)
      assert Map.has_key?(defaults, :max_heap_size)
      assert Map.has_key?(defaults, :supervisor)

      assert is_integer(defaults.timeout)
      assert is_integer(defaults.max_heap_size)
      assert is_atom(defaults.supervisor)
    end
  end

  # =============================================================================
  # Tests: Telemetry emission
  # =============================================================================

  describe "telemetry emission" do
    test "emits telemetry on successful execution" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-isolation-success-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :isolation],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, event, measurements, metadata})
        end,
        nil
      )

      try do
        assert {:ok, _} = IsolatedExecutor.execute_isolated(SuccessHandler, %{}, %{})

        assert_receive {:telemetry, ^ref, [:jido_code, :security, :isolation], measurements,
                        metadata}

        assert is_integer(measurements.duration)
        assert measurements.duration >= 0
        assert metadata.handler == SuccessHandler
        assert metadata.result == :ok
        assert metadata.reason == nil
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits telemetry on timeout" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-isolation-timeout-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :isolation],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, metadata})
        end,
        nil
      )

      try do
        IsolatedExecutor.execute_isolated(SlowHandler, %{"sleep_ms" => 500}, %{}, timeout: 50)

        assert_receive {:telemetry, ^ref, metadata}
        assert metadata.result == :timeout
      after
        :telemetry.detach(handler_id)
      end
    end

    test "emits telemetry on crash" do
      ref = make_ref()
      test_pid = self()
      handler_id = "test-isolation-crash-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:jido_code, :security, :isolation],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry, ref, metadata})
        end,
        nil
      )

      try do
        IsolatedExecutor.execute_isolated(CrashHandler, %{}, %{})

        assert_receive {:telemetry, ^ref, metadata}
        assert metadata.result == :crashed
        assert metadata.reason != nil
      after
        :telemetry.detach(handler_id)
      end
    end
  end

  # =============================================================================
  # Tests: Custom supervisor
  # =============================================================================

  describe "custom supervisor" do
    test "can use a different supervisor" do
      # Start a custom supervisor
      {:ok, _} = Task.Supervisor.start_link(name: :CustomTestSupervisor)

      assert {:ok, "default"} =
               IsolatedExecutor.execute_isolated(
                 SuccessHandler,
                 %{},
                 %{},
                 supervisor: :CustomTestSupervisor
               )
    end
  end
end
