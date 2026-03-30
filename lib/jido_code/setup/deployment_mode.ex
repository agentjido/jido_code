defmodule JidoCode.Setup.DeploymentMode do
  # covers: setup.onboarding.deployment_mode_auto_detected
  @moduledoc """
  Resolves the global deployment flavor used for onboarding defaults and copy.
  """

  @type t :: :desktop | :cloud

  @spec current() :: t()
  def current do
    if desktop_target_present?(), do: :desktop, else: :cloud
  end

  @spec desktop?() :: boolean()
  def desktop?, do: current() == :desktop

  @spec cloud?() :: boolean()
  def cloud?, do: current() == :cloud

  defp desktop_target_present? do
    System.get_env("BURRITO_TARGET") not in [nil, ""]
  end
end
