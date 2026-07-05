defmodule JidoCode.Operations.Assessment do
  # covers: architecture.operations.assessment_records_triage_outcomes
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Operations.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.create(:assessment, attrs, opts)
end
