defmodule JidoCodeWeb.ProviderAuthControllerTest do
  # covers: auth.provider_broker_handoff.start_endpoint_contract
  # covers: auth.provider_broker_handoff.complete_endpoint_contract
  # covers: auth.provider_login_policy.blocked_before_linking
  # covers: auth.provider_login_flow.broker_handoff_consumption
  # covers: auth.provider_login_flow.local_session_issuance
  # covers: auth.provider_login_flow.redirect_path_completion
  use JidoCodeWeb.ConnCase, async: false

  alias JidoCode.AuthProviders.{BrokerNonceStore, BrokerState, ProviderConfig}
  alias JidoCode.Accounts.UserIdentity

  @now ~U[2026-03-15 17:00:00Z]
  @resolver_env :provider_auth_broker_jwks_resolver

  setup do
    BrokerNonceStore.reset!()
    original_resolver = Application.get_env(:jido_code, @resolver_env, :__missing__)

    on_exit(fn ->
      case original_resolver do
        :__missing__ -> Application.delete_env(:jido_code, @resolver_env)
        value -> Application.put_env(:jido_code, @resolver_env, value)
      end
    end)

    :ok
  end

  test "start redirects to the broker start contract URL", %{conn: conn} do
    enable_provider_login!(:github, "github.com")

    conn =
      get(conn, ~p"/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome")

    redirected = redirected_to(conn, 302)

    assert redirected =~ "https://broker.example.com/auth/providers/github/start?"
    assert redirected =~ "provider_host=github.com"
    assert redirected =~ "redirect_uri="
    assert redirected =~ "state="
  end

  test "complete validates the broker handoff, signs in locally, and redirects to the signed path", %{
    conn: conn
  } do
    enable_provider_login!(:github, "github.com")
    {issued_state, handoff_token} = valid_broker_handoff("controller-nonce")

    conn =
      get(
        conn,
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    assert redirected_to(conn, 302) == "/welcome"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Your local account was created and signed in with GitHub."

    session_token = get_session(conn, "user_token")
    assert is_binary(session_token)

    welcome_html =
      conn
      |> recycle()
      |> get(~p"/welcome")
      |> html_response(200)

    assert welcome_html =~ "octocat@example.com"
    assert welcome_html =~ "Sign Out"

    {:ok, identities} = UserIdentity.list_for_user(%{user_id: current_user_id(conn)}, authorize?: false)
    assert Enum.map(identities, & &1.provider_subject) == ["12345"]
  end

  test "complete rejects provider login when provider config is disabled", %{conn: conn} do
    {:ok, _config} =
      ProviderConfig.upsert(
        %{
          provider: :github,
          provider_host: "github.com",
          enabled: false,
          login_enabled: false,
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    {issued_state, handoff_token} = valid_broker_handoff("disabled-nonce")

    response =
      conn
      |> get(
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )
      |> json_response(403)

    assert response["error"]["error_type"] == "provider_login_disabled"
  end

  test "complete does not issue a session when the provider identity is not allowlisted", %{
    conn: conn
  } do
    {:ok, _config} =
      ProviderConfig.upsert(
        %{
          provider: :github,
          provider_host: "github.com",
          enabled: true,
          login_enabled: true,
          allowlist_mode: :organizations,
          allowlist_values: ["agentjido"],
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    {issued_state, handoff_token} =
      valid_broker_handoff("blocked-nonce", %{
        "provider_email" => "blocked@example.com",
        "organizations" => ["different-org"]
      })

    response_conn =
      get(
        conn,
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )

    response = json_response(response_conn, 422)

    assert response["error"]["error_type"] == "provider_identity_not_allowlisted"
    assert get_session(response_conn, "user_token") == nil
  end

  defp valid_broker_handoff(nonce, claim_overrides \\ %{}) do
    {:ok, issued_state} =
      BrokerState.issue(
        %{
          provider: "github",
          provider_host: "github.com",
          broker_base_url: "https://broker.example.com",
          redirect_path: "/welcome"
        },
        now: @now,
        nonce: nonce
      )

    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})

    Application.put_env(:jido_code, @resolver_env, fn _config ->
      {:ok, %{"keys" => [public_jwk_map(jwk)]}}
    end)

    handoff_token =
      handoff_token(
        jwk,
        %{
          "nonce" => nonce,
          "exp" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 300, :second))
        }
        |> Map.merge(claim_overrides)
      )

    {issued_state, handoff_token}
  end

  defp current_user_id(conn) do
    conn
    |> recycle()
    |> get(~p"/welcome")
    |> Map.fetch!(:assigns)
    |> Map.fetch!(:current_user)
    |> Map.fetch!(:id)
  end

  defp enable_provider_login!(provider, provider_host) do
    {:ok, config} =
      ProviderConfig.upsert(
        %{
          provider: provider,
          provider_host: provider_host,
          enabled: true,
          login_enabled: true,
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    config
  end

  defp handoff_token(jwk, overrides) do
    claims =
      Map.merge(
        %{
          "iss" => "https://broker.example.com",
          "aud" => "jido-code",
          "nonce" => "controller-nonce",
          "provider" => "github",
          "provider_host" => "github.com",
          "provider_subject" => "12345",
          "provider_login" => "octocat",
          "provider_email" => "octocat@example.com",
          "email_verified" => true,
          "exp" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 300, :second))
        },
        overrides
      )

    {_, compact} =
      jwk
      |> JOSE.JWT.sign(%{"alg" => "EdDSA"}, JOSE.JWT.from_map(claims))
      |> JOSE.JWS.compact()

    compact
  end

  defp public_jwk_map(jwk) do
    jwk
    |> JOSE.JWK.to_public_map()
    |> elem(1)
  end
end
