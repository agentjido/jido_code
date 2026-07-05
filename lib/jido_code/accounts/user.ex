defmodule JidoCode.Accounts.User do
  # covers: users.admin_system.user_schema_fields_support_local_auth
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Accounts.UserStore

  @spec provision_from_provider_identity(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def provision_from_provider_identity(attrs, opts \\ []) when is_map(attrs), do: UserStore.upsert(attrs, opts)
end
