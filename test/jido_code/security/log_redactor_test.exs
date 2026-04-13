defmodule JidoCode.Security.LogRedactorTest do
  use ExUnit.Case, async: true

  alias JidoCode.Security.LogRedactor

  test "redact_event masks secret fields and inline bearer tokens" do
    secret = "sk-test-0123456789abcdef"
    webhook_secret = "whsec_1234567890abcdef"

    payload = %{
      api_token: secret,
      nested: %{webhook_secret: webhook_secret},
      message: "Authorization: Bearer #{secret}",
      status: "failed"
    }

    assert {:ok, redacted_payload} = LogRedactor.redact_event(payload)

    redacted_api_token = Map.fetch!(redacted_payload, :api_token)
    redacted_nested = Map.fetch!(redacted_payload, :nested)
    redacted_webhook_secret = Map.fetch!(redacted_nested, :webhook_secret)
    redacted_message = Map.fetch!(redacted_payload, :message)

    refute redacted_api_token == secret
    assert redacted_api_token =~ "len="
    assert redacted_api_token =~ "sk"

    refute redacted_webhook_secret == webhook_secret
    assert redacted_webhook_secret =~ "wh"
    assert redacted_webhook_secret =~ "len="

    refute redacted_message =~ secret
    assert redacted_message =~ "Authorization: Bearer [REDACTED"

    refute inspect(redacted_payload) =~ secret
    refute inspect(redacted_payload) =~ webhook_secret
  end

  test "safe_inspect masks assignment-style secrets" do
    inspected =
      LogRedactor.safe_inspect(%{
        message: "token=abcdef1234567890 password=letmein1234"
      })

    assert inspected =~ "token=[REDACTED"
    assert inspected =~ "password=[REDACTED"
    refute inspected =~ "abcdef1234567890"
    refute inspected =~ "letmein1234"
  end

  test "redact_event preserves structs like DateTime while redacting nested secrets" do
    occurred_at = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    payload = %{
      occurred_at: occurred_at,
      nested: %{api_token: "sk-test-0123456789abcdef"}
    }

    assert {:ok, redacted_payload} = LogRedactor.redact_event(payload)
    assert %DateTime{} = redacted_payload.occurred_at
    assert redacted_payload.occurred_at == occurred_at
    assert redacted_payload.nested.api_token =~ "[REDACTED"
  end
end
