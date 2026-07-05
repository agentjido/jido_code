defmodule JidoCode.Forge.EventLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  require Logger

  alias JidoCode.Forge.EventLogger
  alias JidoCode.Security.LogRedactor

  defmodule RecordingWriter do
    def create(attrs) do
      if test_pid = Process.get(:event_logger_test_pid) do
        send(test_pid, {:event_attrs, attrs})
      end

      {:ok, attrs}
    end
  end

  defmodule FailingRedactor do
    def redact_event(_data) do
      {:error, %{error_type: "forced_redaction_failure", message: "forced redaction failure for test"}}
    end

    def safe_inspect(_term), do: "[forced_redaction_failure]"
  end

  setup do
    Process.put(:event_logger_test_pid, self())

    original_redactor = Application.get_env(:jido_code, :forge_log_redactor, LogRedactor)
    original_writer = Application.get_env(:jido_code, :forge_event_writer, EventLogger.StoreEventWriter)

    on_exit(fn ->
      Process.delete(:event_logger_test_pid)
      Application.put_env(:jido_code, :forge_log_redactor, original_redactor)
      Application.put_env(:jido_code, :forge_event_writer, original_writer)
    end)

    Application.put_env(:jido_code, :forge_log_redactor, LogRedactor)
    Application.put_env(:jido_code, :forge_event_writer, RecordingWriter)
    :ok
  end

  test "persists redacted payload to event writer" do
    secret = "sk-test-0123456789abcdef"

    assert :ok =
             EventLogger.log_event("session-123", "session.failed", %{
               api_token: secret,
               message: "Authorization: Bearer #{secret}"
             })

    assert_receive {:event_attrs, attrs}

    assert attrs.session_id == "session-123"
    assert attrs.event_type == "session.failed"
    assert is_map(attrs.data)

    redacted_api_token = event_data_get(attrs.data, :api_token)
    redacted_message = event_data_get(attrs.data, :message)

    assert is_binary(redacted_api_token)
    assert redacted_api_token =~ "len="
    refute redacted_api_token == secret

    assert is_binary(redacted_message)
    assert redacted_message =~ "Bearer [REDACTED"
    refute redacted_message =~ secret
    refute inspect(attrs.data) =~ secret
  end

  test "blocks writer call and emits high-priority security log when redaction fails" do
    Application.put_env(:jido_code, :forge_log_redactor, FailingRedactor)
    secret = "sk-test-0123456789abcdef"

    log =
      capture_log([level: :error], fn ->
        assert :ok =
                 EventLogger.log_event("session-123", "session.failed", %{
                   api_token: secret
                 })

        Logger.flush()
      end)

    refute_received {:event_attrs, _attrs}
    assert log =~ "security_audit=forge_event_redaction_failed"
    assert log =~ "severity=high"
    assert log =~ "action=event_blocked"
    refute log =~ secret
  end

  defp event_data_get(event_data, key) when is_map(event_data) and is_atom(key) do
    Map.get(event_data, key) || Map.get(event_data, Atom.to_string(key))
  end
end
