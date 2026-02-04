defmodule AgentJido.GithubIssueBot.PullRequest.Workers.Actions.QualityAction do
  @moduledoc """
  Validates the quality of the code fix.

  Runs tests, linting, and type checking on the patched code.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, :number, etc.
  - triage: Triage results with :classification
  - research: Research findings from the research phase

  ## Output

  Emits quality.result to parent with:
  - tests_passed: Boolean indicating if tests passed
  - lint_passed: Boolean indicating if linting passed
  - typecheck_passed: Boolean indicating if type checking passed
  - failures: List of failure details (empty if all passed)

  ## Current Behavior (Stub)

  Returns mock quality results (usually passing).
  TODO: Integrate with actual CI commands (mix test, mix credo, mix dialyzer).
  """
  use Jido.Action,
    name: "quality",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true],
      research: [type: :map, required: true],
      patch: [type: :map, default: %{}],
      attempt: [type: :integer, default: 1]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(params, context) do
    run_id = params.run_id
    issue = params.issue
    attempt = params.attempt

    Logger.debug("Running quality checks for run: #{run_id} (attempt #{attempt})")

    issue_number = Map.get(issue, :number, 0)

    # Stub: Generate mock quality results
    # TODO: Replace with actual CI command execution
    # Uses attempt number to make retries eventually succeed
    result = mock_quality_results(attempt, issue_number)

    result_signal =
      Signal.new!(
        "quality.result",
        %{
          run_id: run_id,
          worker_type: :quality,
          result: result
        },
        source: "/quality_agent"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: issue_number
     }, List.wrap(emit_directive)}
  end

  # Generate mock quality results based on attempt number
  # This allows predictable behavior for testing:
  # - Issue numbers ending in 7 (like 17, 27, 47): fail first 2 attempts, pass on 3rd
  # - Issue numbers ending in 9 (like 19, 29, 49): always fail (to test max retry)
  # - All other issues: pass on first attempt
  defp mock_quality_results(attempt, issue_number) do
    cond do
      # Issues ending in 9 always fail - tests max retry exhaustion
      rem(issue_number, 10) == 9 ->
        failure_result(attempt)

      # Issues ending in 7 fail first 2 attempts, pass on 3rd
      rem(issue_number, 10) == 7 ->
        if attempt >= 3, do: success_result(attempt), else: failure_result(attempt)

      # All other issues pass immediately
      true ->
        success_result(attempt)
    end
  end

  defp success_result(attempt) do
    %{
      tests_passed: true,
      lint_passed: true,
      typecheck_passed: true,
      failures: [],
      test_count: 42,
      test_duration_ms: 1234,
      attempt: attempt,
      summary: "All 42 tests passed. No linting or type errors."
    }
  end

  defp failure_result(attempt) do
    %{
      tests_passed: false,
      lint_passed: true,
      typecheck_passed: true,
      failures: [
        %{
          type: :test,
          file: "test/agent_test.exs",
          line: 15,
          message: "Expected :ok but got {:error, :timeout}"
        }
      ],
      test_count: 42,
      test_failures: 1,
      test_duration_ms: 1567,
      attempt: attempt,
      summary: "1 test failed. See failures for details."
    }
  end
end
