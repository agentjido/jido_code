defmodule JidoCode.AuthProviders.BrokerHandoffTest do
  # covers: auth.provider_broker_handoff.broker_jwt_validation
  # covers: auth.provider_broker_handoff.issuer_and_audience_validation
  # covers: auth.provider_broker_handoff.nonce_binding
  # covers: auth.provider_broker_handoff.nonce_replay_protection
  use ExUnit.Case, async: false

  alias JidoCode.AuthProviders.{BrokerHandoff, BrokerNonceStore}

  @now ~U[2026-03-15 16:00:00Z]

  setup do
    BrokerNonceStore.reset!()
    :ok
  end

  test "validate/4 accepts a valid broker handoff and rejects replay" do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    token = handoff_token(jwk, %{"nonce" => "nonce-1", "exp" => DateTime.to_unix(DateTime.add(@now, 300, :second))})

    provider_config = %{
      broker_issuer: "https://broker.example.com",
      broker_audience: "jido-code",
      broker_base_url: "https://broker.example.com"
    }

    expected_state = %{provider: "github", provider_host: "github.com", nonce: "nonce-1"}

    resolver = fn _config -> {:ok, %{"keys" => [public_jwk_map(jwk)]}} end

    assert {:ok, validated} =
             BrokerHandoff.validate(token, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )

    assert validated.provider == "github"
    assert validated.provider_host == "github.com"
    assert validated.nonce == "nonce-1"

    assert {:error, %{error_type: "broker_handoff_replayed"}} =
             BrokerHandoff.validate(token, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )
  end

  test "validate/4 fails closed on issuer, audience, expiry, and nonce mismatch" do
    jwk = JOSE.JWK.generate_key({:okp, :Ed25519})
    resolver = fn _config -> {:ok, %{"keys" => [public_jwk_map(jwk)]}} end

    provider_config = %{
      broker_issuer: "https://broker.example.com",
      broker_audience: "jido-code",
      broker_base_url: "https://broker.example.com"
    }

    expected_state = %{provider: "github", provider_host: "github.com", nonce: "expected-nonce"}

    wrong_issuer =
      handoff_token(jwk, %{
        "iss" => "https://wrong.example.com",
        "nonce" => "expected-nonce",
        "exp" => DateTime.to_unix(DateTime.add(@now, 300, :second))
      })

    assert {:error, %{error_type: "broker_handoff_invalid_issuer"}} =
             BrokerHandoff.validate(wrong_issuer, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )

    wrong_audience =
      handoff_token(jwk, %{
        "aud" => "other-audience",
        "nonce" => "expected-nonce",
        "exp" => DateTime.to_unix(DateTime.add(@now, 300, :second))
      })

    assert {:error, %{error_type: "broker_handoff_invalid_audience"}} =
             BrokerHandoff.validate(wrong_audience, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )

    wrong_nonce =
      handoff_token(jwk, %{
        "nonce" => "other-nonce",
        "exp" => DateTime.to_unix(DateTime.add(@now, 300, :second))
      })

    assert {:error, %{error_type: "broker_handoff_invalid_nonce"}} =
             BrokerHandoff.validate(wrong_nonce, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )

    expired =
      handoff_token(jwk, %{
        "nonce" => "expected-nonce",
        "exp" => DateTime.to_unix(DateTime.add(@now, -10, :second))
      })

    assert {:error, %{error_type: "broker_handoff_expired"}} =
             BrokerHandoff.validate(expired, provider_config, expected_state,
               now: @now,
               jwks_resolver: resolver
             )
  end

  defp handoff_token(jwk, overrides) do
    claims =
      Map.merge(
        %{
          "iss" => "https://broker.example.com",
          "aud" => "jido-code",
          "nonce" => "nonce-1",
          "provider" => "github",
          "provider_host" => "github.com",
          "provider_subject" => "12345",
          "provider_login" => "octocat",
          "provider_email" => "octocat@example.com",
          "email_verified" => true,
          "exp" => DateTime.to_unix(DateTime.add(@now, 300, :second))
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
