defmodule JidoCode.CodeServer.Error do
  @moduledoc """
  Typed error helpers for `JidoCode.CodeServer`.
  """

  @type typed_error :: %{
          error_type: String.t(),
          detail: String.t(),
          remediation: String.t(),
          project_id: String.t() | nil,
          conversation_id: String.t() | nil
        }

  @default_remediation """
  Retry the request. If this persists, verify workspace readiness and runtime configuration.
  """

  @spec build(String.t(), String.t(), String.t() | nil, keyword()) :: typed_error()
  def build(error_type, detail, remediation \\ nil, opts \\ [])
      when is_binary(error_type) and is_binary(detail) and is_list(opts) do
    %{
      error_type: normalize_error_type(error_type),
      detail: detail,
      remediation: normalize_remediation(remediation),
      project_id: normalize_optional_string(Keyword.get(opts, :project_id)),
      conversation_id: normalize_optional_string(Keyword.get(opts, :conversation_id))
    }
  end

  defp normalize_error_type(error_type) do
    error_type
    |> String.trim()
    |> case do
      "" -> "code_server_unexpected_error"
      value -> value
    end
  end

  defp normalize_remediation(nil), do: String.trim(@default_remediation)

  defp normalize_remediation(remediation) when is_binary(remediation) do
    remediation
    |> String.trim()
    |> case do
      "" -> String.trim(@default_remediation)
      value -> value
    end
  end

  defp normalize_remediation(_other), do: String.trim(@default_remediation)

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_optional_string()

  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_value), do: nil
end
