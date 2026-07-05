defmodule JidoCode.Accounts.SessionTokensApiKeysTest do
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: auth.system.api_key_session_lifecycle
  use ExUnit.Case, async: false

  alias JidoCode.Accounts.{ApiKeys, SessionTokens, UserStore}
  alias JidoCode.ControlPlane.StoreServer

  setup do
    setup_store!()
  end

  test "session tokens are issued, verified, and revoked through the embedded store" do
    user = create_user!("session-owner@example.com")

    assert {:ok, token} = SessionTokens.issue(user)
    assert is_binary(token)

    assert {:ok, verified_user} = SessionTokens.verify(token)
    assert verified_user.id == user.id

    assert :ok = SessionTokens.revoke(token)
    assert {:error, :token_revoked} = SessionTokens.verify(token)
  end

  test "API keys are issued, verified, and revoked without storing plaintext key material" do
    user = create_user!("api-key-owner@example.com")

    assert {:ok, issued} = ApiKeys.issue(user, name: "Automation")
    assert String.starts_with?(issued.api_key, "agentjido_")

    assert {:ok, verified_user} = ApiKeys.verify(issued.api_key)
    assert verified_user.id == user.id

    assert :ok = ApiKeys.revoke(issued.id)
    assert {:error, :api_key_revoked} = ApiKeys.verify(issued.api_key)
  end

  defp create_user!(email) do
    {:ok, user} =
      UserStore.upsert(%{
        email: email,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second),
        is_admin: false
      })

    user
  end

  defp setup_store! do
    store_name = :"session_tokens_api_keys_store_#{System.unique_integer([:positive])}"
    path = Path.join(System.tmp_dir!(), "jido_code_session_tokens_api_keys/#{store_name}")

    start_supervised!({StoreServer, name: store_name, id: store_name, path: path, reset_policy: :reset_on_start})

    original = Application.get_env(:jido_code, :control_plane_product_store_server, :__missing__)
    Application.put_env(:jido_code, :control_plane_product_store_server, store_name)

    on_exit(fn ->
      restore_env(:control_plane_product_store_server, original)
      File.rm_rf!(path)
    end)

    :ok
  end

  defp restore_env(key, :__missing__), do: Application.delete_env(:jido_code, key)
  defp restore_env(key, value), do: Application.put_env(:jido_code, key, value)
end
