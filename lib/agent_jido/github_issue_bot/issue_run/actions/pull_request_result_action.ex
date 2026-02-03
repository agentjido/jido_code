defmodule AgentJido.GithubIssueBot.IssueRun.Actions.PullRequestResultAction do
  @moduledoc """
  Handles "pull_request.result" signal from PullRequestCoordinator.

  Aggregates the pull request results into coordinator artifacts
  and marks the issue run as completed.
  """
  use Jido.Action,
    name: "pull_request_result",
    schema: [
      run_id: [type: :string, required: true],
      completed_at: [type: :any, required: true],
      success: [type: :boolean, required: true],
      attempts: [type: :integer, default: 1],
      workers_completed: [type: {:list, :atom}, default: []],
      patch: [type: :map, default: %{}],
      quality: [type: :map, default: %{}],
      pr_submit: [type: :map, default: %{}],
      pr_url: [type: :any, default: nil],
      pr_number: [type: :any, default: nil],
      attempt_history: [type: {:list, :map}, default: []],
      summary: [type: :string, default: ""]
    ]

  require Logger

  def run(params, context) do
    run_id = params.run_id
    current_run_id = Map.get(context.state, :run_id)
    current_artifacts = Map.get(context.state, :artifacts, %{})

    cond do
      current_run_id != run_id ->
        Logger.warning("Received pull_request result for wrong run: #{run_id} (expected #{current_run_id})")

        {:ok, %{}}

      Map.has_key?(current_artifacts, :pull_request) ->
        Logger.debug("Ignoring duplicate pull_request result for #{run_id}")
        {:ok, %{}}

      true ->
        success = params.success
        phase = if success, do: :completed, else: :failed
        status = if success, do: :completed, else: :failed

        if success do
          Logger.info("Pull request created for #{run_id}: PR ##{params.pr_number}")
        else
          Logger.warning("Pull request failed for #{run_id} after #{params.attempts} attempts")
        end

        pull_request_artifact = %{
          completed_at: params.completed_at,
          success: success,
          attempts: params.attempts,
          workers_completed: params.workers_completed,
          patch: params.patch,
          quality: params.quality,
          pr_submit: params.pr_submit,
          pr_url: params.pr_url,
          pr_number: params.pr_number,
          attempt_history: params.attempt_history,
          summary: params.summary
        }

        {:ok,
         %{
           phase: phase,
           status: status,
           artifacts: Map.put(current_artifacts, :pull_request, pull_request_artifact)
         }}
    end
  end
end
