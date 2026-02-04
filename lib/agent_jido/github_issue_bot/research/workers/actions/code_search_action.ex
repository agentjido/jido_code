defmodule AgentJido.GithubIssueBot.Research.Workers.Actions.CodeSearchAction do
  @moduledoc """
  Performs code search for an issue.

  Extracts keywords from the issue and searches for relevant code files.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, etc.
  - triage: Triage results with :classification

  ## Output

  Emits code_search.result to parent with:
  - files: List of relevant file paths
  - snippets: Code snippets that might be relevant
  - keywords: Keywords used for search
  - summary: Human-readable summary

  ## Current Behavior (Stub)

  Returns mock results based on issue keywords.
  TODO: Integrate with GitHub Code Search API or local git grep.
  """
  use Jido.Action,
    name: "code_search",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, issue: issue, triage: triage}, context) do
    Logger.debug("Code search for run: #{run_id}")

    # Extract keywords from issue (stub implementation)
    keywords = extract_keywords(issue)
    classification = Map.get(triage, :classification, :unknown)

    # Stub: Generate mock search results
    # TODO: Replace with actual GitHub Code Search API calls
    result = %{
      keywords: keywords,
      classification: classification,
      files: mock_files(classification),
      snippets: mock_snippets(keywords),
      summary: "Found #{length(mock_files(classification))} potentially relevant files"
    }

    result_signal =
      Signal.new!(
        "code_search.result",
        %{
          run_id: run_id,
          worker_type: :code_search,
          result: result
        },
        source: "/code_search"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: Map.get(issue, :number)
     }, List.wrap(emit_directive)}
  end

  # Extract search keywords from issue title and body
  defp extract_keywords(issue) do
    title = Map.get(issue, :title, "") |> String.downcase()
    body = Map.get(issue, :body, "") |> String.downcase()

    # Simple keyword extraction - split on whitespace, filter short words
    (title <> " " <> body)
    |> String.split(~r/\s+/)
    |> Enum.filter(&(String.length(&1) > 4))
    |> Enum.uniq()
    |> Enum.take(10)
  end

  # Mock file results based on classification
  defp mock_files(:bug), do: ["lib/core/agent.ex", "lib/core/state.ex", "test/agent_test.exs"]
  defp mock_files(:feature), do: ["lib/core/agent.ex", "lib/api/router.ex"]
  defp mock_files(_), do: ["lib/core/agent.ex"]

  # Mock code snippets based on keywords
  defp mock_snippets(keywords) do
    if "state" in keywords or "persist" in keywords do
      [
        %{
          file: "lib/core/agent.ex",
          line: 42,
          content: "def persist_state(agent, state) do"
        }
      ]
    else
      []
    end
  end
end
