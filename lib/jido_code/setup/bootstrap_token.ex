defmodule JidoCode.Setup.BootstrapToken do
  @moduledoc """
  Signed bootstrap handoff tokens for setup-owned owner creation.

  The token only carries identity needed to continue setup. General session,
  password reset, magic-link, and API-key tokens are implemented by the auth
  service layer rather than by this setup helper.
  """

  alias JidoCode.Accounts.User
  alias JidoCodeWeb.Endpoint

  @default_salt "setup-owner-bootstrap"
  @default_max_age_seconds 600

  @spec issue(User.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def issue(%User{} = owner, opts \\ []) do
    with id when is_binary(id) and id != "" <- Map.get(owner, :id),
         email when is_binary(email) and email != "" <- owner |> Map.get(:email) |> to_string() do
      token =
        Phoenix.Token.sign(Endpoint, salt(opts), %{
          "purpose" => "owner_bootstrap",
          "user_id" => id,
          "email" => email
        })

      {:ok, token}
    else
      _other -> {:error, :invalid_owner}
    end
  end

  @spec verify(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def verify(token, opts \\ [])

  def verify(token, opts) when is_binary(token) and token != "" do
    case Phoenix.Token.verify(Endpoint, salt(opts), token, max_age: max_age(opts)) do
      {:ok, %{"purpose" => "owner_bootstrap"} = claims} -> {:ok, claims}
      {:ok, _claims} -> {:error, :invalid_purpose}
      {:error, reason} -> {:error, reason}
    end
  end

  def verify(_token, _opts), do: {:error, :invalid_token}

  defp salt(opts),
    do: Keyword.get(opts, :salt, Application.get_env(:jido_code, :setup_bootstrap_token_salt, @default_salt))

  defp max_age(opts) do
    Keyword.get(
      opts,
      :max_age,
      Application.get_env(:jido_code, :setup_bootstrap_token_max_age_seconds, @default_max_age_seconds)
    )
  end
end
