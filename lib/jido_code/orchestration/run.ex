defmodule JidoCode.Orchestration.Run do
  # covers: architecture.execution_pipeline.run_is_projection_of_workflow_state
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Orchestration.{RecordStore, RunActions}

  @spec get_by_workflow_run_id(String.t(), keyword()) :: {:ok, t() | nil} | {:error, term()}
  def get_by_workflow_run_id(workflow_run_id, opts \\ []) do
    RecordStore.get_run_by_workflow_run_id(workflow_run_id, opts)
  end

  @spec get_by_managed_repo_and_run_id(String.t(), String.t(), keyword()) ::
          {:ok, t() | nil} | {:error, term()}
  def get_by_managed_repo_and_run_id(managed_repo_id, run_id, opts \\ []) do
    RecordStore.get_run_by_managed_repo_and_run_id(managed_repo_id, run_id, opts)
  end

  @spec approve(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def approve(run, params \\ nil), do: RunActions.approve(run, params)

  @spec reject(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def reject(run, params \\ nil), do: RunActions.reject(run, params)

  @spec retry(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def retry(run, params \\ nil), do: RunActions.retry(run, params)

  @spec retry_step(t(), map() | nil) :: {:ok, t()} | {:error, map()}
  def retry_step(run, params \\ nil), do: RunActions.retry_step(run, params)

  @spec step_retry_contract(t()) :: {:ok, map()} | {:error, map()}
  def step_retry_contract(run), do: RunActions.step_retry_contract(run)
end
