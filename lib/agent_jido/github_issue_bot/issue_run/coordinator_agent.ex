defmodule AgentJido.GithubIssueBot.IssueRun.CoordinatorAgent do
  @moduledoc """
  Coordinator agent for processing a single GitHub issue.

  Owns the full lifecycle of one issue run:
  1. Receives issue payload
  2. Spawns triage agent → classifies issue
  3. Spawns research coordinator → gathers context
  4. Spawns pull request coordinator → implements fix, validates, creates PR

  ## Signal Flow

      issue.start
          │
          └── spawn TriageAgent
                  │
          triage.result
                  │
                  └── spawn ResearchCoordinator
                          │
                  research.result
                          │
                          └── spawn PullRequestCoordinator
                                  │
                          pull_request.result
                                  │
                                  └── :completed

  """
  use Jido.Agent,
    name: "issue_run_coordinator",
    schema: [
      run_id: [type: :string, default: nil],
      # Phases: :idle → :awaiting_triage → :awaiting_research → :awaiting_pull_request → :completed
      phase: [type: :atom, default: :idle],
      issue: [type: :map, default: %{}],
      children: [type: :map, default: %{}],
      artifacts: [type: :map, default: %{}],
      errors: [type: {:list, :any}, default: []]
    ]

  alias AgentJido.GithubIssueBot.IssueRun.Actions.{
    ChildStartedAction,
    PullRequestResultAction,
    ResearchResultAction,
    StartRunAction,
    TriageResultAction
  }

  def signal_routes do
    [
      # Phase 1: Start and triage
      {"issue.start", StartRunAction},
      {"jido.agent.child.started", ChildStartedAction},
      {"triage.result", TriageResultAction},

      # Phase 2: Research
      {"research.result", ResearchResultAction},

      # Phase 3: Pull Request
      {"pull_request.result", PullRequestResultAction}
    ]
  end
end
