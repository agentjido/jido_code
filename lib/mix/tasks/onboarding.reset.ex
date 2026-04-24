defmodule Mix.Tasks.Onboarding.Reset do
  # covers: setup.onboarding.reset_mix_task
  # covers: developer.workflow.phoenix_mix_surface
  @shortdoc "Resets onboarding state to bootstrap or the signed-in setup surface"
  @moduledoc false

  use Mix.Task

  @impl true
  def run(args) do
    Mix.Task.run("app.start")
    JidoCode.Mix.OnboardingReset.run!(args)
  end
end
