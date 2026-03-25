defmodule JidoCode.Accounts.Checks.RegistrationAllowed do
  @moduledoc """
  Allows authentication interactions, while blocking open registration in production
  once a local user already exists.
  """

  # covers: users.admin_system.registration_guardrails
  # covers: users.admin_system.admin_managed_provisioning

  use Ash.Policy.SimpleCheck

  alias JidoCode.Setup.BootstrapStatus

  @restricted_registration_actions [:register_with_password]

  @impl true
  def match?(_actor, %{action: %{name: action_name}}, _opts) do
    {:ok, registration_allowed?(action_name)}
  end

  def match?(_actor, _context, _opts), do: {:ok, true}

  @impl true
  def describe(_opts) do
    "registration actions are restricted once the first local user exists"
  end

  defp registration_allowed?(action_name) when action_name in @restricted_registration_actions do
    not BootstrapStatus.first_user_exists?()
  end

  defp registration_allowed?(_action_name), do: true
end
