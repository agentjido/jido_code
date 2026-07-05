defmodule JidoCode.Conversations.Conversation do
  # covers: architecture.conversation_orchestration.conversation_records_repo_scope
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Conversations.RecordStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: RecordStore.create_conversation(attrs, opts)
end
