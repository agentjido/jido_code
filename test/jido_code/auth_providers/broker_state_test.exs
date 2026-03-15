defmodule JidoCode.AuthProviders.BrokerStateTest do
  # covers: auth.provider_broker_handoff.state_token_signature
  # covers: auth.provider_broker_handoff.state_token_ttl
  use ExUnit.Case, async: true

  alias JidoCode.AuthProviders.BrokerState

  @now ~U[2026-03-15 15:00:00Z]

  test "issue/2 and verify/2 round-trip signed provider state" do
    {:ok, issued} =
      BrokerState.issue(
        %{
          provider: "github",
          provider_host: "github.com",
          broker_base_url: "https://broker.example.com",
          redirect_path: "/welcome"
        },
        now: @now,
        nonce: "fixed-nonce"
      )

    assert issued.claims.provider == "github"
    assert issued.claims.nonce == "fixed-nonce"

    assert {:ok, verified} = BrokerState.verify(issued.token, now: @now)
    assert verified.provider == "github"
    assert verified.provider_host == "github.com"
    assert verified.redirect_path == "/welcome"
    assert verified.nonce == "fixed-nonce"
  end

  test "verify/2 fails closed when the signed state is expired" do
    {:ok, issued} =
      BrokerState.issue(
        %{
          provider: "github",
          provider_host: "github.com",
          broker_base_url: "https://broker.example.com"
        },
        now: @now,
        ttl_seconds: 1
      )

    assert {:error, %{error_type: "broker_state_expired"}} =
             BrokerState.verify(
               issued.token,
               now: DateTime.add(@now, 5, :second),
               max_age: 1
             )
  end
end
