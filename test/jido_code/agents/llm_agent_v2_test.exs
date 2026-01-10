defmodule JidoCode.Agents.LLMAgent.V2Test do
  use ExUnit.Case, async: false

  alias JidoCode.Agents.LLMAgent.V2
  alias Jido.AgentServer

  @moduletag :llm_agent_v2

  setup_all do
    # Start a Jido instance once for all tests
    start_supervised!(
      {Task.Supervisor, name: JidoTest.TaskSupervisor, max_children: 100}
    )

    start_supervised!(
      {Registry, keys: :unique, name: JidoTest.Registry}
    )

    start_supervised!(
      {DynamicSupervisor,
       name: JidoTest.AgentSupervisor, strategy: :one_for_one, max_restarts: 1000, max_seconds: 5}
    )

    :ok
  end

  setup do
    # Trap exits in test process to avoid test crashes
    Process.flag(:trap_exit, true)
    :ok
  end

  defp stop_agent(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      GenServer.stop(pid, :normal, 1000)
    end

    :ok
  end

  defp stop_agent(_), do: :ok

  describe "strategy listing" do
    test "list_strategies/0 returns all available strategies" do
      strategies = V2.list_strategies()

      assert :cot in strategies
      assert :react in strategies
      assert :tot in strategies
      assert :got in strategies
      assert :trm in strategies
      assert :adaptive in strategies
    end

    test "list_strategies/0 returns 6 strategies" do
      strategies = V2.list_strategies()
      assert length(strategies) == 6
    end
  end

  describe "strategy names" do
    test "strategy_name/1 returns human-readable names" do
      assert "Chain of Thought" = V2.strategy_name(:cot)
      assert "ReAct (Reason-Act)" = V2.strategy_name(:react)
      assert "Tree of Thoughts" = V2.strategy_name(:tot)
      assert "Graph of Thoughts" = V2.strategy_name(:got)
      assert "Tiny-Recursive-Model" = V2.strategy_name(:trm)
      assert "Adaptive (auto-selecting)" = V2.strategy_name(:adaptive)
      assert "Unknown" = V2.strategy_name(:unknown)
    end
  end

  describe "strategy descriptions" do
    test "strategy_description/1 returns descriptions" do
      description = V2.strategy_description(:cot)
      assert is_binary(description)
      assert String.contains?(description, "reasoning")

      description = V2.strategy_description(:react)
      assert is_binary(description)
      assert String.contains?(description, "tool")

      description = V2.strategy_description(:adaptive)
      assert is_binary(description)
      assert String.contains?(description, "Automatically") or String.contains?(description, "automatically")
    end

    test "strategy_description/1 handles unknown strategy" do
      assert "Unknown strategy" = V2.strategy_description(:unknown)
    end
  end

  describe "system_prompt" do
    test "system_prompt/0 returns a non-empty string" do
      prompt = V2.system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
      assert String.contains?(prompt, "JidoCode")
    end
  end

  describe "AgentServer integration" do
    test "can start agent with minimal state" do
      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: "test_llm_agent_#{System.unique_integer()}",
          jido: JidoTest
        )

      assert Process.alive?(pid)
      stop_agent(pid)
    end

    test "can start agent with initial state" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest,
          initial_state: %{
            session_id: "test-session-123",
            project_root: "/tmp/test"
          }
        )

      assert Process.alive?(pid)

      # Verify state was set
      {:ok, %{agent: agent}} = AgentServer.state(pid)
      assert agent.state.session_id == "test-session-123"
      assert agent.state.project_root == "/tmp/test"

      stop_agent(pid)
    end

    test "agent has correct default strategy" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :adaptive = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "get_strategy/1 returns adaptive by default" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :adaptive = V2.get_strategy(pid)

      stop_agent(pid)
    end
  end

  describe "set_strategy/2" do
    test "can change strategy to cot" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :ok = V2.set_strategy(pid, :cot)
      assert :cot = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "can change strategy to react" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :ok = V2.set_strategy(pid, :react)
      assert :react = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "can change strategy to tot" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :ok = V2.set_strategy(pid, :tot)
      assert :tot = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "can change strategy to got" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :ok = V2.set_strategy(pid, :got)
      assert :got = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "can change strategy to trm" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert :ok = V2.set_strategy(pid, :trm)
      assert :trm = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "can change strategy to adaptive" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      # First change to something else
      assert :ok = V2.set_strategy(pid, :cot)
      assert :cot = V2.get_strategy(pid)

      # Change back to adaptive
      assert :ok = V2.set_strategy(pid, :adaptive)
      assert :adaptive = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "returns error for invalid strategy" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert {:error, {:unknown_strategy, :invalid_strategy}} =
               V2.set_strategy(pid, :invalid_strategy)

      # Strategy should remain unchanged
      assert :adaptive = V2.get_strategy(pid)

      stop_agent(pid)
    end

    test "returns error for unknown strategy atom" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      assert {:error, {:unknown_strategy, :foo}} =
               V2.set_strategy(pid, :foo)

      stop_agent(pid)
    end

    test "debug: check state after set_strategy" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      # Check initial state
      {:ok, initial_state} = AgentServer.state(pid)
      IO.inspect(initial_state.agent.state.current_strategy, label: "Initial strategy")

      # Set strategy
      result = V2.set_strategy(pid, :cot)
      IO.inspect(result, label: "set_strategy result")

      # Give it time to process
      Process.sleep(100)

      # Check state after
      {:ok, final_state} = AgentServer.state(pid)
      IO.inspect(final_state.agent.state.current_strategy, label: "Final strategy")

      stop_agent(pid)
    end
  end

  describe "chat/2" do
    test "accepts chat message with opts" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      # This will queue the message, but won't execute without actual LLM
      assert :ok = V2.chat(pid, "Hello, world!")

      stop_agent(pid)
    end

    test "accepts chat message with strategy override" do
      agent_id = "test_llm_agent_#{System.unique_integer()}"

      {:ok, pid} =
        AgentServer.start(
          agent: V2,
          id: agent_id,
          jido: JidoTest
        )

      # Send message with strategy override
      assert :ok = V2.chat(pid, "Explain Elixir", strategy: :cot)

      stop_agent(pid)
    end
  end
end
