defmodule AgentJido.GithubIssueBot.PullRequest.PullRequestCoordinator do
  @moduledoc """
  Pull Request coordinator that orchestrates the fix → validate → submit flow.

  Implements the sequential ImplementAndValidate pattern with retry:
  1. PatchAgent creates the fix
  2. QualityAgent validates it
  3. If quality fails and attempts < max, retry from step 1
  4. PRSubmitAgent submits if quality passes

  ## Signal Flow

      pull_request.request
          │
          └── spawn PatchAgent
                  │
              patch.result
                  │
                  └── spawn QualityAgent
                          │
                      quality.result
                          │
                          ├── (pass) → spawn PRSubmitAgent
                          │                   │
                          │           pr_submit.result
                          │                   │
                          │           pull_request.result → parent
                          │
                          └── (fail, attempts < 3) → spawn PatchAgent (retry)
                          │
                          └── (fail, attempts >= 3) → pull_request.result (failed)

  ## State Machine

  Phases: :idle → :patching → :validating → :submitting → :completed/:failed

  """
  use Jido.Agent,
    name: "pull_request_coordinator",
    schema: [
      # Tracking
      run_id: [type: :string, default: nil],
      status: [type: :atom, default: :idle],

      # Sequential phase: :idle → :patching → :validating → :submitting → :completed/:failed
      phase: [type: :atom, default: :idle],

      # Retry tracking
      attempt: [type: :integer, default: 0],
      max_attempts: [type: :integer, default: 3],

      # Input from parent
      issue: [type: :map, default: %{}],
      triage: [type: :map, default: %{}],
      research: [type: :map, default: %{}],

      # Results from each phase (accumulated across retries)
      patch_result: [type: :map, default: %{}],
      quality_result: [type: :map, default: %{}],
      pr_submit_result: [type: :map, default: %{}],

      # History of attempts for debugging
      attempt_history: [type: {:list, :map}, default: []]
    ]

  alias AgentJido.GithubIssueBot.PullRequest.Actions.{
    PatchResultAction,
    PRSubmitResultAction,
    QualityResultAction,
    StartPullRequestAction,
    WorkerStartedAction
  }

  def signal_routes do
    [
      # Receive pull request request from parent coordinator
      {"pull_request.request", StartPullRequestAction},

      # Handle child agent lifecycle
      {"jido.agent.child.started", WorkerStartedAction},

      # Sequential results - each triggers the next phase
      {"patch.result", PatchResultAction},
      {"quality.result", QualityResultAction},
      {"pr_submit.result", PRSubmitResultAction}
    ]
  end
end
