defmodule AgentJido.GithubIssueBot.Research.Actions.WorkerResultAction do
  @moduledoc """
  Handles result signals from research workers.

  Aggregates results from:
  - code_search.result
  - reproduction.result
  - root_cause.result
  - pr_search.result

  When all 4 workers have reported, synthesizes a research_report
  and emits research.result to the parent coordinator.
  """
  use Jido.Action,
    name: "worker_result",
    schema: [
      run_id: [type: :string, required: true],
      worker_type: [type: :atom, required: true],
      result: [type: :map, required: true]
    ]

  alias Jido.Agent.Directive
  alias Jido.Signal

  require Logger

  def run(%{run_id: run_id, worker_type: worker_type, result: result}, context) do
    current_run_id = Map.get(context.state, :run_id)
    pending = Map.get(context.state, :pending_workers, [])
    completed = Map.get(context.state, :completed_workers, [])
    worker_results = Map.get(context.state, :worker_results, %{})

    cond do
      # Wrong run - ignore
      current_run_id != run_id ->
        Logger.warning("Received result for wrong run: #{run_id} (expected #{current_run_id})")
        {:ok, %{}}

      # Already received this worker's result - ignore duplicate
      worker_type in completed ->
        Logger.debug("Ignoring duplicate result from #{worker_type}")
        {:ok, %{}}

      # Valid result - aggregate it
      worker_type in pending ->
        Logger.info("Received #{worker_type} result for #{run_id}")

        new_pending = List.delete(pending, worker_type)
        new_completed = [worker_type | completed]
        new_results = Map.put(worker_results, worker_type, result)

        if new_pending == [] do
          # All workers done - synthesize and emit to parent
          Logger.info("All research workers complete for #{run_id}")
          synthesize_and_emit(run_id, new_results, new_completed, context)
        else
          # Still waiting for more workers
          {:ok,
           %{
             pending_workers: new_pending,
             completed_workers: new_completed,
             worker_results: new_results
           }}
        end

      # Unknown worker type
      true ->
        Logger.warning("Unknown worker type: #{worker_type}")
        {:ok, %{}}
    end
  end

  # Synthesize research report from all worker results and emit to parent
  defp synthesize_and_emit(run_id, worker_results, completed_workers, context) do
    research_report = %{
      run_id: run_id,
      completed_at: DateTime.utc_now(),
      workers_completed: completed_workers,

      # Individual worker findings
      code_search: Map.get(worker_results, :code_search, %{}),
      reproduction: Map.get(worker_results, :reproduction, %{}),
      root_cause: Map.get(worker_results, :root_cause, %{}),
      pr_search: Map.get(worker_results, :pr_search, %{}),

      # Synthesized summary (stub for now - could use LLM later)
      summary: synthesize_summary(worker_results)
    }

    result_signal =
      Signal.new!(
        "research.result",
        research_report,
        source: "/research_coordinator"
      )

    emit_directive = Directive.emit_to_parent(context.agent, result_signal)

    {:ok,
     %{
       status: :completed,
       pending_workers: [],
       completed_workers: completed_workers,
       worker_results: worker_results
     }, List.wrap(emit_directive)}
  end

  # Simple summary synthesis - concatenates worker summaries
  # TODO: Could use LLM to synthesize a coherent narrative
  defp synthesize_summary(worker_results) do
    parts =
      Enum.map_join(worker_results, "; ", fn {worker, result} ->
        summary = Map.get(result, :summary, "No summary")
        "#{worker}: #{summary}"
      end)

    "Research complete. #{parts}"
  end
end
