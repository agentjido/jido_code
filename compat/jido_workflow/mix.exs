defmodule JidoWorkflow.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_workflow,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:yaml_elixir, "~> 2.12"}
    ]
  end
end
