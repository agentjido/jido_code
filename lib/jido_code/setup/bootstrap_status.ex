defmodule JidoCode.Setup.BootstrapStatus do
  # covers: users.admin_system.bootstrap_admin
  # covers: users.admin_system.registration_guardrails
  @moduledoc """
  Resolves the public bootstrap state for first-run entry, auth routing, and setup gating.
  """

  alias JidoCode.Accounts.User
  alias JidoCode.Setup.{OwnerStore, SystemConfig}

  @typedoc """
  Product-level first-run state for public entry and onboarding.
  """
  @type state :: :bootstrap_required | :continue_setup | :ready | :invalid_state

  @type t :: %{
          state: state(),
          user_count: non_neg_integer(),
          primary_user: User.t() | nil,
          primary_user_email: String.t() | nil,
          onboarding_completed: boolean(),
          onboarding_step: pos_integer(),
          diagnostic: String.t() | nil,
          legacy_ready: boolean(),
          config: SystemConfig.t() | nil
        }

  @invalid_no_user_message "Onboarding is marked complete, but no local user exists."
  @invalid_bootstrap_message "Bootstrap state is inconsistent. Repair the local user/admin state before continuing."

  @spec current() :: t()
  def current do
    with {:ok, config} <- load_config(),
         {:ok, users} <- load_users() do
      resolve_status(config, users)
    else
      {:error, diagnostic} ->
        invalid_state(nil, 0, diagnostic)
    end
  end

  @spec bootstrap_required?() :: boolean()
  def bootstrap_required?, do: current().state == :bootstrap_required

  @spec continue_setup?() :: boolean()
  def continue_setup?, do: current().state == :continue_setup

  @spec ready?() :: boolean()
  def ready?, do: current().state == :ready

  @spec provider_login_available?() :: boolean()
  def provider_login_available? do
    case current().state do
      :bootstrap_required -> false
      :invalid_state -> false
      _other -> true
    end
  end

  @spec first_user_exists?() :: boolean()
  def first_user_exists?, do: current().user_count > 0

  defp resolve_status(%SystemConfig{} = config, users) when is_list(users) do
    user_count = length(users)
    primary_user = primary_user(users)
    blank_onboarding? = blank_onboarding?(config)

    cond do
      config.onboarding_completed and user_count == 0 ->
        invalid_state(config, user_count, @invalid_no_user_message)

      config.onboarding_completed and user_count > 0 ->
        ready_state(config, users, primary_user, false)

      user_count == 0 ->
        bootstrap_required_state(config)

      blank_onboarding? ->
        ready_state(config, users, primary_user, true)

      primary_user != nil ->
        continue_setup_state(config, users, primary_user)

      true ->
        invalid_state(config, user_count, @invalid_bootstrap_message)
    end
  end

  defp bootstrap_required_state(%SystemConfig{} = config) do
    %{
      state: :bootstrap_required,
      user_count: 0,
      primary_user: nil,
      primary_user_email: nil,
      onboarding_completed: false,
      onboarding_step: config.onboarding_step,
      diagnostic: nil,
      legacy_ready: false,
      config: config
    }
  end

  defp continue_setup_state(%SystemConfig{} = config, users, %User{} = primary_user) do
    %{
      state: :continue_setup,
      user_count: length(users),
      primary_user: primary_user,
      primary_user_email: to_string(primary_user.email),
      onboarding_completed: false,
      onboarding_step: config.onboarding_step,
      diagnostic: nil,
      legacy_ready: false,
      config: config
    }
  end

  defp ready_state(%SystemConfig{} = config, users, primary_user, legacy_ready?) do
    %{
      state: :ready,
      user_count: length(users),
      primary_user: primary_user,
      primary_user_email: primary_email(primary_user),
      onboarding_completed: config.onboarding_completed or legacy_ready?,
      onboarding_step: config.onboarding_step,
      diagnostic: nil,
      legacy_ready: legacy_ready?,
      config: config
    }
  end

  defp invalid_state(config, user_count, diagnostic) do
    %{
      state: :invalid_state,
      user_count: user_count,
      primary_user: nil,
      primary_user_email: nil,
      onboarding_completed: false,
      onboarding_step: config_step(config),
      diagnostic: diagnostic,
      legacy_ready: false,
      config: config
    }
  end

  defp load_config do
    case SystemConfig.load() do
      {:ok, %SystemConfig{} = config} ->
        {:ok, config}

      {:error, %{diagnostic: diagnostic}} ->
        {:error, diagnostic}
    end
  end

  defp load_users do
    case OwnerStore.list_users() do
      {:ok, users} when is_list(users) ->
        {:ok, users}

      {:error, reason} ->
        {:error, "Unable to read local user state (#{inspect(reason)})."}
    end
  end

  defp primary_user(users) do
    admins = Enum.filter(users, &Map.get(&1, :is_admin, false))

    case {admins, users} do
      {[admin], _users} -> admin
      {[], [single_user]} -> single_user
      _other -> nil
    end
  end

  defp blank_onboarding?(%SystemConfig{} = config) do
    config.onboarding_completed == false and config.onboarding_step == 1 and config.onboarding_state == %{}
  end

  defp primary_email(nil), do: nil
  defp primary_email(%User{} = user), do: to_string(user.email)

  defp config_step(%SystemConfig{} = config), do: config.onboarding_step
  defp config_step(_config), do: 1
end
