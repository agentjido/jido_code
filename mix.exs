defmodule JidoCode.MixProject do
  use Mix.Project

  def project do
    [
      app: :jido_code,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),

      # Docs
      name: "JidoCode",
      description: "Agentic Coding Assistant TUI built on Jido",
      source_url: "https://github.com/agentjido/jido_code",

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix, :ex_unit]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JidoCode.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies
      {:jido, "~> 1.2"},
      {:jido_ai, path: "../agentjido/jido_ai"},
      {:term_ui, path: "../term_ui"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},

      # Lua sandbox for tool execution
      {:luerl, "~> 1.2"},

      # Knowledge graph
      {:rdf, "~> 2.0"},
      {:libgraph, "~> 0.16"},

      # Development dependencies
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"],
      test: ["test"]
    ]
  end
end
