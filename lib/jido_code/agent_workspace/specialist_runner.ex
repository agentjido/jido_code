defmodule JidoCode.AgentWorkspace.SpecialistRunner do
  @moduledoc false

  @callback run(module(), pid(), String.t(), keyword()) :: {:ok, any()} | {:error, term()}
end
