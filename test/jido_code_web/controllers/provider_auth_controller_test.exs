defmodule JidoCodeWeb.ProviderAuthControllerTest do
  # covers: auth.provider_broker_handoff.start_endpoint_contract
  # covers: auth.provider_broker_handoff.complete_endpoint_contract
  use JidoCodeWeb.ConnCase, async: false

  alias JidoCode.AuthProviders.{BrokerNonceStore, BrokerState, ProviderConfig}

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
    {:ok, _config} =
      ProviderConfig.upsert(
        %{
          provider: :github,
          provider_host: "github.com",
          enabled: true,
          login_enabled: true,
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    conn =
      get(conn, ~p"/auth/providers/github/start?provider_host=github.com&redirect_path=/welcome")

    redirected = redirected_to(conn, 302)

    assert redirected =~ "https://broker.example.com/auth/providers/github/start?"
    assert redirected =~ "provider_host=github.com"
    assert redirected =~ "redirect_uri="
    assert redirected =~ "state="
  end

  test "complete validates the broker handoff contract and returns acknowledged contract data", %{conn: conn} do
    {:ok, _config} =
      ProviderConfig.upsert(
        %{
          provider: :github,
          provider_host: "github.com",
          enabled: true,
          login_enabled: true,
          broker_issuer: "https://broker.example.com",
          broker_audience: "jido-code",
          broker_base_url: "https://broker.example.com"
        },
        authorize?: false
      )

    {:ok, issued_state} =
      BrokerState.issue(
        %{
          provider: "github",
          provider_host: "github.com",
          broker_base_url: "https://broker.example.com",
          redirect_path: "/welcome"
        },
        now: @now,
        nonce: "controller-nonce"
      )

    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})

    Application.put_env(:jido_code, @resolver_env, fn _config ->
      {:ok, %{"keys" => [public_jwk_map(jwk)]}}
    end)

    handoff_token =
      handoff_token(jwk, %{
        "nonce" => "controller-nonce",
        "exp" => DateTime.to_unix(DateTime.add(DateTime.utc_now(), 300, :second))
      })

    response =
      conn
      |> get(
        ~p"/auth/providers/github/complete?provider_host=github.com&state=#{issued_state.token}&handoff_token=#{handoff_token}"
      )
      |> json_response(200)

    assert response["status"] == "broker_handoff_validated"
    assert response["provider"] == "github"
    assert response["provider_host"] == "github.com"
    assert response["nonce"] == "controller-nonce"
    assert response["redirect_path"] == "/welcome"
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
