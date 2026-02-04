defmodule AgentJido.GithubIssueBot.IssueRun.Actions.StartRunAction do
  @moduledoc """
  Handles "issue.start" signal.

  Sets up the run and spawns the triage agent.
  """
  use Jido.Action,
    name: "start_run",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true]
    ]

  alias AgentJido.GithubIssueBot.Triage.TriageAgent
  alias Jido.Agent.Directive

  require Logger

  def run(%{run_id: run_id, issue: issue}, _context) do
    Logger.debug("Starting issue run: #{run_id}")

    spawn_directive =
      Directive.spawn_agent(TriageAgent, :triage, meta: %{run_id: run_id, issue: issue})

    {:ok,
     %{
       run_id: run_id,
       issue: issue,
       phase: :awaiting_triage
     }, [spawn_directive]}
  end
end
