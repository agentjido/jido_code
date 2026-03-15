defmodule JidoCode.Setup.OwnerRecovery do
  @moduledoc """
  Handles setup step 2 owner credential recovery with explicit verification checks.
  """

  require Logger

  alias AshAuthentication.{Info, Strategy}
  alias AshAuthentication.Strategy.Password
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.OwnerBootstrap

  @audit_event [:jido_code, :auth, :owner_recovery, :completed]
  @verification_phrase "RECOVER OWNER ACCESS"
  @verification_denied_error "Owner recovery verification failed. Credential reset was denied and owner state is unchanged."
  @missing_recovery_fields_error "Owner recovery requires email and a new password."
  @password_confirmation_error "Owner recovery requires matching password confirmation."
  @verification_phrase_required_error "Owner recovery requires the verification phrase."
  @verification_ack_required_error "Owner recovery requires explicit recovery acknowledgement."
  @password_length_error "Owner recovery requires a password that is at least 8 characters."
  @recovery_unavailable_error "Owner recovery is unavailable because no owner account exists yet."
  @token_generation_error "Owner recovery could not generate a sign-in token."

  @typedoc """
  Recovery audit metadata captured on successful owner recovery.
  """
  @type audit_metadata :: %{
          route: String.t(),
          owner_id: Ecto.UUID.t() | String.t(),
          owner_email: String.t(),
          recovery_mode: :bootstrap,
          verified_at: DateTime.t(),
          verification_steps: [String.t()]
        }

  @typedoc """
  Result returned after a successful recovery.
  """
  @type result :: %{
          owner: User.t(),
          token: String.t(),
          owner_mode: :recovered,
          validated_note: String.t(),
          audit: audit_metadata()
        }

  @doc """
  Recovery phrase operators must type exactly in setup recovery.
  """
  @spec verification_phrase() :: String.t()
  def verification_phrase, do: @verification_phrase

  @doc """
  Resets existing owner credentials after explicit recovery verification checks.
  """
  @spec recover(map()) :: {:ok, result()} | {:error, {atom(), String.t()}}
  def recover(params) when is_map(params) do
    with {:ok, owner} <- fetch_owner_for_recovery(),
         {:ok, normalized_params} <- normalize_params(params),
         :ok <- verify_recovery(owner, normalized_params),
         {:ok, signed_in_owner} <- reset_and_sign_in(owner, normalized_params),
         {:ok, token} <- fetch_token(signed_in_owner) do
      audit = build_audit_metadata(signed_in_owner)
      emit_audit_event(audit)

      {:ok,
       %{
         owner: signed_in_owner,
         token: token,
         owner_mode: :recovered,
         validated_note: "Owner account recovered.",
         audit: audit
       }}
    else
      {:error, :verification_denied} ->
        {:error, {:verification_denied, @verification_denied_error}}

      {:error, {_error_type, _diagnostic} = typed_error} ->
        {:error, typed_error}
    end
  end

  def recover(_params), do: {:error, {:validation, @missing_recovery_fields_error}}

  @doc """
  Converts recovery audit metadata into setup step-state storage format.
  """
  @spec serialize_audit_for_state(audit_metadata()) :: map()
  def serialize_audit_for_state(audit_metadata) when is_map(audit_metadata) do
    %{
      "route" => Map.get(audit_metadata, :route, "/setup"),
      "owner_id" => to_string(Map.get(audit_metadata, :owner_id, "")),
      "owner_email" => to_string(Map.get(audit_metadata, :owner_email, "")),
      "recovery_mode" => audit_metadata |> Map.get(:recovery_mode, :bootstrap) |> Atom.to_string(),
      "verified_at" =>
        audit_metadata
        |> Map.get(:verified_at, DateTime.utc_now())
        |> DateTime.to_iso8601(),
      "verification_steps" => Map.get(audit_metadata, :verification_steps, verification_steps())
    }
  end

  def serialize_audit_for_state(_audit_metadata), do: %{}

  defp fetch_owner_for_recovery do
    case OwnerBootstrap.status() do
      {:ok, %{mode: :confirm, owner: owner}} ->
        {:ok, owner}

      {:ok, %{mode: :create}} ->
        {:error, {:owner_recovery_unavailable, @recovery_unavailable_error}}

      {:error, {_error_type, _diagnostic} = typed_error} ->
        {:error, typed_error}
    end
  end

  defp normalize_params(params) when is_map(params) do
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

    verification_phrase =
      params
      |> Map.get("verification_phrase", "")
      |> normalize_value()

    verification_ack =
      params
      |> Map.get("verification_ack", false)
      |> normalize_bool()

    cond do
      email == "" or password == "" ->
        {:error, {:validation, @missing_recovery_fields_error}}

      String.length(password) < 8 ->
        {:error, {:validation, @password_length_error}}

      password_confirmation == "" or password != password_confirmation ->
        {:error, {:validation, @password_confirmation_error}}

      verification_phrase == "" ->
        {:error, {:validation, @verification_phrase_required_error}}

      verification_ack != true ->
        {:error, {:validation, @verification_ack_required_error}}

      true ->
        {:ok,
         %{
           email: email,
           password: password,
           password_confirmation: password_confirmation,
           verification_phrase: verification_phrase,
           verification_ack: verification_ack
         }}
    end
  end

  defp normalize_params(_params), do: {:error, {:validation, @missing_recovery_fields_error}}

  defp verify_recovery(owner, normalized_params) do
    if same_email?(owner.email, normalized_params.email) and
         normalized_params.verification_phrase == @verification_phrase and normalized_params.verification_ack do
      :ok
    else
      {:error, :verification_denied}
    end
  end

  defp reset_and_sign_in(owner, normalized_params) do
    strategy = password_strategy()

    with {:ok, reset_token} <- Password.reset_token_for(strategy, owner),
         {:ok, _recovered_owner} <- run_reset(strategy, reset_token, normalized_params),
         {:ok, signed_in_owner} <- run_sign_in(strategy, normalized_params) do
      {:ok, signed_in_owner}
    else
      :error ->
        {:error, {:owner_recovery_failed, @token_generation_error}}

      {:error, reason} ->
        {:error, {:owner_recovery_failed, format_authentication_error(reason)}}
    end
  end

  defp run_reset(strategy, reset_token, normalized_params) do
    Strategy.action(
      strategy,
      :reset,
      %{
        "reset_token" => reset_token,
        "password" => normalized_params.password,
        "password_confirmation" => normalized_params.password_confirmation
      },
      context: %{token_type: :sign_in}
    )
  end

  defp run_sign_in(strategy, normalized_params) do
    Strategy.action(
      strategy,
      :sign_in,
      %{
        "email" => normalized_params.email,
        "password" => normalized_params.password
      },
      context: %{token_type: :sign_in}
    )
  end

  defp fetch_token(owner) do
    token =
      owner
      |> Map.get(:__metadata__, %{})
      |> Map.get(:token)

    if is_binary(token) and token != "" do
      {:ok, token}
    else
      {:error, {:owner_recovery_failed, @token_generation_error}}
    end
  end

  defp build_audit_metadata(owner) do
    %{
      route: "/setup",
      owner_id: Map.get(owner, :id),
      owner_email: to_string(Map.get(owner, :email, "")),
      recovery_mode: :bootstrap,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      verification_steps: verification_steps()
    }
  end

  defp emit_audit_event(audit_metadata) do
    measurements = %{count: 1, recovery_timestamp: System.system_time(:millisecond)}

    telemetry_metadata = %{
      route: audit_metadata.route,
      owner_id: audit_metadata.owner_id,
      owner_email: audit_metadata.owner_email,
      recovery_mode: Atom.to_string(audit_metadata.recovery_mode),
      verified_at: DateTime.to_iso8601(audit_metadata.verified_at),
      verification_steps: audit_metadata.verification_steps
    }

    :telemetry.execute(@audit_event, measurements, telemetry_metadata)

    Logger.info(
      "owner_recovery_audit=#{inspect(Map.merge(telemetry_metadata, %{recovery_timestamp: measurements.recovery_timestamp}))}"
    )
  end

  defp verification_steps do
    [
      "owner_email_match",
      "verification_phrase",
      "manual_acknowledgement"
    ]
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

  defp normalize_exception_message(""), do: "Owner recovery failed."
  defp normalize_exception_message(message), do: message

  defp normalize_bool(true), do: true
  defp normalize_bool("true"), do: true
  defp normalize_bool("1"), do: true
  defp normalize_bool(1), do: true
  defp normalize_bool("on"), do: true
  defp normalize_bool(_value), do: false

  defp normalize_value(value) when is_binary(value), do: String.trim(value)
  defp normalize_value(_value), do: ""

  defp same_email?(left, right) do
    left
    |> to_string()
    |> String.downcase()
    |> Kernel.==(String.downcase(right))
  end
end
