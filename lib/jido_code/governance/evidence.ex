defmodule JidoCode.Governance.Evidence do
  # covers: architecture.run_governance.evidence_records_attach_to_runs_and_work
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Governance.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.upsert_evidence(attrs, opts)
end
