defmodule JidoCode.Security.Encryption do
  # covers: setup.onboarding.github_pat_capture_requires_encryption_ready_secret_storage
  @moduledoc false

  alias Cloak.Ciphers.AES.GCM

  @aad_tag "JIDO.SECRETREF.V1"
  @iv_length 12

  @type config_status :: :ready | :missing | :invalid

  @spec config_status() :: config_status()
  def config_status do
    case Application.get_env(:jido_code, :secret_ref_encryption_key) do
      key when is_binary(key) ->
        case Base.decode64(key) do
          {:ok, decoded_key} when byte_size(decoded_key) == 32 -> :ready
          _other -> :invalid
        end

      _other ->
        :missing
    end
  end

  @spec encrypt(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def encrypt(value) when is_binary(value) do
    with {:ok, key} <- fetch_key(),
         {:ok, ciphertext} <- GCM.encrypt(value, key: key, tag: @aad_tag, iv_length: @iv_length) do
      {:ok, Base.encode64(ciphertext)}
    else
      {:error, :missing_key} ->
        {:error, :encryption_config_unavailable}

      {:error, :invalid_key} ->
        {:error, :encryption_config_unavailable}

      :error ->
        {:error, :encryption_failed}

      {:error, _reason} ->
        {:error, :encryption_failed}
    end
  rescue
    _error -> {:error, :encryption_failed}
  end

  def encrypt(_value), do: {:error, :encryption_failed}

  @spec decrypt(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def decrypt(encoded_ciphertext) when is_binary(encoded_ciphertext) do
    with {:ok, key} <- fetch_key(),
         {:ok, ciphertext} <- decode_ciphertext(encoded_ciphertext),
         {:ok, value} <- GCM.decrypt(ciphertext, key: key, tag: @aad_tag, iv_length: @iv_length) do
      {:ok, value}
    else
      {:error, :missing_key} ->
        {:error, :decryption_config_unavailable}

      {:error, :invalid_key} ->
        {:error, :decryption_config_unavailable}

      {:error, :invalid_ciphertext} ->
        {:error, :decryption_failed}

      :error ->
        {:error, :decryption_failed}

      {:error, _reason} ->
        {:error, :decryption_failed}
    end
  rescue
    _error -> {:error, :decryption_failed}
  end

  def decrypt(_encoded_ciphertext), do: {:error, :decryption_failed}

  defp fetch_key do
    case Application.get_env(:jido_code, :secret_ref_encryption_key) do
      key when is_binary(key) ->
        decode_key(key)

      _other ->
        {:error, :missing_key}
    end
  end

  defp decode_key(encoded_key) do
    case Base.decode64(encoded_key) do
      {:ok, decoded_key} when byte_size(decoded_key) == 32 ->
        {:ok, decoded_key}

      {:ok, _decoded_key} ->
        {:error, :invalid_key}

      :error ->
        {:error, :invalid_key}
    end
  end

  defp decode_ciphertext(encoded_ciphertext) do
    case Base.decode64(encoded_ciphertext) do
      {:ok, ciphertext} -> {:ok, ciphertext}
      :error -> {:error, :invalid_ciphertext}
    end
  end
end
