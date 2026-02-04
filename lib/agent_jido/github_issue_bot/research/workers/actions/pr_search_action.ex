defmodule AgentJido.GithubIssueBot.Research.Workers.Actions.PRSearchAction do
  @moduledoc """
  Searches for related PRs and issues.

  Looks for PRs/issues that might be related to the current issue.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, :number, etc.
  - triage: Triage results with :classification

  ## Output

  Emits pr_search.result to parent with:
  - related_prs: List of potentially related PRs
  - related_issues: List of potentially related issues
  - potential_duplicates: Issues that might be duplicates
  - potential_fixes: Open PRs that might fix this issue
  - summary: Human-readable summary

  ## Current Behavior (Stub)

  Returns mock search results.
  TODO: Use GitHub Search API to find actual related PRs/issues.
  """
  use Jido.Action,
    name: "pr_search",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, issue: issue, triage: triage}, context) do
    Logger.debug("PR/Issue search for run: #{run_id}")

    repo = Map.get(issue, :repo, "unknown/repo")
    title = Map.get(issue, :title, "")
    classification = Map.get(triage, :classification, :unknown)

    # Mock search results (stub implementation)
    # TODO: Replace with actual GitHub API calls
    result = %{
      repo: repo,
      search_terms: extract_search_terms(title),
      related_prs: mock_related_prs(classification),
      related_issues: mock_related_issues(classification),
      potential_duplicates: [],
      potential_fixes: mock_potential_fixes(classification),
      summary: generate_summary(classification)
    }

    result_signal =
      Signal.new!(
        "pr_search.result",
        %{
          run_id: run_id,
          worker_type: :pr_search,
          result: result
        },
        source: "/pr_search"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: Map.get(issue, :number)
     }, List.wrap(emit_directive)}
  end

  # Extract search terms from title
  defp extract_search_terms(title) do
    title
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, "")
    |> String.split()
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.take(5)
  end

  # Mock related PRs based on classification
  defp mock_related_prs(:bug) do
    [
      %{
        number: 456,
        title: "Fix state serialization edge case",
        state: "merged",
        url: "https://github.com/example/repo/pull/456"
      }
    ]
  end

  defp mock_related_prs(_), do: []

  # Mock related issues based on classification
  defp mock_related_issues(:bug) do
    [
      %{
        number: 100,
        title: "Similar state persistence issue",
        state: "closed",
        url: "https://github.com/example/repo/issues/100"
      }
    ]
  end

  defp mock_related_issues(_), do: []

  # Mock potential fixes (open PRs that might address this)
  defp mock_potential_fixes(:bug) do
    [
      %{
        number: 789,
        title: "WIP: Improve state handling",
        state: "open",
        url: "https://github.com/example/repo/pull/789",
        match_confidence: :low
      }
    ]
  end

  defp mock_potential_fixes(_), do: []

  # Generate summary of search results
  defp generate_summary(:bug) do
    "Found 1 related merged PR and 1 similar closed issue"
  end

  defp generate_summary(_) do
    "No directly related PRs or issues found"
  end
end
