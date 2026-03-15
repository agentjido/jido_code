defmodule JidoCode.Setup.OwnerBootstrap do
  @moduledoc """
  Handles setup step 2 owner bootstrap in single-user mode.
  """

  alias AshAuthentication.{Info, Strategy}
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User

  @single_user_policy_error "Single-user policy error: an owner account already exists."
  @missing_credentials_error "Owner bootstrap requires email and password."
  @email_format_error "Owner bootstrap requires a valid email address."
  @password_confirmation_error "Owner bootstrap requires matching password confirmation."
  @password_length_error "Owner bootstrap requires a password that is at least 8 characters."
  @token_generation_error "Owner bootstrap could not generate a sign-in token."

  @typedoc """
  Owner bootstrap status for setup step 2.
  """
  @type status ::
          %{mode: :create, owner: nil}
          | %{mode: :confirm, owner: User.t()}

  @typedoc """
  Result returned after a successful owner bootstrap action.
  """
  @type result :: %{
          owner: User.t(),
          token: String.t(),
          owner_mode: :created | :confirmed,
          validated_note: String.t()
        }

  @doc """
  Returns whether setup should create a new owner or confirm an existing owner.
  """
  @spec status() :: {:ok, status()} | {:error, {atom(), String.t()}}
  def status do
    case list_owners() do
      {:ok, []} ->
        {:ok, %{mode: :create, owner: nil}}

      {:ok, [owner]} ->
        {:ok, %{mode: :confirm, owner: owner}}

      {:ok, owners} ->
        {:error,
         {:single_user_policy, "Single-user policy error: expected exactly one owner account, found #{length(owners)}."}}

      {:error, reason} ->
        {:error, {:owner_lookup_failed, "Unable to read owner account state (#{inspect(reason)})."}}
    end
  end

  @doc """
  Creates the owner account if none exists, or confirms the existing owner account.
  """
  @spec bootstrap(map()) :: {:ok, result()} | {:error, {atom(), String.t()}}
  def bootstrap(params) when is_map(params) do
    with {:ok, owner_status} <- status(),
         {:ok, normalized_params} <- normalize_params(params, owner_status.mode) do
      do_bootstrap(owner_status, normalized_params)
    end
  end

  def bootstrap(_params), do: {:error, {:validation, @missing_credentials_error}}

  defp do_bootstrap(%{mode: :create}, normalized_params) do
    strategy = password_strategy()

    register_params = %{
      "email" => normalized_params.email,
      "password" => normalized_params.password,
      "password_confirmation" => normalized_params.password_confirmation
    }

    case Strategy.action(strategy, :register, register_params, context: %{token_type: :sign_in}) do
      {:ok, owner} ->
        owner_result(owner, :created)

      {:error, reason} ->
        {:error, {:owner_bootstrap_failed, format_authentication_error(reason)}}
    end
  end

  defp do_bootstrap(%{mode: :confirm, owner: owner}, normalized_params) do
    if same_email?(owner.email, normalized_params.email) do
      strategy = password_strategy()

      sign_in_params = %{
        "email" => normalized_params.email,
        "password" => normalized_params.password
      }

      case Strategy.action(strategy, :sign_in, sign_in_params, context: %{token_type: :sign_in}) do
        {:ok, confirmed_owner} ->
          owner_result(confirmed_owner, :confirmed)

        {:error, reason} ->
          {:error, {:owner_bootstrap_failed, format_authentication_error(reason)}}
      end
    else
      {:error, {:single_user_policy, @single_user_policy_error}}
    end
  end

  defp owner_result(owner, owner_mode) do
    case fetch_token(owner) do
      {:ok, token} ->
        {:ok,
         %{
           owner: owner,
           token: token,
           owner_mode: owner_mode,
           validated_note: validated_note(owner_mode)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_token(owner) do
    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.get(:token)

    if is_binary(token) and token != "" do
      {:ok, token}
    else
      {:error, {:owner_bootstrap_failed, @token_generation_error}}
    end
  end

  defp validated_note(:created), do: "Owner account bootstrapped."
  defp validated_note(:confirmed), do: "Owner account confirmed."

  defp normalize_params(params, mode) do
    email =
      params
      |> Map.get("email", "")
      |> normalize_value()

    password =
      params
      |> Map.get("password", "")
      |> normalize_value()

    password_confirmation =
      params
      |> Map.get("password_confirmation", "")
      |> normalize_value()

    cond do
      email == "" or password == "" ->
        {:error, {:validation, @missing_credentials_error}}

      mode == :create and not valid_email?(email) ->
        {:error, {:validation, @email_format_error}}

      mode == :create and String.length(password) < 8 ->
        {:error, {:validation, @password_length_error}}

      mode == :create and password_confirmation == "" ->
        {:error, {:validation, @password_confirmation_error}}

      mode == :create and password != password_confirmation ->
        {:error, {:validation, @password_confirmation_error}}

      true ->
        {:ok,
         %{
           email: email,
           password: password,
           password_confirmation: password_confirmation
         }}
    end
  end

  defp list_owners do
    Ash.read(User, domain: Accounts, authorize?: false)
  end

  defp password_strategy do
    Info.strategy!(User, :password)
  end

  defp format_authentication_error(error) do
    case error do
      exception when is_exception(exception) ->
        exception
        |> Exception.message()
        |> normalize_exception_message()

      other ->
        inspect(other)
    end
  end

  defp normalize_exception_message(""), do: "Owner bootstrap failed."
  defp normalize_exception_message(message), do: message

  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(_value), do: ""

  defp valid_email?(email) do
    Regex.match?(~r/^[^\s]+@[^\s]+\.[^\s]+$/, email)
  end

  defp same_email?(left, right) do
    left
    |> to_string()
    |> String.downcase()
    |> Kernel.==(String.downcase(right))
  end
end
