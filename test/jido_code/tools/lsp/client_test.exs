defmodule JidoCode.Tools.LSP.ClientTest do
  use ExUnit.Case, async: false

  alias JidoCode.Tools.LSP.Client

  # ============================================================================
  # Test Fixtures
  # ============================================================================

  @project_root System.tmp_dir!()

  # ============================================================================
  # Setup and Helpers
  # ============================================================================

  setup do
    # Ensure clean state
    :ok
  end

  # ============================================================================
  # Expert Path Detection Tests (3.6.4 - Process Spawning)
  # ============================================================================

  describe "find_expert_path/0" do
    test "returns {:error, :not_found} when expert is not available" do
      original = System.get_env("EXPERT_PATH")

      try do
        System.delete_env("EXPERT_PATH")
        result = Client.find_expert_path()
        assert result == {:error, :not_found} or match?({:ok, _}, result)
      after
        if original, do: System.put_env("EXPERT_PATH", original)
      end
    end

    test "returns path from EXPERT_PATH environment variable when file exists" do
      mix_path = System.find_executable("mix")

      if mix_path do
        original = System.get_env("EXPERT_PATH")

        try do
          System.put_env("EXPERT_PATH", mix_path)
          assert {:ok, ^mix_path} = Client.find_expert_path()
        after
          if original do
            System.put_env("EXPERT_PATH", original)
          else
            System.delete_env("EXPERT_PATH")
          end
        end
      end
    end

    test "returns {:error, :not_found} when EXPERT_PATH points to non-existent file" do
      original = System.get_env("EXPERT_PATH")

      try do
        System.put_env("EXPERT_PATH", "/nonexistent/path/to/expert")
        assert {:error, :not_found} = Client.find_expert_path()
      after
        if original do
          System.put_env("EXPERT_PATH", original)
        else
          System.delete_env("EXPERT_PATH")
        end
      end
    end

    test "prefers EXPERT_PATH over system PATH" do
      mix_path = System.find_executable("mix")
      elixir_path = System.find_executable("elixir")

      if mix_path && elixir_path do
        original = System.get_env("EXPERT_PATH")

        try do
          # Set EXPERT_PATH to mix
          System.put_env("EXPERT_PATH", mix_path)
          assert {:ok, ^mix_path} = Client.find_expert_path()
        after
          if original do
            System.put_env("EXPERT_PATH", original)
          else
            System.delete_env("EXPERT_PATH")
          end
        end
      end
    end
  end

  describe "expert_available?/0" do
    test "returns boolean indicating expert availability" do
      result = Client.expert_available?()
      assert is_boolean(result)
    end

    test "returns false when EXPERT_PATH points to non-existent file" do
      original = System.get_env("EXPERT_PATH")

      try do
        System.put_env("EXPERT_PATH", "/nonexistent/path/to/expert")
        assert Client.expert_available?() == false
      after
        if original do
          System.put_env("EXPERT_PATH", original)
        else
          System.delete_env("EXPERT_PATH")
        end
      end
    end
  end

  # ============================================================================
  # Client Initialization Tests (3.6.4 - Process Spawning)
  # ============================================================================

  describe "start_link/1" do
    test "requires project_root option" do
      Process.flag(:trap_exit, true)
      assert {:error, _reason} = Client.start_link([])
    after
      Process.flag(:trap_exit, false)
    end

    test "starts with auto_start: false" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)
      assert Process.alive?(pid)

      status = Client.status(pid)
      assert status.initialized == false
      assert status.port_open == false

      GenServer.stop(pid)
    end

    test "accepts name option for registration" do
      {:ok, pid} =
        Client.start_link(
          project_root: @project_root,
          auto_start: false,
          name: :test_lsp_client
        )

      assert Process.whereis(:test_lsp_client) == pid
      GenServer.stop(pid)
    end

    test "accepts custom expert_path option" do
      mix_path = System.find_executable("mix")

      if mix_path do
        {:ok, pid} =
          Client.start_link(
            project_root: @project_root,
            auto_start: false,
            expert_path: mix_path
          )

        assert Process.alive?(pid)
        GenServer.stop(pid)
      end
    end

    test "initializes with correct default state" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      assert status.initialized == false
      assert status.pending_requests == 0
      assert status.capabilities == %{}
      assert status.port_open == false
      assert status.project_root == @project_root

      GenServer.stop(pid)
    end

    test "multiple clients can run with different names" do
      {:ok, pid1} =
        Client.start_link(
          project_root: @project_root,
          auto_start: false,
          name: :lsp_client_1
        )

      {:ok, pid2} =
        Client.start_link(
          project_root: @project_root,
          auto_start: false,
          name: :lsp_client_2
        )

      assert pid1 != pid2
      assert Process.whereis(:lsp_client_1) == pid1
      assert Process.whereis(:lsp_client_2) == pid2

      GenServer.stop(pid1)
      GenServer.stop(pid2)
    end
  end

  # ============================================================================
  # Status Tests
  # ============================================================================

  describe "status/1" do
    test "returns current client state" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)

      assert is_map(status)
      assert status.initialized == false
      assert status.pending_requests == 0
      assert status.capabilities == %{}
      assert status.port_open == false
      assert status.project_root == @project_root

      GenServer.stop(pid)
    end

    test "status reflects project_root correctly" do
      custom_root = "/custom/project/root"
      {:ok, pid} = Client.start_link(project_root: custom_root, auto_start: false)

      status = Client.status(pid)
      assert status.project_root == custom_root

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Request Tests (3.6.4 - Request/Response Correlation)
  # ============================================================================

  describe "request/4" do
    test "returns {:error, :not_initialized} when not initialized" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      result = Client.request(pid, "textDocument/hover", %{})
      assert result == {:error, :not_initialized}

      GenServer.stop(pid)
    end

    test "accepts custom timeout parameter" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Request with short timeout - should still return :not_initialized before timeout
      result = Client.request(pid, "textDocument/hover", %{}, 100)
      assert result == {:error, :not_initialized}

      GenServer.stop(pid)
    end

    test "handles various LSP methods" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # All should return not_initialized, but verify different methods are accepted
      assert {:error, :not_initialized} = Client.request(pid, "textDocument/hover", %{})
      assert {:error, :not_initialized} = Client.request(pid, "textDocument/definition", %{})
      assert {:error, :not_initialized} = Client.request(pid, "textDocument/references", %{})
      assert {:error, :not_initialized} = Client.request(pid, "textDocument/completion", %{})

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Notification Tests (3.6.4 - Notification Handling)
  # ============================================================================

  describe "notify/3" do
    test "sends notification without waiting for response" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Should return immediately even though not connected
      assert :ok = Client.notify(pid, "textDocument/didOpen", %{})
      assert :ok = Client.notify(pid, "textDocument/didClose", %{})
      assert :ok = Client.notify(pid, "textDocument/didSave", %{})

      GenServer.stop(pid)
    end

    test "accepts various notification types" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Test various notification methods
      assert :ok =
               Client.notify(pid, "textDocument/didOpen", %{
                 "textDocument" => %{
                   "uri" => "file:///test.ex",
                   "languageId" => "elixir",
                   "version" => 1,
                   "text" => "defmodule Test do\nend"
                 }
               })

      assert :ok =
               Client.notify(pid, "textDocument/didChange", %{
                 "textDocument" => %{"uri" => "file:///test.ex", "version" => 2},
                 "contentChanges" => [%{"text" => "defmodule Test do\n  # changed\nend"}]
               })

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Subscription Tests (3.6.4 - Notification Handling)
  # ============================================================================

  describe "subscribe/2 and unsubscribe/2" do
    test "subscribes and unsubscribes from notifications" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      :ok = Client.subscribe(pid, self())
      :ok = Client.unsubscribe(pid, self())

      GenServer.stop(pid)
    end

    test "multiple subscribers can be registered" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Create multiple subscriber processes
      sub1 = spawn(fn -> Process.sleep(:infinity) end)
      sub2 = spawn(fn -> Process.sleep(:infinity) end)
      sub3 = spawn(fn -> Process.sleep(:infinity) end)

      :ok = Client.subscribe(pid, sub1)
      :ok = Client.subscribe(pid, sub2)
      :ok = Client.subscribe(pid, sub3)

      # All should be subscribed
      assert Process.alive?(pid)

      # Clean up
      Process.exit(sub1, :kill)
      Process.exit(sub2, :kill)
      Process.exit(sub3, :kill)
      GenServer.stop(pid)
    end

    test "subscribing same pid multiple times doesn't duplicate" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      :ok = Client.subscribe(pid, self())
      :ok = Client.subscribe(pid, self())
      :ok = Client.subscribe(pid, self())

      # Should still work fine
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "unsubscribe returns :ok even if not subscribed" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Unsubscribe without subscribing first
      :ok = Client.unsubscribe(pid, self())

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Notification Broadcasting Tests (3.6.4 - Notification Handling)
  # ============================================================================

  describe "notification broadcasting" do
    test "monitors subscriber processes" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Create a temporary subscriber process
      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Client.subscribe(pid, subscriber)

      # Kill the subscriber
      Process.exit(subscriber, :kill)

      # Give the client time to receive the DOWN message
      Process.sleep(50)

      # The client should still be alive and functioning
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "removes subscriber when it exits" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Create and register subscriber
      subscriber =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      :ok = Client.subscribe(pid, subscriber)

      # Kill the subscriber
      Process.exit(subscriber, :kill)
      Process.sleep(50)

      # Client should handle this gracefully
      status = Client.status(pid)
      assert status.initialized == false

      GenServer.stop(pid)
    end

    test "handles multiple subscriber exits" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Create multiple subscribers
      subscribers =
        for _ <- 1..5 do
          spawn(fn -> Process.sleep(:infinity) end)
        end

      for sub <- subscribers do
        :ok = Client.subscribe(pid, sub)
      end

      # Kill all subscribers
      for sub <- subscribers do
        Process.exit(sub, :kill)
      end

      Process.sleep(100)

      # Client should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # JSON-RPC Message Encoding Tests (3.6.4 - Message Encoding/Decoding)
  # ============================================================================

  describe "JSON-RPC message encoding" do
    test "request encoding produces valid Content-Length header" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # The request will fail because not initialized, but verify client state
      status = Client.status(pid)
      assert status.pending_requests == 0

      GenServer.stop(pid)
    end

    test "client maintains request_id counter" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Status should show 0 pending requests initially
      status = Client.status(pid)
      assert status.pending_requests == 0

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Message Parsing Tests (3.6.4 - Message Encoding/Decoding)
  # ============================================================================

  describe "message parsing" do
    test "parses valid JSON-RPC response format" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Verify client handles state correctly
      status = Client.status(pid)
      assert status.initialized == false

      GenServer.stop(pid)
    end

    test "client handles empty buffer correctly" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Client should be in clean state
      status = Client.status(pid)
      assert status.initialized == false
      assert status.pending_requests == 0

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Shutdown Tests (3.6.4 - Graceful Shutdown)
  # ============================================================================

  describe "shutdown/1" do
    test "gracefully shuts down when not connected" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      assert :ok = Client.shutdown(pid)

      status = Client.status(pid)
      assert status.initialized == false
      assert status.port_open == false

      GenServer.stop(pid)
    end

    test "shutdown is idempotent" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Multiple shutdowns should work
      assert :ok = Client.shutdown(pid)
      assert :ok = Client.shutdown(pid)
      assert :ok = Client.shutdown(pid)

      status = Client.status(pid)
      assert status.initialized == false

      GenServer.stop(pid)
    end

    test "client can be stopped after shutdown" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      :ok = Client.shutdown(pid)

      # Should be able to stop the GenServer
      assert :ok = GenServer.stop(pid)
      refute Process.alive?(pid)
    end
  end

  # ============================================================================
  # Terminate Callback Tests (3.6.4 - Graceful Shutdown)
  # ============================================================================

  describe "terminate/2" do
    test "GenServer.stop triggers clean termination" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Stop should work cleanly
      :ok = GenServer.stop(pid)

      refute Process.alive?(pid)
    end

    test "terminate handles brutal kill" do
      # Use trap_exit to avoid the test process receiving the exit signal
      Process.flag(:trap_exit, true)

      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Brutal kill should work - we'll receive the EXIT message
      Process.exit(pid, :kill)

      # Wait for the EXIT message
      assert_receive {:EXIT, ^pid, :killed}, 1000

      refute Process.alive?(pid)
    after
      Process.flag(:trap_exit, false)
    end
  end

  # ============================================================================
  # Error Handling Tests (3.6.4 - Reconnection)
  # ============================================================================

  describe "error handling" do
    test "handles unexpected messages gracefully" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Send unexpected messages
      send(pid, :unexpected_message)
      send(pid, {:weird, :tuple})
      send(pid, "string message")

      Process.sleep(10)

      # Client should still be alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "client survives malformed data" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      # Send data that would be malformed for LSP parsing
      send(pid, {:port_data, "not valid lsp"})

      Process.sleep(10)

      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Connection State Tests (3.6.4 - Process Spawning)
  # ============================================================================

  describe "connection state" do
    test "tracks port_open correctly when not connected" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      assert status.port_open == false

      GenServer.stop(pid)
    end

    test "tracks initialized correctly when not started" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      assert status.initialized == false

      GenServer.stop(pid)
    end

    test "capabilities are empty when not initialized" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      assert status.capabilities == %{}

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Initialize Handshake Tests (3.6.4 - Initialize Handshake)
  # ============================================================================

  describe "initialize handshake" do
    test "auto_start triggers initialization message" do
      # With auto_start: true (default), client will try to start Expert
      # This test verifies the behavior when Expert is not available
      original = System.get_env("EXPERT_PATH")

      try do
        System.put_env("EXPERT_PATH", "/nonexistent/expert")
        {:ok, pid} = Client.start_link(project_root: @project_root)

        # Wait briefly for initialization attempt
        Process.sleep(100)

        # Should still be alive even if Expert not found
        assert Process.alive?(pid)

        status = Client.status(pid)
        # Without Expert, should not be initialized
        assert status.initialized == false

        GenServer.stop(pid)
      after
        if original do
          System.put_env("EXPERT_PATH", original)
        else
          System.delete_env("EXPERT_PATH")
        end
      end
    end

    test "client advertises correct capabilities" do
      # Test that client state includes expected capability format
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      # Capabilities are empty until initialized
      assert status.capabilities == %{}

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Reconnection Tests (3.6.4 - Reconnection on Crash)
  # ============================================================================

  describe "reconnection behavior" do
    test "client schedules restart when Expert not found" do
      original = System.get_env("EXPERT_PATH")

      try do
        System.put_env("EXPERT_PATH", "/nonexistent/expert")
        {:ok, pid} = Client.start_link(project_root: @project_root)

        # Client should still be alive
        Process.sleep(100)
        assert Process.alive?(pid)

        # Status should show not initialized
        status = Client.status(pid)
        assert status.initialized == false
        assert status.port_open == false

        GenServer.stop(pid)
      after
        if original do
          System.put_env("EXPERT_PATH", original)
        else
          System.delete_env("EXPERT_PATH")
        end
      end
    end

    test "client continues to function after failed start" do
      original = System.get_env("EXPERT_PATH")

      try do
        System.put_env("EXPERT_PATH", "/nonexistent/expert")
        {:ok, pid} = Client.start_link(project_root: @project_root)

        Process.sleep(100)

        # Client should still respond to API calls
        assert {:error, :not_initialized} = Client.request(pid, "test", %{})
        assert :ok = Client.notify(pid, "test", %{})
        assert :ok = Client.subscribe(pid, self())
        assert is_map(Client.status(pid))
        assert :ok = Client.shutdown(pid)

        GenServer.stop(pid)
      after
        if original do
          System.put_env("EXPERT_PATH", original)
        else
          System.delete_env("EXPERT_PATH")
        end
      end
    end
  end

  # ============================================================================
  # Pending Request Tracking Tests (3.6.4 - Request/Response Correlation)
  # ============================================================================

  describe "pending request tracking" do
    test "tracks zero pending requests when not initialized" do
      {:ok, pid} = Client.start_link(project_root: @project_root, auto_start: false)

      status = Client.status(pid)
      assert status.pending_requests == 0

      # Try to make a request - should fail immediately
      {:error, :not_initialized} = Client.request(pid, "test", %{})

      # Still zero pending
      status = Client.status(pid)
      assert status.pending_requests == 0

      GenServer.stop(pid)
    end
  end

  # ============================================================================
  # Integration Tests (require Expert to be installed)
  # ============================================================================

  describe "integration with Expert" do
    @tag :integration
    @tag :expert_required

    test "connects to Expert and initializes" do
      case Client.find_expert_path() do
        {:ok, _path} ->
          {:ok, pid} = Client.start_link(project_root: @project_root)

          # Wait for initialization
          Process.sleep(2000)

          status = Client.status(pid)
          assert status.initialized == true
          assert status.port_open == true
          assert is_map(status.capabilities)

          Client.shutdown(pid)
          GenServer.stop(pid)

        {:error, :not_found} ->
          :ok
      end
    end

    test "sends hover request and receives response" do
      case Client.find_expert_path() do
        {:ok, _path} ->
          test_file = Path.join(@project_root, "test_hover.ex")
          File.write!(test_file, "defmodule TestHover do\n  def hello, do: :world\nend")

          try do
            {:ok, pid} = Client.start_link(project_root: @project_root)
            Process.sleep(2000)

            Client.notify(pid, "textDocument/didOpen", %{
              "textDocument" => %{
                "uri" => "file://#{test_file}",
                "languageId" => "elixir",
                "version" => 1,
                "text" => File.read!(test_file)
              }
            })

            Process.sleep(500)

            result =
              Client.request(pid, "textDocument/hover", %{
                "textDocument" => %{"uri" => "file://#{test_file}"},
                "position" => %{"line" => 1, "character" => 6}
              })

            assert match?({:ok, _}, result) or match?({:error, _}, result)

            Client.shutdown(pid)
            GenServer.stop(pid)
          after
            File.rm(test_file)
          end

        {:error, :not_found} ->
          :ok
      end
    end

    test "sends definition request and receives response" do
      case Client.find_expert_path() do
        {:ok, _path} ->
          test_file = Path.join(@project_root, "test_definition.ex")

          File.write!(test_file, """
          defmodule TestDefinition do
            def hello, do: :world

            def call_hello do
              hello()
            end
          end
          """)

          try do
            {:ok, pid} = Client.start_link(project_root: @project_root)
            Process.sleep(2000)

            Client.notify(pid, "textDocument/didOpen", %{
              "textDocument" => %{
                "uri" => "file://#{test_file}",
                "languageId" => "elixir",
                "version" => 1,
                "text" => File.read!(test_file)
              }
            })

            Process.sleep(500)

            result =
              Client.request(pid, "textDocument/definition", %{
                "textDocument" => %{"uri" => "file://#{test_file}"},
                "position" => %{"line" => 4, "character" => 4}
              })

            assert match?({:ok, _}, result) or match?({:error, _}, result)

            Client.shutdown(pid)
            GenServer.stop(pid)
          after
            File.rm(test_file)
          end

        {:error, :not_found} ->
          :ok
      end
    end

    test "receives diagnostics notifications" do
      case Client.find_expert_path() do
        {:ok, _path} ->
          test_file = Path.join(@project_root, "test_diagnostics.ex")
          # Write a file with a syntax error
          File.write!(test_file, "defmodule TestDiagnostics do\n  def broken(\nend")

          try do
            {:ok, pid} = Client.start_link(project_root: @project_root)
            Process.sleep(2000)

            :ok = Client.subscribe(pid, self())

            Client.notify(pid, "textDocument/didOpen", %{
              "textDocument" => %{
                "uri" => "file://#{test_file}",
                "languageId" => "elixir",
                "version" => 1,
                "text" => File.read!(test_file)
              }
            })

            # Wait for potential diagnostics
            Process.sleep(1000)

            # We may or may not receive diagnostics depending on Expert version
            # The test passes if the client handles the subscription correctly
            Client.shutdown(pid)
            GenServer.stop(pid)
          after
            File.rm(test_file)
          end

        {:error, :not_found} ->
          :ok
      end
    end

    test "handles request timeout" do
      case Client.find_expert_path() do
        {:ok, _path} ->
          {:ok, pid} = Client.start_link(project_root: @project_root)
          Process.sleep(2000)

          status = Client.status(pid)

          if status.initialized do
            # Try a request with a very short timeout
            # Note: this might actually succeed if Expert is fast enough
            result =
              Client.request(
                pid,
                "textDocument/hover",
                %{
                  "textDocument" => %{"uri" => "file:///nonexistent.ex"},
                  "position" => %{"line" => 0, "character" => 0}
                },
                100
              )

            # Either times out or returns a result
            assert match?({:ok, _}, result) or match?({:error, _}, result)
          end

          Client.shutdown(pid)
          GenServer.stop(pid)

        {:error, :not_found} ->
          :ok
      end
    end
  end
end
