defmodule AgentJido.GithubIssueBot.Research.ResearchCoordinator do
  @moduledoc """
  Research coordinator that fans out to specialized worker agents.

  Spawns 4 parallel workers to research an issue:
  - CodeSearchAgent: Find relevant code in the repository
  - ReproductionAgent: Analyze reproduction steps from issue
  - RootCauseAgent: Hypothesize root cause based on findings
  - PRSearchAgent: Find related PRs and issues

  Aggregates results into a research_report artifact and emits to parent.

  ## Signal Flow

      research.request
          │
          ├── spawn CodeSearchAgent
          ├── spawn ReproductionAgent
          ├── spawn RootCauseAgent
          └── spawn PRSearchAgent
                    │
          (await all 4 results)
                    │
          research.result → parent

  """
  use Jido.Agent,
    name: "research_coordinator",
    schema: [
      # Tracking
      run_id: [type: :string, default: nil],
      status: [type: :atom, default: :idle],

      # Input from parent
      issue: [type: :map, default: %{}],
      triage: [type: :map, default: %{}],

      # Worker tracking - which workers have reported back
      pending_workers: [type: {:list, :atom}, default: []],
      completed_workers: [type: {:list, :atom}, default: []],

      # Aggregated results from workers
      worker_results: [type: :map, default: %{}]
    ]

  alias AgentJido.GithubIssueBot.Research.Actions.{
    StartResearchAction,
    WorkerResultAction,
    WorkerStartedAction
  }

  def signal_routes do
    [
      # Receive research request from parent coordinator
      {"research.request", StartResearchAction},

      # Handle child agent lifecycle
      {"jido.agent.child.started", WorkerStartedAction},

      # Receive results from each worker type
      {"code_search.result", WorkerResultAction},
      {"reproduction.result", WorkerResultAction},
      {"root_cause.result", WorkerResultAction},
      {"pr_search.result", WorkerResultAction}
    ]
  end
end
