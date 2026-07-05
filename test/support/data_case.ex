defmodule JidoCode.DataCase do
  @moduledoc """
  This module defines the setup for tests requiring
  access to the application's embedded data layer.

  You may define functions here to be used as helpers in
  your tests.

  Tests that need product persistence should start isolated store instances
  through the relevant helper for the surface under test.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import JidoCode.DataCase
    end
  end

  setup _tags do
    JidoCode.DataCase.setup_policy_actor()
    :ok
  end

  @doc """
  Kept as a no-op compatibility hook while fixtures move to isolated embedded stores.
  """
  def setup_sandbox(_tags), do: :ok

  @doc """
  Seeds a default operator-class actor for direct resource calls in tests.
  """
  def setup_policy_actor do
    alias JidoCode.Control.Actor

    Actor.put_policy_actor(
      Actor.operator_actor(%{
        "id" => "test:operator",
        "email" => "test-operator@example.com"
      })
    )

    on_exit(fn -> Actor.clear_policy_actor() end)
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, validation} = Accounts.create_user(%{password: "short"})
      assert "password is too short" in errors_on(validation).password
      assert %{password: ["password is too short"]} = errors_on(validation)

  """
  def errors_on(%{errors: errors}) when is_map(errors), do: errors
  def errors_on(errors) when is_map(errors), do: errors
  def errors_on(_validation), do: %{}
end
