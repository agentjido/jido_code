defmodule JidoCode.GithubIssueBotTest.Research.ResearchCoordinatorTest do
  @moduledoc """
  Tests for the ResearchCoordinator and its worker agents.

  Covers:
  - ResearchCoordinator spawns all 4 workers
  - Each worker processes requests and emits results
  - Results are aggregated into a research report
  - Research report is emitted to parent
  """
  use ExUnit.Case, async: false

  alias Jido.AgentServer
  alias Jido.Signal
  alias JidoCode.GithubIssueBot.IssueRun.CoordinatorAgent

  @test_issue %{
    repo: "test/repo",
    number: 1,
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

    ## Actual Behavior
    Nested maps are flattened.

    ## Version
    - Elixir: 1.19
    - OTP: 27
    - Jido: 2.1.0
    """,
    labels: ["bug"]
  }

  setup_all do
    unless Process.whereis(JidoCode.Jido) do
      start_supervised!({JidoCode.Jido, []})
    end

    :ok
  end

  describe "full issue run with research phase" do
    test "coordinator progresses through triage and research phases" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      # Start the issue run
      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, agent} = AgentServer.call(pid, signal)

      # Should be awaiting triage
      assert agent.state.phase == :awaiting_triage

      # Wait for full completion (triage + research)
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

      # Verify final state
      assert agent_state.phase == :completed
      assert agent_state.run_id == run_id

      # Verify triage artifact
      assert agent_state.artifacts[:triage] != nil
      assert agent_state.artifacts[:triage].classification == :bug

      # Verify research artifact
      assert agent_state.artifacts[:research] != nil
      research = agent_state.artifacts[:research]

      # All 4 workers should have completed
      assert :code_search in research.workers_completed
      assert :reproduction in research.workers_completed
      assert :root_cause in research.workers_completed
      assert :pr_search in research.workers_completed

      # Each worker result should be present
      assert research.code_search != %{}
      assert research.reproduction != %{}
      assert research.root_cause != %{}
      assert research.pr_search != %{}
    end
  end

  describe "research worker outputs" do
    test "code_search extracts keywords and finds files" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

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
      code_search = server_state.agent.state.artifacts[:research].code_search

      # Should have extracted keywords
      assert is_list(code_search.keywords)
      assert length(code_search.keywords) > 0

      # Should have found files (mock)
      assert is_list(code_search.files)
      assert code_search.summary != nil
    end

    test "reproduction extracts steps and environment" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

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
      reproduction = server_state.agent.state.artifacts[:research].reproduction

      # Should detect repro steps
      assert reproduction.has_repro_steps == true

      # Should extract numbered steps
      assert is_list(reproduction.steps)
      assert length(reproduction.steps) >= 4

      # Should extract environment info
      assert reproduction.environment.elixir_version == "1.19"
      assert reproduction.environment.otp_version == "27"
    end

    test "root_cause provides hypothesis" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

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
      root_cause = server_state.agent.state.artifacts[:research].root_cause

      # Should have a hypothesis
      assert root_cause.hypothesis != nil
      assert root_cause.confidence in [:high, :medium, :low]

      # Should have evidence
      assert is_list(root_cause.evidence)
    end

    test "pr_search finds related items" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: @test_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

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
      pr_search = server_state.agent.state.artifacts[:research].pr_search

      # Should have search results structure
      assert is_list(pr_search.related_prs)
      assert is_list(pr_search.related_issues)
      assert pr_search.summary != nil
    end
  end

  describe "needs_info handling" do
    test "issue needing more info does not proceed to research" do
      run_id = "test-run-#{System.unique_integer([:positive])}"

      # Issue with minimal body - should trigger needs_info
      sparse_issue = %{
        repo: "test/repo",
        number: 2,
        title: "Something is broken",
        body: "Help",
        labels: ["bug"]
      }

      {:ok, pid} =
        Jido.start_agent(
          JidoCode.Jido,
          CoordinatorAgent,
          id: run_id
        )

      signal = Signal.new!("issue.start", %{run_id: run_id, issue: sparse_issue}, source: "/test")
      {:ok, _agent} = AgentServer.call(pid, signal)

      # Wait for triage to complete
      eventually(
        fn ->
          case AgentServer.state(pid) do
            {:ok, %{agent: %{state: %{phase: :needs_info}}}} -> true
            {:ok, %{agent: %{state: %{phase: :completed}}}} -> true
            _ -> false
          end
        end,
        timeout: 5_000
      )

      {:ok, server_state} = AgentServer.state(pid)
      agent_state = server_state.agent.state

      # Should have triage but NOT research
      assert agent_state.artifacts[:triage] != nil
      assert agent_state.artifacts[:triage].needs_info == true
      assert agent_state.artifacts[:research] == nil
      assert agent_state.phase == :needs_info
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
