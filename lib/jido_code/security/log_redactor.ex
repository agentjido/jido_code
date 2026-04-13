defmodule JidoCode.Security.LogRedactor do
  @moduledoc """
  Redacts secret-like values from event payloads and logger output.
  """

  @type redaction_error :: %{
          error_type: String.t(),
          message: String.t()
        }

  @secret_key_pattern ~r/(^|_|-)(secret|token|password|credential|authorization|api[_-]?key|private[_-]?key|access[_-]?token|refresh[_-]?token)(_|-|$)/i

  @assignment_secret_pattern ~r/((?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|credential)\s*[:=]\s*)([^,\s;]+)/iu
  @bearer_token_pattern ~r/\b(Bearer\s+)([A-Za-z0-9\-\._~\+\/=]{8,})\b/u
  @openai_token_pattern ~r/\b(sk-[A-Za-z0-9\-_]{12,})\b/u
  @github_token_pattern ~r/\b(gh[pousr]_[A-Za-z0-9]{12,})\b/u
  @github_pat_pattern ~r/\b(github_pat_[A-Za-z0-9_]{12,})\b/u
  @jwt_pattern ~r/\b([A-Za-z0-9\-_]{16,}\.[A-Za-z0-9\-_]{16,}\.[A-Za-z0-9\-_]{16,})\b/u

  @spec redact_event(map()) :: {:ok, map()} | {:error, redaction_error()}
  def redact_event(data) when is_map(data) do
    try do
      redact_term(data, nil)
    rescue
      exception ->
        {:error, redaction_error("redaction_exception", Exception.message(exception))}
    catch
      kind, _reason ->
        {:error, redaction_error("redaction_#{kind}", "Redaction pipeline crashed unexpectedly.")}
    end
  end

  def redact_event(_data) do
    {:error, redaction_error("redaction_invalid_payload", "Expected map payload for event redaction.")}
  end

  @spec redact_string(binary()) :: {:ok, binary()} | {:error, redaction_error()}
  def redact_string(value) when is_binary(value) do
    try do
      if String.valid?(value) do
        redacted =
          value
          |> redact_assignment_pairs()
          |> redact_bearer_tokens()
          |> redact_known_token_patterns()

        {:ok, redacted}
      else
        {:ok, "[REDACTED_BINARY bytes=#{byte_size(value)}]"}
      end
    rescue
      exception ->
        {:error, redaction_error("redaction_string_failed", Exception.message(exception))}
    end
  end

  @spec safe_inspect(term()) :: String.t()
  def safe_inspect(term) do
    term
    |> inspect(limit: 50, printable_limit: 5_000)
    |> redact_string()
    |> case do
      {:ok, redacted} -> redacted
      {:error, _reason} -> "[UNAVAILABLE_REDACTED_INSPECT]"
    end
  end

  defp redact_term(value, _key_context) when is_number(value) or is_boolean(value) or is_nil(value),
    do: {:ok, value}

  defp redact_term(value, _key_context) when is_binary(value) do
    redact_string(value)
  end

  defp redact_term(value, key_context) when is_list(value) do
    value
    |> Enum.reduce_while({:ok, []}, fn item, {:ok, acc} ->
      case redact_term(item, key_context) do
        {:ok, redacted_item} ->
          {:cont, {:ok, [redacted_item | acc]}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, redacted_values} -> {:ok, Enum.reverse(redacted_values)}
      {:error, _reason} = error -> error
    end
  end

  defp redact_term(value, key_context) when is_tuple(value) do
    value
    |> Tuple.to_list()
    |> redact_term(key_context)
    |> case do
      {:ok, redacted_values} -> {:ok, List.to_tuple(redacted_values)}
      {:error, _reason} = error -> error
    end
  end

  defp redact_term(%_{} = value, key_context) do
    struct_module = value.__struct__

    value
    |> Map.from_struct()
    |> redact_term(key_context)
    |> case do
      {:ok, redacted_fields} when is_map(redacted_fields) ->
        {:ok, struct(struct_module, redacted_fields)}

      {:error, _reason} = error ->
        error
    end
  end

  defp redact_term(value, _key_context) when is_map(value) do
    value
    |> Enum.reduce_while({:ok, %{}}, fn {key, nested_value}, {:ok, acc} ->
      case redact_for_key(key, nested_value) do
        {:ok, redacted_value} ->
          {:cont, {:ok, Map.put(acc, key, redacted_value)}}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
  end

  defp redact_term(value, _key_context), do: {:ok, value}

  defp redact_for_key(key, value) do
    if secret_key?(key) do
      {:ok, mask_secret_value(value)}
    else
      redact_term(value, key)
    end
  end

  defp redact_assignment_pairs(text) do
    Regex.replace(@assignment_secret_pattern, text, fn _, prefix, secret_value ->
      prefix <> mask_secret_binary(secret_value)
    end)
  end

  defp redact_bearer_tokens(text) do
    Regex.replace(@bearer_token_pattern, text, fn _, prefix, token ->
      prefix <> mask_secret_binary(token)
    end)
  end

  defp redact_known_token_patterns(text) do
    [@openai_token_pattern, @github_token_pattern, @github_pat_pattern, @jwt_pattern]
    |> Enum.reduce(text, fn pattern, acc ->
      Regex.replace(pattern, acc, fn _, token -> mask_secret_binary(token) end)
    end)
  end

  defp secret_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> secret_key?()
  end

  defp secret_key?(key) when is_binary(key) do
    Regex.match?(@secret_key_pattern, key)
  end

  defp secret_key?(key), do: key |> inspect() |> secret_key?()

  defp mask_secret_value(value) when is_binary(value), do: mask_secret_binary(value)
  defp mask_secret_value(value) when is_list(value), do: "[REDACTED_LIST count=#{length(value)}]"
  defp mask_secret_value(value) when is_tuple(value), do: "[REDACTED_TUPLE size=#{tuple_size(value)}]"
  defp mask_secret_value(value) when is_map(value), do: "[REDACTED_MAP keys=#{map_size(value)}]"
  defp mask_secret_value(_value), do: "[REDACTED]"

  defp mask_secret_binary(value) when is_binary(value) do
    length = byte_size(value)

    cond do
      length == 0 ->
        "[REDACTED len=0]"

      length <= 4 ->
        "[REDACTED len=#{length}]"

      true ->
        prefix = safe_fragment(binary_part(value, 0, 2))
        suffix = safe_fragment(binary_part(value, length - 2, 2))
        "[REDACTED #{prefix}...#{suffix} len=#{length}]"
    end
  end

  defp safe_fragment(fragment) do
    if String.valid?(fragment) and String.printable?(fragment) do
      fragment
    else
      Base.encode16(fragment, case: :lower)
    end
  end

  defp redaction_error(error_type, message) do
    %{error_type: error_type, message: message}
  end
end
