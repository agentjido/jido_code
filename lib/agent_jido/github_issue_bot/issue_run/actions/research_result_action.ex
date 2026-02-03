defmodule AgentJido.GithubIssueBot.IssueRun.Actions.ResearchResultAction do
  @moduledoc """
  Handles "research.result" signal from research coordinator.

  Aggregates the research report into coordinator artifacts and spawns
  the PullRequestCoordinator to implement the fix and create a PR.
  """
  use Jido.Action,
    name: "research_result",
    schema: [
      run_id: [type: :string, required: true],
      completed_at: [type: :any, required: true],
      workers_completed: [type: {:list, :atom}, required: true],
      code_search: [type: :map, default: %{}],
      reproduction: [type: :map, default: %{}],
      root_cause: [type: :map, default: %{}],
      pr_search: [type: :map, default: %{}],
      summary: [type: :string, default: ""]
    ]

  alias Jido.Agent.Directive
  alias AgentJido.GithubIssueBot.PullRequest.PullRequestCoordinator

  require Logger

  def run(params, context) do
    run_id = params.run_id
    current_run_id = Map.get(context.state, :run_id)
    current_artifacts = Map.get(context.state, :artifacts, %{})

    cond do
      current_run_id != run_id ->
        Logger.warning("Received research result for wrong run: #{run_id} (expected #{current_run_id})")

        {:ok, %{}}

      Map.has_key?(current_artifacts, :research) ->
        Logger.debug("Ignoring duplicate research result for #{run_id}")
        {:ok, %{}}

      true ->
        Logger.info("Research complete for #{run_id}, spawning PullRequestCoordinator")

        research_artifact = %{
          completed_at: params.completed_at,
          workers_completed: params.workers_completed,
          code_search: params.code_search,
          reproduction: params.reproduction,
          root_cause: params.root_cause,
          pr_search: params.pr_search,
          summary: params.summary
        }

        issue = Map.get(context.state, :issue, %{})
        triage = Map.get(current_artifacts, :triage, %{})

        spawn_directive =
          Directive.spawn_agent(PullRequestCoordinator, :pull_request,
            meta: %{
              run_id: run_id,
              issue: issue,
              triage: triage,
              research: research_artifact
            }
          )

        {:ok,
         %{
           phase: :awaiting_pull_request,
           artifacts: Map.put(current_artifacts, :research, research_artifact)
         }, [spawn_directive]}
    end
  end
end
