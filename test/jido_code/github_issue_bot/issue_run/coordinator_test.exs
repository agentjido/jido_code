defmodule JidoCode.GithubIssueBotTest.IssueRun.CoordinatorTest do
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Signal
  alias JidoCode.GithubIssueBot.IssueRun.CoordinatorAgent

  @test_issue %{
    repo: "test/repo",
    number: 1,
    title: "Bug: something broken",
    body: """
    ## Steps to Reproduce
    1. Do the first thing
    2. Do the second thing
    3. Observe the error

    ## Version
    Elixir: 1.19
    OTP: 27
    """,
    labels: ["bug"]
  }

  setup_all do
    unless Process.whereis(JidoCode.Jido) do
      start_supervised!({JidoCode.Jido, []})
    end

    :ok
  end

  describe "coordinator spawns triage on issue.start" do
    test "phase becomes :awaiting_triage after start" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      assert agent.state.phase == :awaiting_triage
      assert agent.state.run_id == run_id
      assert agent.state.issue == @test_issue
    end
  end

  describe "full flow through research" do
    test "coordinator receives triage and research results" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Now waits for full completion (triage + research)
      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 10_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      assert agent_state.phase == :completed
      assert agent_state.artifacts[:triage] != nil
      assert agent_state.artifacts[:triage].classification == :bug
      # Research artifact should also be present now
      assert agent_state.artifacts[:research] != nil
    end
  end

  describe "idempotency" do
    test "duplicate triage results do not corrupt state" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Wait for full completion
      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 10_000
      )

      dupe_signal =
        Signal.new!(
          "triage.result",
          %{run_id: run_id, classification: :feature, needs_info: true, summary: "dupe"},
          source: "/test"
        )

      {:ok, _} = AgentServer.call(pid, dupe_signal)

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      assert agent_state.phase == :completed
      assert agent_state.artifacts[:triage].classification == :bug
    end
  end

  defp eventually(fun, opts) do
    timeout = Keyword.get(opts, :timeout, 1000)
    interval = Keyword.get(opts, :interval, 50)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_eventually(fun, interval, deadline)
  end

  defp do_eventually(fun, interval, deadline) do
    if fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= deadline do
        flunk("Condition not met within timeout")
      else
        Process.sleep(interval)
        do_eventually(fun, interval, deadline)
      end
    end
  end
end
