defmodule AgentJido.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/agent_jido"

  def project do
    [
      app: :agent_jido,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {AgentJido.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md"]
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # Core framework
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:bandit, "~> 1.5"},

      # Ash framework and extensions
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_json_api, "~> 1.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_admin, "~> 0.13"},
      {:ash_archival, "~> 2.0"},
      {:ash_paper_trail, "~> 0.5"},
      {:ash_cloak, "~> 0.2"},
      {:ash_typescript, "~> 0.12"},
      {:ash_jido, github: "agentjido/ash_jido", branch: "main"},

      # Database
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},

      # Security & encryption
      {:bcrypt_elixir, "~> 3.0"},
      {:cloak, "~> 1.0"},

      # HTTP & API
      {:req, "~> 0.5"},
      {:open_api_spex, "~> 3.0"},
      {:plug_canonical_host, "~> 2.0"},

      # Email
      {:swoosh, "~> 1.16"},

      # Frontend assets
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:phoenix_live_reload, "~> 1.2", only: :dev},

      # Observability & monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:dns_cluster, "~> 0.2.0"},

      # Jido AI framework
      {:jido, "~> 2.0.0-rc"},
      {:jido_action, "~> 2.0.0-rc", override: true},
      {:jido_signal, "~> 2.0.0-rc"},
      {:jido_ai, github: "agentjido/jido_ai", branch: "main"},
      {:req_llm, "~> 1.4", override: true},
      {:timex, "~> 3.7", override: true},
      {:gettext, "~> 0.26", override: true},

      # Cloud Sandboxes
      {:sprites, github: "superfly/sprites-ex"},

      # Utilities
      {:live_toast, "~> 0.8"},
      {:jason, "~> 1.2"},
      {:picosat_elixir, "~> 0.2"},
      {:mdex, "~> 0.4"},

      # Development & testing
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:usage_rules, "~> 1.0", only: [:dev]},
      {:tidewave, "~> 0.5", only: [:dev]},
      {:mishka_chelekom, "~> 0.0", only: [:dev]},
      {:live_debugger, "~> 0.5", only: [:dev]},

      # Quality tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},

      # Error handling
      {:splode, "~> 0.3"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ash.setup", "assets.setup", "assets.build", "run priv/repo/seeds.exs"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ash.setup --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind agent_jido", "esbuild agent_jido"],
      "assets.deploy": [
        "tailwind agent_jido --minify",
        "esbuild agent_jido --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"],
      sync_rules: ["usage_rules.sync AGENTS.md --all --link-to-folder deps --yes"],
      quality: [
        "compile --warnings-as-errors",
        "format --check-formatted",
        "credo --strict",
        "doctor --raise"
      ]
    ]
  end
end
