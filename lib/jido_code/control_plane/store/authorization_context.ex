defmodule JidoCode.ControlPlane.Store.AuthorizationContext do
  @moduledoc """
  Authorization decision carried with a store request.
  """

  defstruct mode: :system,
            allowed?: true,
            scopes: [],
            reason: nil,
            metadata: %{}

  @type mode :: :human_operator | :machine_actor | :setup_bootstrap | :system

  @type t :: %__MODULE__{
          mode: mode(),
          allowed?: boolean(),
          scopes: [atom()],
          reason: term(),
          metadata: map()
        }

  @spec allow(mode(), [atom()], map()) :: t()
  def allow(mode \\ :system, scopes \\ [], metadata \\ %{}) do
    %__MODULE__{mode: mode, allowed?: true, scopes: scopes, metadata: metadata}
  end

  @spec deny(mode(), term(), map()) :: t()
  def deny(mode, reason, metadata \\ %{}) do
    %__MODULE__{mode: mode, allowed?: false, reason: reason, metadata: metadata}
  end
end
