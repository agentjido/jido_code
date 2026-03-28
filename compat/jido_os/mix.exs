defmodule JidoOs.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_os,
      version: "0.1.0",
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Jido.Os.Application, []}
    ]
  end

  defp deps do
    []
  end
end
