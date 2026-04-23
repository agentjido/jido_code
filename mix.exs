defmodule JidoCode.MixProject do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: package.jido_code.mix_first_cli_surface
  # covers: package.jido_code.package_quality_mix_surface_aligned
  # covers: workflow.runtime.compatibility.local_override_present
  # covers: developer.workflow.local_dotenv_bootstrap
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mikehostetler/jido_code"
  @description "Primary Jido.Code product and implementation repository."
  @erlang_rocksdb_opts "-DWITH_BUNDLE_SNAPPY=ON -DWITH_BUNDLE_LZ4=OFF -DWITH_LZ4=TRUE"

  if System.get_env("ERLANG_ROCKSDB_OPTS") in [nil, ""] do
    System.put_env("ERLANG_ROCKSDB_OPTS", @erlang_rocksdb_opts)
  end

  def project do
    [
      app: :jido_code,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      releases: releases(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      consolidate_protocols: Mix.env() != :dev,
      name: "Jido.Code",
      description: @description,
      source_url: @source_url,
      homepage_url: "https://jido.run",
      package: package(),
      test_coverage: [
        tool: ExCoveralls,
        summary: [threshold: 60],
        export: "cov"
      ],
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt"
      ],
      docs: docs()
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {JidoCode.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "browser.verify": :test,
        coveralls: :test,
        "coveralls.github": :test,
        "coveralls.html": :test,
        precommit: :test,
        "memory.verify": :test,
        "semantic.verify": :test,
        "source_graph.verify": :test
      ]
    ]
  end

  def releases do
    [
      jido_code: [
        include_executables_for: [:unix],
        include_erts: System.get_env("MIX_ERTS_PATH") || Mix.env() == :prod,
        quiet: true
      ],
      jido_code_desktop: [
        validate_compile_env: false,
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos: [os: :darwin, cpu: :aarch64]
            # linux: [os: :linux, cpu: :x86_64],
            # windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
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
      extras: ["README.md", "CHANGELOG.md", "CONTRIBUTING.md", ".spec/README.md"]
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "assets",
        "priv",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "LICENSE"
      ],
      maintainers: ["Jido.Code contributors"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "#{@source_url}#documentation",
        "GitHub" => @source_url,
        "Spec Workspace" => "#{@source_url}/tree/main/.spec",
        "Website" => "https://jido.run"
      }
    ]
  end

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:live_vue, "~> 1.0"},
      {:phoenix_vite, "~> 0.4"},
      {:nodejs, "~> 3.1"},
      # Core framework
      {:phoenix, "~> 1.8"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1"},
      {:phoenix_live_dashboard, "~> 0.8"},
      {:bandit, "~> 1.5"},

      # Ash framework and extensions
      {:ash, "~> 3.0"},
      {:ash_phoenix, "~> 2.0"},
      {:ash_postgres, "~> 2.0"},
      {:ash_json_api, "~> 1.0"},
      {:ash_authentication, "~> 4.0"},
      {:ash_authentication_phoenix, "~> 2.0"},
      {:ash_admin, "~> 0.14"},
      {:ash_archival, "~> 2.0"},
      {:ash_paper_trail, "~> 0.5"},
      {:ash_cloak, "~> 0.2"},
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
      {:heroicons,
       github: "tailwindlabs/heroicons", tag: "v2.2.0", sparse: "optimized", app: false, compile: false, depth: 1},
      {:phoenix_live_reload, "~> 1.2", only: :dev},

      # Observability & monitoring
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:dns_cluster, "~> 0.2.0"},

      # Jido runtime stack
      # Mix conflict resolution still needs root-level pins for the directly used core packages.
      {:jido, "~> 2.0", override: true},
      {:jido_action, "~> 2.0", override: true},
      {:jido_signal, "~> 2.0", override: true},
      {:jido_ai, github: "agentjido/jido_ai", branch: "main", override: true},
      {:jido_agent_os, git: "https://github.com/pcharbon70/jido_agent_os.git", branch: "main"},
      {:jido_workflow, path: "compat/jido_workflow", override: true},
      {:libgraph, github: "zblanco/libgraph", branch: "zw/multigraph-indexes", override: true},

      # Source-code ontology analysis
      {:elixir_ontologies,
       git: "https://github.com/pcharbon70/elixir-ontologies.git", ref: "ccb069136f3b96cfd3684468a8ec1be70f41dc0b"},
      {:sparql, "~> 0.3.11"},
      {:triple_store,
       git: "https://github.com/pcharbon70/triple_store.git",
       ref: "ff3665c4f8e6bbb0e68f966d88d5d9e952e4de2a",
       override: true},
      {:rocksdb, "~> 2.6", override: true},

      # Product-specific Jido integrations
      {:gettext, "~> 0.26", override: true},

      # Cloud Sandboxes
      {:sprites, git: "https://github.com/mikehostetler/sprites-ex.git", override: true},

      # Utilities
      {:dotenvy, "~> 1.1"},
      {:live_toast, "~> 0.8"},
      {:jason, "~> 1.2"},
      {:picosat_elixir, "~> 0.2"},
      {:mdex, "~> 0.12"},
      {:zoi, "~> 0.17"},

      # Development & testing
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:spec_led_ex, github: "specleddev/specled_ex", branch: "main", only: [:dev, :test], runtime: false},
      {:lazy_html, ">= 0.1.0"},
      {:tidewave, "~> 0.5.6", only: [:dev]},
      # TODO: re-enable once startup perf is fixed (v0.6.0 adds ~28s to boot)
      # {:live_debugger, "~> 0.5", only: [:dev]},

      # Quality tools
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:doctor, "~> 0.21", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: [:dev, :test]},
      {:git_hooks, "~> 0.8", only: [:dev, :test], runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},

      # Error handling
      {:splode, "~> 0.3"},

      # Desktop packaging
      {:burrito, "~> 1.5"}
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
      setup: ["deps.get", "git_hooks.install", "ecto.setup", "assets.setup", "assets.build"],
      server: ["frontend.start", "phx.server"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["phoenix_vite.npm assets install"],
      "assets.build": [
        "phoenix_vite.npm vite build --manifest --emptyOutDir true",
        "phoenix_vite.npm vite build --ssrManifest --emptyOutDir false --ssr js/server.js --outDir ../priv/static"
      ],
      "frontend.verify": ["assets.setup", "assets.build"],
      "browser.verify": ["frontend.verify", "cmd npm run e2e:test"],
      "source_graph.verify": [
        "test test/jido_code/source_code_graph_test.exs test/jido_code/source_code_graph_actions_test.exs test/jido_code/source_code_graph_workspace_test.exs test/jido_code/agent_os/phase_twenty_integration_test.exs test/jido_code/agent_os/phase_twenty_one_integration_test.exs test/jido_code/agent_os/phase_twenty_two_integration_test.exs test/jido_code/agent_os/phase_twenty_three_integration_test.exs"
      ],
      "memory.verify": [
        "source_graph.verify",
        "test test/jido_code/memory_graph*_test.exs test/jido_code/source_code_graph_workflow_service_test.exs test/jido_code/source_code_graph_governed_adoption_test.exs test/jido_code/agent_os/phase_twenty_eight_integration_test.exs test/jido_code/agent_os/phase_twenty_nine_integration_test.exs test/jido_code/phase_thirty_integration_test.exs test/jido_code/phase_thirty_one_integration_test.exs test/jido_code/phase_thirty_three_integration_test.exs test/jido_code/phase_thirty_five_integration_test.exs test/jido_code/phase_thirty_six_integration_test.exs test/jido_code/phase_thirty_seven_integration_test.exs test/jido_code/phase_thirty_eight_integration_test.exs"
      ],
      "semantic.verify": [
        "memory.verify",
        "test test/jido_code/source_code_graph_product_service_test.exs test/jido_code/source_code_graph_materialization_test.exs test/jido_code/source_code_graph_workflow_service_test.exs test/jido_code/source_code_graph_governed_adoption_test.exs test/jido_code/phase_twenty_four_integration_test.exs test/jido_code/phase_twenty_six_integration_test.exs test/jido_code/phase_twenty_seven_integration_test.exs test/jido_code_web/live/phase_twenty_five_integration_test.exs test/jido_code_web/live/phase_twenty_seven_integration_test.exs test/jido_code_web/live/phase_thirty_eight_integration_test.exs"
      ],
      "assets.deploy": [
        "assets.build"
      ],
      q: ["quality.fast"],
      specs: ["spec.check"],
      precommit: [
        "deps.unlock --check-unused",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "test"
      ],
      "quality.fast": [
        "deps.unlock --check-unused",
        "format --check-formatted",
        "deps.compile",
        "compile --warnings-as-errors",
        "credo --min-priority higher"
      ],
      quality: [
        "quality.fast",
        "frontend.verify",
        "doctor --raise",
        "dialyzer"
      ]
    ]
  end
end
