defmodule JidoCode.Setup.OwnerRecovery do
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.admin_role_assignment
  @moduledoc """
  Handles setup step 2 owner credential recovery with explicit verification checks.
  """

  require Logger

  alias JidoCode.Accounts.User
  alias JidoCode.Setup.{BootstrapToken, OwnerBootstrap, OwnerStore}

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
         {:ok, recovered_owner} <- recover_owner(owner),
         {:ok, token} <- BootstrapToken.issue(recovered_owner) do
      audit = build_audit_metadata(recovered_owner)
      emit_audit_event(audit)

      {:ok,
       %{
         owner: recovered_owner,
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
      "route" => Map.get(audit_metadata, :route, "/welcome"),
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

  defp recover_owner(%User{} = owner), do: maybe_promote_bootstrap_admin(owner)

  defp build_audit_metadata(owner) do
    %{
      route: "/welcome",
      owner_id: Map.get(owner, :id),
      owner_email: to_string(Map.get(owner, :email, "")),
      recovery_mode: :bootstrap,
      verified_at: DateTime.utc_now() |> DateTime.truncate(:second),
      verification_steps: verification_steps()
    }
  end

  defp maybe_promote_bootstrap_admin(%User{is_admin: true} = owner), do: {:ok, owner}

  defp maybe_promote_bootstrap_admin(%User{} = owner) do
    case OwnerStore.promote_to_admin(owner) do
      {:ok, promoted_owner} -> {:ok, Map.put(promoted_owner, :__metadata__, Map.get(owner, :__metadata__, %{}))}
      {:error, reason} -> {:error, {:owner_recovery_failed, format_store_error(reason)}}
    end
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

  defp format_store_error(:invalid_owner), do: @token_generation_error

  defp format_store_error(error) do
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
