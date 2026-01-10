defmodule JidoCode.Agents.TaskAgent.V2Test do
  use ExUnit.Case, async: false

  alias JidoCode.Agents.TaskAgent.V2

  @moduletag :task_agent_v2

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  describe "system_prompt" do
    test "system_prompt/0 returns a non-empty string" do
      prompt = V2.system_prompt()
      assert is_binary(prompt)
      assert String.length(prompt) > 0
      assert String.contains?(prompt, "sub-agent")
    end
  end

  describe "start_link/1" do
    test "starts with required options" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something"
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "returns error for missing task_id" do
      assert {:error, "Missing required option: task_id"} =
               V2.start_link(
                 description: "Test task",
                 prompt: "Do something"
               )
    end

    test "returns error for missing description" do
      assert {:error, "Missing required option: description"} =
               V2.start_link(
                 task_id: "task_123",
                 prompt: "Do something"
               )
    end

    test "returns error for missing prompt" do
      assert {:error, "Missing required option: prompt"} =
               V2.start_link(
                 task_id: "task_123",
                 description: "Test task"
               )
    end

    test "returns error for empty task_id" do
      assert {:error, "Option task_id must be a non-empty string"} =
               V2.start_link(
                 task_id: "",
                 description: "Test task",
                 prompt: "Do something"
               )
    end

    test "returns error for empty description" do
      assert {:error, "Option description must be a non-empty string"} =
               V2.start_link(
                 task_id: "task_123",
                 description: "",
                 prompt: "Do something"
               )
    end

    test "returns error for empty prompt" do
      assert {:error, "Option prompt must be a non-empty string"} =
               V2.start_link(
                 task_id: "task_123",
                 description: "Test task",
                 prompt: ""
               )
    end

    test "accepts optional provider option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 provider: :openai
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "accepts optional model option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 model: "gpt-4o"
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "accepts optional session_id option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 session_id: "session-abc"
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "accepts optional temperature option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 temperature: 0.5
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "accepts optional max_tokens option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 max_tokens: 1024
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end

    test "accepts optional name option" do
      task_id = "task_#{System.unique_integer()}"

      assert {:ok, pid} =
               V2.start_link(
                 task_id: task_id,
                 description: "Test task",
                 prompt: "Do something",
                 name: :my_named_task
               )

      assert Process.alive?(pid)
      Jido.AgentServer.stop(pid)
    end
  end

  describe "status/1" do
    test "returns status map for running agent" do
      task_id = "task_#{System.unique_integer()}"

      {:ok, pid} =
        V2.start_link(
          task_id: task_id,
          description: "Test task",
          prompt: "Do something"
        )

      status = V2.status(pid)

      assert status.task_id == task_id
      assert status.description == "Test task"
      assert status.status == :ready
      assert is_nil(status.result)
      assert is_nil(status.session_id)

      Jido.AgentServer.stop(pid)
    end

    test "includes session_id in status when provided" do
      task_id = "task_#{System.unique_integer()}"

      {:ok, pid} =
        V2.start_link(
          task_id: task_id,
          description: "Test task",
          prompt: "Do something",
          session_id: "session-xyz"
        )

      status = V2.status(pid)
      assert status.session_id == "session-xyz"

      Jido.AgentServer.stop(pid)
    end

    test "returns error map for non-existent pid" do
      status = V2.status(self())
      assert status.error == :not_found
    end
  end

  describe "AgentServer state" do
    test "initial state has correct default values" do
      task_id = "task_#{System.unique_integer()}"

      {:ok, pid} =
        V2.start_link(
          task_id: task_id,
          description: "Test task",
          prompt: "Do something"
        )

      {:ok, state} = Jido.AgentServer.state(pid)

      assert state.agent.state.task_id == task_id
      assert state.agent.state.description == "Test task"
      assert state.agent.state.prompt == "Do something"
      assert state.agent.state.status == :ready
      assert state.agent.state.provider == :anthropic
      assert state.agent.state.model == "anthropic:claude-sonnet-4-20250514"
      assert state.agent.state.temperature == 0.3
      assert state.agent.state.max_tokens == 2048

      Jido.AgentServer.stop(pid)
    end

    test "initial state preserves provided values" do
      task_id = "task_#{System.unique_integer()}"

      {:ok, pid} =
        V2.start_link(
          task_id: task_id,
          description: "Custom task",
          prompt: "Custom prompt",
          provider: :openai,
          model: "gpt-4o",
          temperature: 0.7,
          max_tokens: 4096,
          session_id: "custom-session"
        )

      {:ok, state} = Jido.AgentServer.state(pid)

      assert state.agent.state.task_id == task_id
      assert state.agent.state.description == "Custom task"
      assert state.agent.state.prompt == "Custom prompt"
      assert state.agent.state.provider == :openai
      assert state.agent.state.model == "gpt-4o"
      assert state.agent.state.temperature == 0.7
      assert state.agent.state.max_tokens == 4096
      assert state.agent.state.session_id == "custom-session"

      Jido.AgentServer.stop(pid)
    end
  end
end
