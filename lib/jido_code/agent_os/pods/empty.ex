defmodule JidoCode.AgentOS.Pods.Empty do
  # covers: architecture.agent_os_integration.kernel_per_managed_repo
  @moduledoc """
  Placeholder pod for AgentOS kernels.

  This is a minimal pod used during kernel initialization. Once RepoPod is
  implemented (Section 19.2), this will be replaced with the proper
  repository monitoring pod.
  """

  use Jido.AgentOS.Pod,
    name: "empty",
    topology: %{}
end
