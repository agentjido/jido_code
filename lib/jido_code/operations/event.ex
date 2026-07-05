defmodule JidoCode.Operations.Event do
  # covers: architecture.operations.event_records_ingress_flow
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Operations.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.create(:event, attrs, opts)
end
