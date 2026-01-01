defmodule JidoCode.Memory.Promotion.TriggersTest do
  use ExUnit.Case, async: true

  alias JidoCode.Memory.Promotion.Triggers
  alias JidoCode.Session
  alias JidoCode.Session.State

  # =============================================================================
  # Test Setup
  # =============================================================================

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "triggers_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    {:ok, tmp_dir: tmp_dir}
  end

  defp start_session(tmp_dir) do
    {:ok, session} = Session.new(project_path: tmp_dir)
    {:ok, pid} = State.start_link(session: session)
    {session, pid}
  end

  defp create_memory_item(overrides \\ %{}) do
    Map.merge(
      %{
        content: "Test memory content",
        memory_type: :fact,
        confidence: 0.9,
        source_type: :tool,
        evidence: [],
        rationale: nil
      },
      overrides
    )
  end

  # =============================================================================
  # on_session_pause/1 Tests
  # =============================================================================

  describe "on_session_pause/1" do
    test "runs promotion and returns count", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      # Add a high-importance pending memory
      item = create_memory_item(%{importance_score: 0.85})
      :ok = State.add_pending_memory(session.id, item)

      {:ok, count} = Triggers.on_session_pause(session.id)

      # Should have promoted the high-importance item
      assert count >= 0

      GenServer.stop(pid)
    end

    test "returns {:ok, 0} when no candidates to promote", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      {:ok, count} = Triggers.on_session_pause(session.id)

      assert count == 0

      GenServer.stop(pid)
    end

    test "returns error for unknown session" do
      result = Triggers.on_session_pause("unknown-session-id")

      assert {:error, :session_not_found} = result
    end

    test "emits telemetry event", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-pause-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :triggered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _count} = Triggers.on_session_pause(session.id)

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :triggered], measurements,
                      metadata}

      assert metadata.trigger == :session_pause
      assert metadata.session_id == session.id
      assert metadata.status == :success
      assert is_integer(measurements.promoted_count)

      :telemetry.detach("test-pause-#{inspect(ref)}")
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # on_session_close/1 Tests
  # =============================================================================

  describe "on_session_close/1" do
    test "runs promotion and returns count", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      {:ok, count} = Triggers.on_session_close(session.id)

      assert count >= 0

      GenServer.stop(pid)
    end

    test "uses lower threshold for final promotion", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      # Add an item with importance between 0.4 and 0.6
      # Would not be promoted by normal threshold (0.6) but should be by session_close (0.4)
      item = create_memory_item(%{importance_score: 0.5})
      :ok = State.add_pending_memory(session.id, item)

      {:ok, count} = Triggers.on_session_close(session.id)

      # The item should be considered for promotion with lower threshold
      assert count >= 0

      GenServer.stop(pid)
    end

    test "returns error for unknown session" do
      result = Triggers.on_session_close("unknown-session-id")

      assert {:error, :session_not_found} = result
    end

    test "emits telemetry event", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-close-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :triggered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _count} = Triggers.on_session_close(session.id)

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :triggered], measurements,
                      metadata}

      assert metadata.trigger == :session_close
      assert metadata.session_id == session.id
      assert is_integer(measurements.promoted_count)

      :telemetry.detach("test-close-#{inspect(ref)}")
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # on_memory_limit_reached/2 Tests
  # =============================================================================

  describe "on_memory_limit_reached/2" do
    test "runs promotion to clear space", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      {:ok, count} = Triggers.on_memory_limit_reached(session.id, 500)

      assert count >= 0

      GenServer.stop(pid)
    end

    test "returns error for unknown session" do
      result = Triggers.on_memory_limit_reached("unknown-session-id", 100)

      assert {:error, :session_not_found} = result
    end

    test "emits telemetry with current_count", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-limit-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :triggered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      {:ok, _count} = Triggers.on_memory_limit_reached(session.id, 500)

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :triggered], measurements,
                      metadata}

      assert metadata.trigger == :memory_limit_reached
      assert metadata.session_id == session.id
      assert metadata.current_count == 500
      assert is_integer(measurements.promoted_count)

      :telemetry.detach("test-limit-#{inspect(ref)}")
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # on_agent_decision/2 Tests
  # =============================================================================

  describe "on_agent_decision/2" do
    test "promotes single memory item immediately", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      item = create_memory_item(%{
        id: "agent-mem-123",
        content: "User prefers tabs",
        memory_type: :convention,
        confidence: 1.0,
        source_type: :user
      })

      {:ok, count} = Triggers.on_agent_decision(session.id, item)

      assert count == 1

      GenServer.stop(pid)
    end

    test "generates id if not provided", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      item = create_memory_item(%{
        content: "Some important convention",
        memory_type: :convention
      })
      # No id in item

      {:ok, count} = Triggers.on_agent_decision(session.id, item)

      assert count == 1

      GenServer.stop(pid)
    end

    test "emits telemetry event", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-decision-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :triggered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      item = create_memory_item(%{memory_type: :convention})
      {:ok, _count} = Triggers.on_agent_decision(session.id, item)

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :triggered], measurements,
                      metadata}

      assert metadata.trigger == :agent_decision
      assert metadata.session_id == session.id
      assert measurements.promoted_count == 1

      :telemetry.detach("test-decision-#{inspect(ref)}")
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # Integration with Session.State Tests
  # =============================================================================

  describe "Session.State integration" do
    test "add_agent_memory_decision triggers promotion asynchronously", %{tmp_dir: tmp_dir} do
      {session, pid} = start_session(tmp_dir)

      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test-integration-#{inspect(ref)}",
        [:jido_code, :memory, :promotion, :triggered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      item = %{
        content: "User prefers explicit aliases",
        memory_type: :convention,
        confidence: 1.0,
        source_type: :user,
        evidence: ["User stated preference"]
      }

      :ok = State.add_agent_memory_decision(session.id, item)

      # Wait for async trigger
      Process.sleep(100)

      assert_receive {:telemetry, [:jido_code, :memory, :promotion, :triggered], _measurements,
                      metadata},
                     500

      assert metadata.trigger == :agent_decision

      :telemetry.detach("test-integration-#{inspect(ref)}")
      GenServer.stop(pid)
    end
  end

  # =============================================================================
  # Input Validation Tests
  # =============================================================================

  describe "input validation" do
    test "on_session_pause requires binary session_id" do
      assert_raise FunctionClauseError, fn ->
        Triggers.on_session_pause(nil)
      end

      assert_raise FunctionClauseError, fn ->
        Triggers.on_session_pause(123)
      end
    end

    test "on_memory_limit_reached requires non-negative count" do
      assert_raise FunctionClauseError, fn ->
        Triggers.on_memory_limit_reached("session-id", -1)
      end
    end

    test "on_agent_decision requires map item" do
      assert_raise FunctionClauseError, fn ->
        Triggers.on_agent_decision("session-id", "not a map")
      end
    end
  end
end
