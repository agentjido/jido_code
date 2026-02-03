defmodule AgentJido.GithubIssueBot.IssueRun.Actions.TriageResultAction do
  @moduledoc """
  Handles "triage.result" signal from triage agent.

  Aggregates the triage result into coordinator artifacts.
  If triage is valid (not needs_info), spawns ResearchCoordinator for next phase.
  """
  use Jido.Action,
    name: "triage_result",
    schema: [
      run_id: [type: :string, required: true],
      classification: [type: :atom, required: true],
      needs_info: [type: :boolean, default: false],
      summary: [type: :string, default: ""]
    ]

  alias Jido.Agent.Directive
  alias AgentJido.GithubIssueBot.Research.ResearchCoordinator

  require Logger

  def run(
        %{
          run_id: run_id,
          classification: classification,
          needs_info: needs_info,
          summary: summary
        },
        context
      ) do
    current_run_id = Map.get(context.state, :run_id)
    current_artifacts = Map.get(context.state, :artifacts, %{})
    current_issue = Map.get(context.state, :issue, %{})

    cond do
      current_run_id != run_id ->
        Logger.warning("Received triage result for wrong run: #{run_id} (expected #{current_run_id})")

        {:ok, %{}}

      Map.has_key?(current_artifacts, :triage) ->
        Logger.debug("Ignoring duplicate triage result for #{run_id}")
        {:ok, %{}}

      # Issue needs more info - don't proceed to research
      needs_info ->
        Logger.info("Triage complete for #{run_id}: needs more info")

        triage_artifact = %{
          classification: classification,
          needs_info: needs_info,
          summary: summary,
          completed_at: DateTime.utc_now()
        }

        {:ok,
         %{
           phase: :needs_info,
           status: :needs_info,
           artifacts: Map.put(current_artifacts, :triage, triage_artifact)
         }}

      # Triage passed - spawn research coordinator
      true ->
        Logger.info("Triage complete for #{run_id}: #{classification}, spawning research")

        triage_artifact = %{
          classification: classification,
          needs_info: needs_info,
          summary: summary,
          completed_at: DateTime.utc_now()
        }

        # Spawn research coordinator with issue and triage context
        spawn_directive =
          Directive.spawn_agent(ResearchCoordinator, :research,
            meta: %{
              run_id: run_id,
              issue: current_issue,
              triage: triage_artifact
            }
          )

        {:ok,
         %{
           phase: :awaiting_research,
           artifacts: Map.put(current_artifacts, :triage, triage_artifact)
         }, [spawn_directive]}
    end
  end
end
