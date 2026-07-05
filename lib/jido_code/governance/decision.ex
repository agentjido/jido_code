defmodule JidoCode.Governance.Decision do
  # covers: architecture.run_governance.decision_records_actor_and_rationale
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Governance.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.upsert_decision(attrs, opts)
end
