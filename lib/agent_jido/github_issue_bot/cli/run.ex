defmodule AgentJido.GithubIssueBot.CLI.Run do
  @moduledoc """
  CLI runner for the GitHub Issue Bot.

  Usage:
      mix run -e "AgentJido.GithubIssueBot.CLI.Run.run()"
      iex -S mix run -e "AgentJido.GithubIssueBot.CLI.Run.run()"

  Or with options:
      mix run -e "AgentJido.GithubIssueBot.CLI.Run.run(run_id: \\"test-run\\")"
  """

  alias AgentJido.GithubIssueBot.IssueRun.CoordinatorAgent
  alias Jido.AgentServer
  alias Jido.Signal

  require Logger

  @default_issue %{
    repo: "agentjido/jido",
    number: 123,
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
    - Elixir: 1.18
    - OTP: 27
    - Jido: 2.0.0-rc.2
    """,
    labels: ["bug"]
  }

  def run(opts \\ []) do
    Logger.configure(level: :debug)

    run_id = Keyword.get(opts, :run_id, "run-#{System.system_time(:millisecond)}")
    issue = Keyword.get(opts, :issue, @default_issue)
    timeout = Keyword.get(opts, :timeout, 30_000)

    Logger.info("Starting GitHub Issue Bot run: #{run_id}")
    Logger.debug("Issue: #{inspect(issue, pretty: true)}")

    {:ok, _} = start_jido()

    {:ok, coord_pid} =
      Jido.start_agent(
        AgentJido.Jido,
        CoordinatorAgent,
        id: run_id
      )

    Logger.info("Coordinator started: #{inspect(coord_pid)}")

    signal = Signal.new!("issue.start", %{run_id: run_id, issue: issue}, source: "/cli")
    {:ok, _agent} = AgentServer.call(coord_pid, signal)

    Logger.info("Issue start signal sent, awaiting completion...")

    case Jido.await(coord_pid, timeout) do
      {:ok, %{status: :completed}} ->
        Logger.info("✓ Run completed successfully!")
        {:ok, server_state} = AgentServer.state(coord_pid)
        agent_state = server_state.agent.state
        print_artifacts(agent_state.artifacts)
        {:ok, agent_state}

      {:ok, %{status: status}} ->
        Logger.warning("Run ended with status: #{status}")
        {:ok, server_state} = AgentServer.state(coord_pid)
        agent_state = server_state.agent.state
        print_state(agent_state)
        {:ok, agent_state}

      {:error, {:timeout, details}} ->
        Logger.error("Run timed out after #{timeout}ms")
        Logger.debug("Timeout details: #{inspect(details)}")
        {:error, :timeout}

      {:error, :timeout} ->
        Logger.error("Run timed out after #{timeout}ms")
        {:error, :timeout}

      other ->
        Logger.error("Unexpected result: #{inspect(other)}")
        other
    end
  end

  def run_interactive(opts \\ []) do
    result = run(opts)
    IO.puts("\n--- Run complete. Entering IEx. ---")
    IO.puts("Coordinator is available in the registry as the run_id.")
    result
  end

  defp start_jido do
    case AgentJido.Jido.start_link() do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
    end
  end

  defp print_artifacts(artifacts) do
    IO.puts("\n=== Artifacts ===")

    Enum.each(artifacts, fn {name, artifact} ->
      IO.puts("\n--- #{name} ---")
      IO.puts(inspect(artifact, pretty: true, limit: :infinity))
    end)
  end

  defp print_state(state) do
    IO.puts("\n=== Final State ===")
    IO.puts("Phase: #{state.phase}")
    IO.puts("Run ID: #{state.run_id}")

    if map_size(state.artifacts) > 0 do
      print_artifacts(state.artifacts)
    end

    if state.errors != [] do
      IO.puts("\n--- Errors ---")
      Enum.each(state.errors, fn error -> IO.puts(inspect(error)) end)
    end
  end
end
