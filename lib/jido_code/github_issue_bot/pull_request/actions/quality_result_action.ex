defmodule JidoCode.GithubIssueBot.PullRequest.Actions.QualityResultAction do
  @moduledoc """
  Handles "quality.result" signal from QualityAgent.

  Implements the retry logic:
  - If quality passes → spawn PRSubmitAgent
  - If quality fails and attempts < max → retry with new PatchAgent
  - If quality fails and attempts >= max → emit failure to parent
  """
  use Jido.Action,
    name: "quality_result",
    schema: [
      run_id: [type: :string, required: true],
      worker_type: [type: :atom, required: true],
      result: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  alias JidoCode.GithubIssueBot.PullRequest.Workers.{
    PatchAgent,
    PRSubmitAgent
  }

  require Logger

  def run(%{run_id: run_id, worker_type: :quality, result: result}, context) do
    current_run_id = Map.get(context.state, :run_id)
    current_phase = Map.get(context.state, :phase)
    attempt = Map.get(context.state, :attempt, 1)
    max_attempts = Map.get(context.state, :max_attempts, 3)
    attempt_history = Map.get(context.state, :attempt_history, [])

    cond do
      current_run_id != run_id ->
        Logger.warning("Received quality result for wrong run: #{run_id}")
        {:ok, %{}}

      current_phase != :validating ->
        Logger.warning("Received quality result in wrong phase: #{current_phase}")
        {:ok, %{}}

      true ->
        quality_passed = quality_passed?(result)
        handle_quality_result(run_id, result, quality_passed, attempt, max_attempts, attempt_history, context)
    end
  end

  def run(%{worker_type: other}, _context) do
    Logger.warning("Unexpected worker type in quality result: #{inspect(other)}")
    {:ok, %{}}
  end

  # Quality passed - proceed to PR submission
  defp handle_quality_result(run_id, result, true = _passed, attempt, _max_attempts, attempt_history, context) do
    Logger.info("Quality checks passed for #{run_id} (attempt #{attempt}), spawning PRSubmitAgent")

    patch_result = Map.get(context.state, :patch_result, %{})

    spawn_directive =
      Directive.spawn_agent(PRSubmitAgent, :pr_submit,
        opts: %{id: worker_agent_id(run_id, :pr_submit, attempt)},
        meta: %{
          run_id: run_id,
          issue: context.state.issue,
          triage: context.state.triage,
          research: context.state.research,
          patch: patch_result,
          quality: result,
          attempt: attempt
        }
      )

    # Record successful attempt
    history_entry = %{
      attempt: attempt,
      patch: context.state.patch_result,
      quality: result,
      outcome: :passed
    }

    {:ok,
     %{
       phase: :submitting,
       quality_result: result,
       attempt_history: attempt_history ++ [history_entry]
     }, [spawn_directive]}
  end

  # Quality failed but can retry
  defp handle_quality_result(run_id, result, false = _passed, attempt, max_attempts, attempt_history, context)
       when attempt < max_attempts do
    next_attempt = attempt + 1
    Logger.warning("Quality checks failed for #{run_id} (attempt #{attempt}/#{max_attempts}), retrying...")

    # Record failed attempt
    history_entry = %{
      attempt: attempt,
      patch: context.state.patch_result,
      quality: result,
      outcome: :failed,
      failures: Map.get(result, :failures, [])
    }

    # Spawn new PatchAgent for retry
    spawn_directive =
      Directive.spawn_agent(PatchAgent, :patch,
        opts: %{id: worker_agent_id(run_id, :patch, next_attempt)},
        meta: %{
          run_id: run_id,
          issue: context.state.issue,
          triage: context.state.triage,
          research: context.state.research,
          previous_patch: context.state.patch_result,
          previous_quality: result,
          attempt: next_attempt
        }
      )

    {:ok,
     %{
       phase: :patching,
       attempt: next_attempt,
       quality_result: result,
       attempt_history: attempt_history ++ [history_entry]
     }, [spawn_directive]}
  end

  # Quality failed and max retries reached
  defp handle_quality_result(run_id, result, false = _passed, attempt, max_attempts, attempt_history, context) do
    Logger.error("Quality checks failed for #{run_id} after #{attempt} attempts, giving up")

    # Record final failed attempt
    history_entry = %{
      attempt: attempt,
      patch: context.state.patch_result,
      quality: result,
      outcome: :failed,
      failures: Map.get(result, :failures, [])
    }

    final_history = attempt_history ++ [history_entry]

    # Emit failure to parent
    failure_report = %{
      run_id: run_id,
      completed_at: DateTime.utc_now(),
      success: false,
      attempts: attempt,
      max_attempts: max_attempts,
      patch: context.state.patch_result,
      quality: result,
      pr_submit: %{},
      attempt_history: final_history,
      summary: "Failed after #{attempt} attempts. Quality checks did not pass."
    }

    result_signal =
      Signal.new!(
        "pull_request.result",
        failure_report,
        source: "/pull_request_coordinator"
      )

    emit_directive = Directive.emit_to_parent(%{state: context.state}, result_signal)

    {:ok,
     %{
       phase: :failed,
       status: :failed,
       quality_result: result,
       attempt_history: final_history
     }, [emit_directive]}
  end

  # Check if all quality checks passed
  defp quality_passed?(result) do
    Map.get(result, :tests_passed, false) and
      Map.get(result, :lint_passed, false) and
      Map.get(result, :typecheck_passed, false)
  end

  defp worker_agent_id(run_id, worker_type, attempt)
       when is_binary(run_id) and is_atom(worker_type) and is_integer(attempt) do
    "#{run_id}/#{worker_type}/#{attempt}"
  end
end
