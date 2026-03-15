defmodule JidoCode.Accounts.Checks.RegistrationAllowed do
  @moduledoc """
  Allows authentication interactions, while blocking open registration in production
  after the owner account exists.
  """
  # covers: users.admin_system.registration_guardrails
  # covers: users.admin_system.admin_managed_provisioning

  use Ash.Policy.SimpleCheck

  alias Ash.Query
  alias JidoCode.Accounts
  alias JidoCode.Accounts.User
  alias JidoCode.Setup.RuntimeMode

  @restricted_registration_actions [:register_with_password, :sign_in_with_magic_link]

  @impl true
  def match?(_actor, %{action: %{name: action_name}}, _opts) do
    {:ok, registration_allowed?(action_name)}
  end

  def match?(_actor, _context, _opts), do: {:ok, true}

  @impl true
  def describe(_opts) do
    "registration actions are restricted in production once an owner exists"
  end

  defp registration_allowed?(action_name) when action_name in @restricted_registration_actions do
    if RuntimeMode.production?() do
      not owner_exists?()
    else
      true
    end
  end

  defp registration_allowed?(_action_name), do: true

  defp owner_exists? do
    query = Query.limit(User, 1)

    case Ash.read(query, domain: Accounts, authorize?: false) do
      {:ok, []} -> false
      {:ok, _owners} -> true
      {:error, _reason} -> true
    end
  end
end
