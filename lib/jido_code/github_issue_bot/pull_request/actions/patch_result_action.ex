defmodule JidoCode.GithubIssueBot.PullRequest.Actions.PatchResultAction do
  @moduledoc """
  Handles "patch.result" signal from PatchAgent.

  Stores the patch result and spawns QualityAgent to validate the fix.
  """
  use Jido.Action,
    name: "patch_result",
    schema: [
      run_id: [type: :string, required: true],
      worker_type: [type: :atom, required: true],
      result: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias JidoCode.GithubIssueBot.PullRequest.Workers.QualityAgent

  require Logger

  def run(%{run_id: run_id, worker_type: :patch, result: result}, context) do
    current_run_id = Map.get(context.state, :run_id)
    current_phase = Map.get(context.state, :phase)
    attempt = Map.get(context.state, :attempt, 1)

    cond do
      current_run_id != run_id ->
        Logger.warning("Received patch result for wrong run: #{run_id}")
        {:ok, %{}}

      current_phase != :patching ->
        Logger.warning("Received patch result in wrong phase: #{current_phase}")
        {:ok, %{}}

      true ->
        Logger.info("Patch complete for #{run_id} (attempt #{attempt}), spawning QualityAgent")

        # Spawn QualityAgent to validate the fix
        spawn_directive =
          Directive.spawn_agent(QualityAgent, :quality,
            opts: %{id: worker_agent_id(run_id, :quality, attempt)},
            meta: %{
              run_id: run_id,
              issue: context.state.issue,
              triage: context.state.triage,
              research: context.state.research,
              patch: result,
              attempt: attempt
            }
          )

        {:ok,
         %{
           phase: :validating,
           patch_result: result
         }, [spawn_directive]}
    end
  end

  def run(%{worker_type: other}, _context) do
    Logger.warning("Unexpected worker type in patch result: #{inspect(other)}")
    {:ok, %{}}
  end

  defp worker_agent_id(run_id, worker_type, attempt)
       when is_binary(run_id) and is_atom(worker_type) and is_integer(attempt) do
    "#{run_id}/#{worker_type}/#{attempt}"
  end
end
