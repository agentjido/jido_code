defmodule JidoCode.AgentOS.Manager.KernelState do
  @moduledoc false

  @type t :: %__MODULE__{
          managed_repo_id: String.t(),
          pid: pid(),
          created_at: DateTime.t(),
          pods: %{optional(String.t()) => map()}
        }

  defstruct [
    :managed_repo_id,
    :pid,
    :created_at,
    pods: %{}
  ]
end
