defmodule JidoCode.Operations.WorkItem do
  # covers: architecture.operations.work_item_records_governed_work
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Operations.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.create(:work_item, attrs, opts)
end
