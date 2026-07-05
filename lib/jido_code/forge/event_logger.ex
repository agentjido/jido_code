defmodule JidoCode.Forge.EventLogger do
  @moduledoc """
  Writes Forge event records with mandatory redaction.
  """

  require Logger

  alias JidoCode.Security.LogRedactor

  defmodule StoreEventWriter do
    @moduledoc false

    alias JidoCode.ExecutionRuntime.RecordStore
    alias JidoCode.Forge.Resources.Event

    @spec create(map()) :: {:ok, Event.t()} | {:error, term()}
    def create(attrs), do: RecordStore.create_runtime_event(attrs)
  end

  @spec log_event(String.t(), String.t(), map(), keyword()) :: :ok
  def log_event(session_id, event_type, data, opts \\ [])

  def log_event(session_id, event_type, data, opts) when is_binary(event_type) and is_map(data) do
    with {:ok, redacted_data} <- redact_data(data),
         {:ok, _event} <- create_event(session_id, event_type, redacted_data, opts) do
      :ok
    else
      {:error, {:redaction_failed, reason}} ->
        emit_redaction_failure(session_id, event_type, reason)
        :ok

      {:error, reason} ->
        Logger.warning(
          "forge_event_persistence_failed session_id=#{session_id} event_type=#{event_type} reason=#{LogRedactor.safe_inspect(reason)}"
        )

        :ok
    end
  end

  def log_event(session_id, event_type, _data, _opts) do
    emit_redaction_failure(session_id, event_type, %{error_type: "redaction_invalid_payload"})
    :ok
  end

  defp redact_data(data) do
    redactor = redactor_module()

    try do
      case redactor.redact_event(data) do
        {:ok, redacted_data} when is_map(redacted_data) ->
          {:ok, redacted_data}

        {:error, reason} ->
          {:error, {:redaction_failed, reason}}

        _other ->
          {:error,
           {:redaction_failed, %{error_type: "redaction_invalid_response", message: "Unexpected redactor response."}}}
      end
    rescue
      _exception ->
        {:error, {:redaction_failed, %{error_type: "redaction_exception", message: "Redaction raised unexpectedly."}}}
    catch
      _kind, _reason ->
        {:error, {:redaction_failed, %{error_type: "redaction_crash", message: "Redaction crashed unexpectedly."}}}
    end
  end

  defp create_event(session_id, event_type, redacted_data, opts) do
    attrs =
      %{
        session_id: session_id,
        event_type: event_type,
        data: redacted_data
      }
      |> maybe_put_exec_sequence(Keyword.get(opts, :exec_session_sequence))

    event_writer_module().create(attrs)
  end

  defp maybe_put_exec_sequence(attrs, sequence) when is_integer(sequence) do
    Map.put(attrs, :exec_session_sequence, sequence)
  end

  defp maybe_put_exec_sequence(attrs, _sequence), do: attrs

  defp redactor_module do
    Application.get_env(:jido_code, :forge_log_redactor, LogRedactor)
  end

  defp event_writer_module do
    Application.get_env(:jido_code, :forge_event_writer, StoreEventWriter)
  end

  defp emit_redaction_failure(session_id, event_type, reason) do
    Logger.error(
      "security_audit=forge_event_redaction_failed severity=high session_id=#{session_id} event_type=#{event_type} action=event_blocked reason_type=#{reason_type(reason)}"
    )
  end

  defp reason_type(%{error_type: error_type}) when is_binary(error_type), do: sanitize_reason_type(error_type)
  defp reason_type(%{"error_type" => error_type}) when is_binary(error_type), do: sanitize_reason_type(error_type)
  defp reason_type(reason) when is_atom(reason), do: reason |> Atom.to_string() |> sanitize_reason_type()
  defp reason_type(_reason), do: "unknown"

  defp sanitize_reason_type(type) do
    String.replace(type, ~r/[^a-zA-Z0-9._-]/, "_")
  end
end
