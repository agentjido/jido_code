defmodule AgentJido.GithubIssueBotTest.PullRequest.PullRequestCoordinatorTest do
  @moduledoc """
  Tests for the PullRequestCoordinator and its sequential worker flow.

  Covers:
  - Sequential flow: Patch → Quality → PR Submit
  - Retry logic: Quality failures trigger patch retry
  - Max retries: Gives up after 3 attempts
  - Success path: PR created when quality passes
  """
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Signal
  alias AgentJido.GithubIssueBot.IssueRun.CoordinatorAgent

  # Issue number 42 - passes on first attempt
  @test_issue_pass %{
    repo: "test/repo",
    number: 42,
    title: "Bug: Agent state not persisting correctly",
    body: """
    ## Description
    When I try to persist agent state, it seems to lose some fields.

    ## Steps to Reproduce
    1. Create an agent with nested state
    2. Hibernate it
    3. Thaw it back
    4. Some nested fields are missing

    ## Expected Behavior
    All state should be preserved.

    ## Version
    - Elixir: 1.18
    - OTP: 27
    """,
    labels: ["bug"]
  }

  # Issue number 47 - fails first 2 attempts, passes on 3rd (ends in 7)
  @test_issue_retry %{
    repo: "test/repo",
    number: 47,
    title: "Bug: Flaky test in agent module",
    body: """
    ## Description
    Test intermittently fails with timeout.

    ## Version
    - Elixir: 1.18
    - OTP: 27
    """,
    labels: ["bug"]
  }

  # Issue number 49 - always fails (ends in 9)
  @test_issue_fail %{
    repo: "test/repo",
    number: 49,
    title: "Bug: Cannot reproduce locally",
    body: """
    ## Description
    Something is broken but we can't figure out what.

    ## Version
    - Elixir: 1.18
    - OTP: 27
    """,
    labels: ["bug"]
  }

  setup_all do
    :ok
  end

  describe "sequential flow - success on first attempt" do
    test "completes with PR when quality passes immediately" do
      run_id = "test-pass-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_pass}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 15_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      assert agent_state.phase == :completed
      assert agent_state.artifacts[:pull_request] != nil

      pr = agent_state.artifacts[:pull_request]
      assert pr.success == true
      assert pr.attempts == 1
      assert pr.pr_url != nil
      assert pr.pr_number != nil
    end

    test "patch result contains correct data" do
      run_id = "test-patch-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_pass}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 15_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      patch = server_state.agent.state.artifacts[:pull_request].patch

      assert patch.branch_name == "fix/issue-42"
      assert is_list(patch.files_changed)
      assert is_binary(patch.commit_sha)
    end

    test "quality result shows all checks passed" do
      run_id = "test-quality-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_pass}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 15_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      quality = server_state.agent.state.artifacts[:pull_request].quality

      assert quality.tests_passed == true
      assert quality.lint_passed == true
      assert quality.typecheck_passed == true
      assert quality.failures == []
    end
  end

  describe "retry flow - eventual success" do
    test "retries and succeeds on 3rd attempt for issue ending in 7" do
      run_id = "test-retry-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_retry}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            {:ok, %{agent: %{state: %{phase: :failed}}}} -> true
            _ -> false
          end
        end,
        timeout: 20_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      assert agent_state.phase == :completed
      pr = agent_state.artifacts[:pull_request]

      assert pr.success == true
      assert pr.attempts == 3
      assert pr.pr_url != nil

      # Should have attempt history
      assert length(pr.attempt_history) >= 1
    end
  end

  describe "max retry exhaustion" do
    test "fails after 3 attempts for issue ending in 9" do
      run_id = "test-fail-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_fail}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :failed}}}} -> true
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 20_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      assert agent_state.phase == :failed
      pr = agent_state.artifacts[:pull_request]

      assert pr.success == false
      assert pr.attempts == 3

      # No PR URL since it failed
      assert pr.pr_url == nil
      assert pr.pr_submit == %{}

      # Should have 3 failed attempts in history
      assert length(pr.attempt_history) == 3

      Enum.each(pr.attempt_history, fn entry ->
        assert entry.outcome == :failed
      end)
    end
  end

  describe "phase transitions" do
    test "phases progress correctly: patching → validating → submitting → completed" do
      run_id = "test-phases-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          AgentJido.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue_pass}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Should reach awaiting_pull_request (research must complete first)
      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: phase}}}} when phase in [:awaiting_pull_request, :completed] -> true
            _ -> false
          end
        end,
        timeout: 10_000
      )

      # Then complete
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
      assert server_state.agent.state.phase == :completed
    end
  end

  # Helper to wait for async conditions
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
