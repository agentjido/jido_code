defmodule AgentJido.GithubIssueBot.PullRequest.Workers.Actions.PatchAction do
  @moduledoc """
  Implements the code fix for an issue.

  Analyzes research findings and creates code changes to fix the issue.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, :number, etc.
  - triage: Triage results with :classification
  - research: Research findings from the research phase

  ## Output

  Emits patch.result to parent with:
  - branch_name: Name of the fix branch
  - files_changed: List of modified file paths
  - commit_sha: SHA of the fix commit
  - summary: Human-readable description of changes

  ## Current Behavior (Stub)

  Returns mock patch data based on issue details.
  TODO: Integrate with AI code generation and GitHub API.
  """
  use Jido.Action,
    name: "patch",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true],
      research: [type: :map, required: true],
      attempt: [type: :integer, default: 1],
      # For retries - previous attempt results (empty map if first attempt)
      previous_patch: [type: :map, default: %{}],
      previous_quality: [type: :map, default: %{}]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(params, context) do
    run_id = params.run_id
    issue = params.issue
    triage = params.triage
    research = params.research
    attempt = params.attempt
    previous_quality = params.previous_quality

    Logger.debug("Creating patch for run: #{run_id} (attempt #{attempt})")

    issue_number = Map.get(issue, :number, 0)
    classification = Map.get(triage, :classification, :unknown)

    # Stub: Generate mock patch data
    # TODO: Replace with actual code generation and git operations
    # On retry, we might modify approach based on previous failures
    result = %{
      branch_name: "fix/issue-#{issue_number}",
      files_changed: mock_files_changed(classification, research),
      commit_sha: generate_mock_sha(),
      attempt: attempt,
      summary: generate_summary(issue, classification, attempt, previous_quality)
    }

    result_signal =
      Signal.new!(
        "patch.result",
        %{
          run_id: run_id,
          worker_type: :patch,
          result: result
        },
        source: "/patch_agent"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: issue_number
     }, List.wrap(emit_directive)}
  end

  # Mock files changed based on classification and research
  defp mock_files_changed(:bug, research) do
    # Use files from research if available
    code_search = Map.get(research, :code_search, %{})
    files = Map.get(code_search, :files, [])

    if files == [] do
      ["lib/core/agent.ex", "test/agent_test.exs"]
    else
      Enum.take(files, 3)
    end
  end

  defp mock_files_changed(:feature, _research) do
    ["lib/core/agent.ex", "lib/api/router.ex", "test/api/router_test.exs"]
  end

  defp mock_files_changed(_classification, _research) do
    ["lib/core/agent.ex"]
  end

  # Generate a mock commit SHA
  defp generate_mock_sha do
    :crypto.strong_rand_bytes(20)
    |> Base.encode16(case: :lower)
    |> String.slice(0..39)
  end

  # Generate a summary of changes
  defp generate_summary(issue, classification, attempt, previous_quality) do
    title = Map.get(issue, :title, "issue")
    base_summary = base_summary(title, classification)

    if attempt > 1 and previous_quality != %{} do
      failures = Map.get(previous_quality, :failures, [])
      failure_info = if failures != [], do: " Addressed: #{length(failures)} previous failure(s).", else: ""
      "#{base_summary} (Attempt #{attempt}).#{failure_info}"
    else
      base_summary
    end
  end

  defp base_summary(title, :bug) do
    "Fixed bug: #{title}. Added error handling and updated tests."
  end

  defp base_summary(title, :feature) do
    "Implemented feature: #{title}. Added new module and API endpoint."
  end

  defp base_summary(title, _classification) do
    "Addressed: #{title}. Made necessary code changes."
  end
end
