defmodule AgentJido.GithubIssueBot.Research.Workers.Actions.RootCauseAction do
  @moduledoc """
  Hypothesizes the root cause of an issue.

  Analyzes issue content and triage results to generate a hypothesis.

  ## Input

  - run_id: The parent run identifier
  - issue: Map with :title, :body, :repo, etc.
  - triage: Triage results with :classification

  ## Output

  Emits root_cause.result to parent with:
  - hypothesis: Primary root cause hypothesis
  - confidence: :high, :medium, :low
  - evidence: List of supporting evidence from issue
  - suggested_fix_area: Where to look for the fix
  - summary: Human-readable summary

  ## Current Behavior (Stub)

  Uses simple heuristics based on keywords.
  TODO: Use LLM (via jido_ai ReAct agent) for sophisticated analysis.
  """
  use Jido.Action,
    name: "root_cause",
    schema: [
      run_id: [type: :string, required: true],
      issue: [type: :map, required: true],
      triage: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, issue: issue, triage: triage}, context) do
    Logger.debug("Root cause analysis for run: #{run_id}")

    title = Map.get(issue, :title, "") |> String.downcase()
    body = Map.get(issue, :body, "") |> String.downcase()
    classification = Map.get(triage, :classification, :unknown)

    # Generate hypothesis (stub implementation)
    {hypothesis, confidence, fix_area} = hypothesize(title, body, classification)
    evidence = extract_evidence(body)

    result = %{
      hypothesis: hypothesis,
      confidence: confidence,
      evidence: evidence,
      suggested_fix_area: fix_area,
      summary: "#{confidence} confidence: #{hypothesis}"
    }

    result_signal =
      Signal.new!(
        "root_cause.result",
        %{
          run_id: run_id,
          worker_type: :root_cause,
          result: result
        },
        source: "/root_cause"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       run_id: run_id,
       issue_number: Map.get(issue, :number)
     }, List.wrap(emit_directive)}
  end

  # Generate hypothesis based on keywords and classification
  defp hypothesize(title, body, classification) do
    cond do
      state_persist_issue?(body) -> {"State serialization/deserialization issue", :medium, "lib/core/state.ex"}
      state_lost_issue?(body) -> {"State not being saved properly", :medium, "lib/core/agent.ex"}
      concurrency_issue?(body) -> {"Race condition in concurrent operations", :low, "lib/core/"}
      error_handling_issue?(title, body) -> {"Unhandled error case", :medium, "lib/"}
      classification == :bug -> {"Logic error in core functionality", :low, "lib/"}
      classification == :feature -> {"Missing feature implementation", :high, "lib/"}
      true -> {"Unable to determine root cause", :low, nil}
    end
  end

  defp state_persist_issue?(body), do: String.contains?(body, "state") and String.contains?(body, "persist")
  defp state_lost_issue?(body), do: String.contains?(body, "state") and String.contains?(body, "lost")
  defp concurrency_issue?(body), do: String.contains?(body, "race") or String.contains?(body, "concurrent")
  defp error_handling_issue?(title, body), do: String.contains?(title, "error") or String.contains?(body, "exception")

  # Extract evidence from issue body
  defp extract_evidence(body) do
    evidence = []

    # Look for error messages
    evidence =
      if String.contains?(body, "error") or String.contains?(body, "exception") do
        ["Contains error/exception reference" | evidence]
      else
        evidence
      end

    # Look for stack traces
    evidence =
      if String.contains?(body, "stacktrace") or String.contains?(body, "** (") do
        ["Contains stack trace" | evidence]
      else
        evidence
      end

    # Look for version info
    evidence =
      if String.contains?(body, "version") do
        ["Version information provided" | evidence]
      else
        evidence
      end

    # Look for code snippets
    evidence =
      if String.contains?(body, "```") do
        ["Contains code snippets" | evidence]
      else
        evidence
      end

    evidence
  end
end
