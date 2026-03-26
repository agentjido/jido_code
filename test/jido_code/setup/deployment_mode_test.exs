defmodule JidoCode.Setup.DeploymentModeTest do
  # covers: setup.onboarding.deployment_mode_auto_detected
  use ExUnit.Case, async: false

  alias JidoCode.Setup.DeploymentMode

  setup do
    original_target = System.get_env("BURRITO_TARGET")

    on_exit(fn ->
      case original_target do
        nil -> System.delete_env("BURRITO_TARGET")
        value -> System.put_env("BURRITO_TARGET", value)
      end
    end)

    :ok
  end

  test "detects desktop mode when burrito target is present" do
    System.put_env("BURRITO_TARGET", "darwin-aarch64")

    assert DeploymentMode.current() == :desktop
    assert DeploymentMode.desktop?()
    refute DeploymentMode.cloud?()
  end

  test "detects cloud mode when burrito target is absent" do
    System.delete_env("BURRITO_TARGET")

    assert DeploymentMode.current() == :cloud
    assert DeploymentMode.cloud?()
    refute DeploymentMode.desktop?()
  end
end
