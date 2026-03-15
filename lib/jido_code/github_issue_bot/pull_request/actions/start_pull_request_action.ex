defmodule JidoCode.GithubIssueBot.PullRequest.Actions.StartPullRequestAction do
  @moduledoc """
  Handles "pull_request.request" signal.

  Initiates the sequential fix flow by spawning PatchAgent first.
  The flow continues: Patch → Quality → (retry?) → PR Submit

  ## Flow

  1. Spawns PatchAgent to create the fix
  2. PatchResultAction will spawn QualityAgent
  3. QualityResultAction will either:
     - Spawn PRSubmitAgent (if quality passes)
     - Spawn PatchAgent again (if quality fails, attempts < max)
     - Emit failure (if quality fails, attempts >= max)
  """
  use Jido.Action,
    name: "start_pull_request",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true],
      research: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias JidoCode.GithubIssueBot.PullRequest.Workers.PatchAgent

  require Logger

  @max_attempts 3

  def run(%{run_id: run_id, issue: issue, triage: triage, research: research}, _context) do
    Logger.info("Starting pull request flow for run: #{run_id} (attempt 1/#{@max_attempts})")

    # Spawn only PatchAgent first - sequential flow
    spawn_directive =
      Directive.spawn_agent(PatchAgent, :patch,
        opts: %{id: worker_agent_id(run_id, :patch, 1)},
        meta: %{
          run_id: run_id,
          issue: issue,
          triage: triage,
          research: research,
          attempt: 1
        }
      )

    {:ok,
     %{
       run_id: run_id,
       issue: issue,
       triage: triage,
       research: research,
       status: :creating_pr,
       phase: :patching,
       attempt: 1,
       max_attempts: @max_attempts,
       patch_result: %{},
       quality_result: %{},
       pr_submit_result: %{},
       attempt_history: []
     }, [spawn_directive]}
  end

  defp worker_agent_id(run_id, worker_type, attempt)
       when is_binary(run_id) and is_atom(worker_type) and is_integer(attempt) do
    "#{run_id}/#{worker_type}/#{attempt}"
  end
end
