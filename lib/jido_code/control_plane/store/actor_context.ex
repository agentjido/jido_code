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
end
