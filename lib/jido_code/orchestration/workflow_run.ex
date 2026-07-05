defmodule JidoCode.Orchestration.WorkflowRun do
  # covers: architecture.run_governance.workflow_run_audit_preserves_actor_class_attribution
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  @retry_action_error_type "workflow_run_retry_action_failed"

  @spec step_retry_contract(t()) :: {:ok, map()} | {:error, map()}
  def step_retry_contract(%__MODULE__{} = run) do
    contract =
      run.step_results
      |> normalize_map()
      |> map_get(:step_retry_contract, %{})
      |> normalize_map()

    case contract |> map_get(:retry_step) |> normalize_optional_string() do
      nil ->
        {:error,
         action_failure(
           "step_retry_unavailable",
           "Step-level retry is not available for this workflow run.",
           "Refresh run projections and retry once failure context includes a retryable step."
         )}

      _retry_step ->
        {:ok, contract}
    end
  end

  def step_retry_contract(_run) do
    {:error,
     action_failure(
       "invalid_run",
       "Run reference is invalid and step-level retry contract cannot be resolved.",
       "Reload run detail and retry once the failed run is available."
     )}
  end

  defp action_failure(reason_type, detail, remediation) do
    %{
      "error_type" => @retry_action_error_type,
      "reason_type" => reason_type,
      "detail" => detail,
      "remediation" => remediation,
      "timestamp" => DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()
    }
  end

  defp normalize_map(%{} = map), do: map
  defp normalize_map(_value), do: %{}

  defp map_get(map, key, default \\ nil)
  defp map_get(%{} = map, key, default), do: Map.get(map, key, Map.get(map, to_string(key), default))
  defp map_get(_map, _key, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
