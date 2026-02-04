defmodule AgentJido.GithubIssueBot.Research.Actions.StartResearchAction do
  @moduledoc """
  Handles "research.request" signal.

  Spawns all 4 research workers in parallel:
  - CodeSearchAgent
  - ReproductionAgent
  - RootCauseAgent
  - PRSearchAgent

  Each worker will receive a work request once started (via WorkerStartedAction).
  """
  use Jido.Action,
    name: "start_research",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true]
    ]

  alias AgentJido.GithubIssueBot.Research.Workers.{
    CodeSearchAgent,
    PRSearchAgent,
    ReproductionAgent,
    RootCauseAgent
  }

  alias Jido.Agent.Directive

  require Logger

  # Workers to spawn - each gets a tag for identification
  @workers [
    {CodeSearchAgent, :code_search},
    {ReproductionAgent, :reproduction},
    {RootCauseAgent, :root_cause},
    {PRSearchAgent, :pr_search}
  ]

  def run(%{run_id: run_id, issue: issue, triage: triage}, _context) do
    Logger.debug("Starting research for run: #{run_id}")

    # Build spawn directives for all workers
    spawn_directives =
      Enum.map(@workers, fn {agent_module, tag} ->
        Directive.spawn_agent(agent_module, tag,
          meta: %{
            run_id: run_id,
            issue: issue,
            triage: triage
          }
        )
      end)

    # Track which workers we're waiting for
    pending_workers = Enum.map(@workers, fn {_mod, tag} -> tag end)

    {:ok,
     %{
       run_id: run_id,
       issue: issue,
       triage: triage,
       status: :researching,
       pending_workers: pending_workers,
       completed_workers: [],
       worker_results: %{}
     }, spawn_directives}
  end
end
