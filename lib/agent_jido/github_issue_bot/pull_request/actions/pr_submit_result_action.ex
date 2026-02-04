defmodule AgentJido.GithubIssueBot.PullRequest.Actions.PRSubmitResultAction do
  @moduledoc """
  Handles "pr_submit.result" signal from PRSubmitAgent.

  Aggregates all results and emits the final pull_request.result to parent.
  This is the happy path completion of the PR flow.
  """
  use Jido.Action,
    name: "pr_submit_result",
    schema: [
      run_id: [type: :string, required: true],
      worker_type: [type: :atom, required: true],
      result: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, worker_type: :pr_submit, result: result}, context) do
    current_run_id = Map.get(context.state, :run_id)
    current_phase = Map.get(context.state, :phase)
    attempt = Map.get(context.state, :attempt, 1)
    attempt_history = Map.get(context.state, :attempt_history, [])

    cond do
      current_run_id != run_id ->
        Logger.warning("Received pr_submit result for wrong run: #{run_id}")
        {:ok, %{}}

      current_phase != :submitting ->
        Logger.warning("Received pr_submit result in wrong phase: #{current_phase}")
        {:ok, %{}}

      true ->
        Logger.info("PR submitted for #{run_id}: #{result.pr_url}")

        patch_result = Map.get(context.state, :patch_result, %{})
        quality_result = Map.get(context.state, :quality_result, %{})

        # Build success report
        success_report = %{
          run_id: run_id,
          completed_at: DateTime.utc_now(),
          success: true,
          attempts: attempt,
          workers_completed: [:patch, :quality, :pr_submit],

          # Individual results
          patch: patch_result,
          quality: quality_result,
          pr_submit: result,

          # PR details for easy access
          pr_url: Map.get(result, :pr_url),
          pr_number: Map.get(result, :pr_number),

          # History
          attempt_history: attempt_history,

          # Summary
          summary: build_summary(patch_result, result, attempt)
        }

        result_signal =
          Signal.new!(
            "pull_request.result",
            success_report,
            source: "/pull_request_coordinator"
          )

        emit_directive = Directive.emit_to_parent(context.agent, result_signal)

        {:ok,
         %{
           phase: :completed,
           status: :completed,
           pr_submit_result: result
         }, [emit_directive]}
    end
  end

  def run(%{worker_type: other}, _context) do
    Logger.warning("Unexpected worker type in pr_submit result: #{inspect(other)}")
    {:ok, %{}}
  end

  defp build_summary(patch, pr_submit, attempt) do
    branch = Map.get(patch, :branch_name, "unknown")
    files_count = length(Map.get(patch, :files_changed, []))
    pr_number = Map.get(pr_submit, :pr_number, "?")

    attempt_note = if attempt > 1, do: " (after #{attempt} attempts)", else: ""

    "PR ##{pr_number} created on branch #{branch} with #{files_count} file(s) changed. All quality checks passed#{attempt_note}."
  end
end
