defmodule JidoCode.Session.Persistence.Crypto do
  @moduledoc """
  Cryptographic operations for session file integrity verification.

  Provides HMAC-SHA256 signing and verification for persisted session files
  to prevent tampering. Uses a machine-specific signing key derived from
  the application's compile-time salt and hostname.

  ## Security Model

  - **Algorithm:** HMAC-SHA256
  - **Key Derivation:** PBKDF2 with application salt + hostname
  - **Signature Location:** `signature` field in JSON (excluded from signed payload)
  - **Backward Compatibility:** Unsigned files accepted with warning (v1.0.0)

  ## Example

      iex> data = %{id: "uuid", name: "Session"}
      iex> signed = Crypto.sign_payload(data)
      iex> Crypto.verify_payload(signed)
      {:ok, %{id: "uuid", name: "Session"}}

      iex> tampered = Map.put(signed, "name", "Tampered")
      iex> Crypto.verify_payload(tampered)
      {:error, :signature_verification_failed}
  """

  require Logger

  @hash_algorithm :sha256
  @iterations 100_000
  @key_length 32

  # Compile-time application salt (changes per release)
  @app_salt Application.compile_env(:jido_code, :signing_salt, "jido_code_session_v1")

  @typedoc "Signed payload with signature field"
  @type signed_payload :: %{required(String.t()) => term(), required(String.t()) => String.t()}

  @doc """
  Computes HMAC-SHA256 signature for a JSON string.

  Returns a Base64-encoded signature that can be verified later.

  ## Parameters

  - `json_string` - JSON-encoded string to sign

  ## Returns

  - Base64-encoded signature string

  ## Examples

      iex> json = Jason.encode!(%{id: "123", data: "test"})
      iex> signature = Crypto.compute_signature(json)
      iex> is_binary(signature)
      true
  """
  @spec compute_signature(String.t()) :: String.t()
  def compute_signature(json_string) when is_binary(json_string) do
    :crypto.mac(:hmac, @hash_algorithm, signing_key(), json_string)
    |> Base.encode64()
  end

  @doc """
  Verifies HMAC signature over JSON payload.

  Extracts the signature from the parsed map, recomputes HMAC over the
  payload (without signature), and compares. Uses constant-time comparison
  to prevent timing attacks.

  ## Parameters

  - `unsigned_json` - JSON string of payload WITHOUT signature field
  - `provided_signature` - Base64-encoded signature to verify

  ## Returns

  - `:ok` - Signature is valid
  - `{:error, :signature_verification_failed}` - Signature is invalid

  ## Examples

      iex> json = Jason.encode!(%{data: "test"})
      iex> signature = Crypto.compute_signature(json)
      iex> Crypto.verify_signature(json, signature)
      :ok
  """
  @spec verify_signature(String.t(), String.t()) :: :ok | {:error, :signature_verification_failed}
  def verify_signature(unsigned_json, provided_signature)
      when is_binary(unsigned_json) and is_binary(provided_signature) do
    expected_signature = compute_signature(unsigned_json)

    # Constant-time comparison to prevent timing attacks
    if secure_compare(provided_signature, expected_signature) do
      :ok
    else
      {:error, :signature_verification_failed}
    end
  end

  @doc """
  Checks if a payload has a signature field.

  Useful for determining if file is signed or legacy unsigned format.

  ## Examples

      iex> Crypto.signed?(%{"signature" => "..."})
      true

      iex> Crypto.signed?(%{data: "test"})
      false
  """
  @spec signed?(map()) :: boolean()
  def signed?(payload) when is_map(payload) do
    Map.has_key?(payload, "signature")
  end

  # Private Functions

  # Derives a deterministic but machine-specific signing key
  defp signing_key do
    # Combine application salt with hostname for machine specificity
    # This prevents sessions from being copied between machines
    hostname = get_hostname()
    salt = @app_salt <> hostname

    # Use PBKDF2 to derive a strong key
    :crypto.pbkdf2_hmac(
      @hash_algorithm,
      @app_salt,
      salt,
      @iterations,
      @key_length
    )
  end

  # Gets the machine hostname
  defp get_hostname do
    case :inet.gethostname() do
      {:ok, hostname} -> to_string(hostname)
      {:error, _} -> "localhost"
    end
  end

  # Constant-time string comparison to prevent timing attacks
  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    if byte_size(a) == byte_size(b) do
      secure_compare(a, b, 0) == 0
    else
      false
    end
  end

  defp secure_compare(<<x, rest_a::binary>>, <<y, rest_b::binary>>, acc) do
    import Bitwise
    secure_compare(rest_a, rest_b, bor(acc, bxor(x, y)))
  end

  defp secure_compare(<<>>, <<>>, acc), do: acc
end
