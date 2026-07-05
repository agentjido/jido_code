defmodule JidoCode.ControlPlane.Store.ActorContext do
  @moduledoc """
  Actor metadata attached to store requests.
  """

  @enforce_keys [:id, :type]
  defstruct [:id, :type, roles: [], metadata: %{}]

  @type t :: %__MODULE__{
          id: String.t(),
          type: :human | :machine | :system | :setup,
          roles: [atom()],
          metadata: map()
        }

  @spec system(String.t(), map()) :: t()
  def system(id \\ "system:control-plane", metadata \\ %{}) do
    %__MODULE__{id: id, type: :system, roles: [:system], metadata: metadata}
  end

  @spec human_operator(String.t(), [atom()], map()) :: t()
  def human_operator(id, roles \\ [], metadata \\ %{}) do
    %__MODULE__{id: id, type: :human, roles: roles, metadata: metadata}
  end

  @spec machine_actor(String.t(), [atom()], map()) :: t()
  def machine_actor(id, roles \\ [], metadata \\ %{}) do
    %__MODULE__{id: id, type: :machine, roles: roles, metadata: metadata}
  end

  @spec setup_bootstrap(String.t(), map()) :: t()
  def setup_bootstrap(id \\ "setup:bootstrap", metadata \\ %{}) do
    %__MODULE__{id: id, type: :setup, roles: [:setup_bootstrap], metadata: metadata}
  end
end
