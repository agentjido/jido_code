defmodule JidoCode.ControlPlane.Telemetry do
  @moduledoc """
  Telemetry helpers for the embedded control-plane store boundary.
  """

  @prefix [:jido_code, :control_plane]

  @spec span(atom(), map(), (-> term())) :: term()
  def span(operation, metadata \\ %{}, fun) when is_atom(operation) and is_map(metadata) and is_function(fun, 0) do
    :telemetry.span(@prefix ++ [operation], metadata, fn ->
      result = fun.()
      {result, Map.merge(metadata, result_metadata(result))}
    end)
  end

  @spec execute(atom(), map(), map()) :: :ok
  def execute(operation, measurements, metadata \\ %{})
      when is_atom(operation) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@prefix ++ [operation], measurements, metadata)
  end

  defp result_metadata({:ok, result}) when is_map(result) do
    result
    |> Map.take([
      :status,
      :graph_count,
      :total_quad_count,
      :exported_quad_count,
      :omitted_quad_count,
      :restored_quad_count,
      :written_triple_count,
      :deleted_triple_count
    ])
    |> Map.put_new(:status, :ok)
  end

  defp result_metadata({:ok, _result}), do: %{status: :ok}
  defp result_metadata({:error, reason}), do: %{status: :error, reason: reason}
  defp result_metadata({:error, reason, diagnostics}), do: %{status: :error, reason: reason, diagnostics: diagnostics}
  defp result_metadata(_result), do: %{status: :ok}
end
