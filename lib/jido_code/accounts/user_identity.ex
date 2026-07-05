defmodule JidoCode.Accounts.UserIdentity do
  # covers: auth.provider_foundation.user_identity_links_provider_subject
  @moduledoc false

  use JidoCode.ControlPlane.RecordStruct

  alias JidoCode.Accounts.UserIdentityStore

  @spec create(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def create(attrs, opts \\ []) when is_map(attrs), do: UserIdentityStore.upsert(attrs, opts)

  @spec list_for_user(map() | String.t(), keyword()) :: {:ok, [t()]} | {:error, term()}
  def list_for_user(user_or_id, opts \\ [])
  def list_for_user(%{user_id: user_id}, opts), do: UserIdentityStore.list_for_user(user_id, opts)
  def list_for_user(user_id, opts) when is_binary(user_id), do: UserIdentityStore.list_for_user(user_id, opts)
end
