defmodule JidoCodeWeb.UIResetPhase100IntegrationTest do
  use ExUnit.Case, async: true

  @daisy_re ~r/daisy\s*ui|daisyui/i

  @runtime_globs [
    "lib/**/*.{ex,heex,vue}",
    "assets/**/*.{css,js,ts,vue}",
    "package.json",
    "package-lock.json"
  ]

  @retained_islands %{
    "DashboardRunSummaryWidget" => %{host: "lib/jido_code_web/live/dashboard_live.ex", events: %{}},
    "DashboardRuntimePostureWidget" => %{host: "lib/jido_code_web/live/dashboard_live.ex", events: %{}},
    "ProjectDetailOverviewWidget" => %{host: "lib/jido_code_web/live/project_detail_live.ex", events: %{}},
    "ProjectDetailSemanticExplorerWidget" => %{
      host: "lib/jido_code_web/live/project_detail_live.ex",
      events: %{"requestRecovery" => "recover_semantic_graph"}
    },
    "RunGovernanceOverviewWidget" => %{host: "lib/jido_code_web/live/run_detail_live.ex", events: %{}},
    "SettingsOverviewWidget" => %{
      host: "lib/jido_code_web/live/settings_live.ex",
      events: %{"openAddRepo" => "open_add_modal"}
    },
    "SetupGitHubRepositorySelectorWidget" => %{
      host: "lib/jido_code_web/live/setup_live.ex",
      events: %{
        "selectRepository" => "select_github_repository",
        "refreshRepositories" => "refresh_github_repository_listing",
        "importRepository" => "import_selected_github_repository"
      }
    },
    "SetupRuntimeDefaultsWidget" => %{
      host: "lib/jido_code_web/live/setup_live.ex",
      events: %{
        "changeRuntimeEnvironment" => "change_runtime_environment",
        "saveRuntimeEnvironment" => "save_runtime_environment"
      }
    },
    "SetupStartPathSelectorWidget" => %{
      host: "lib/jido_code_web/live/setup_live.ex",
      events: %{"chooseStartPath" => "choose_start_path"}
    },
    "WorkbenchSummaryWidget" => %{
      host: "lib/jido_code_web/live/workbench_live.ex",
      events: %{"resetFilters" => "reset_filters"}
    }
  }

  test "runtime code and package metadata have no DaisyUI references" do
    @runtime_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&File.dir?/1)
    |> Enum.sort()
    |> Enum.each(fn path ->
      refute File.read!(path) =~ @daisy_re,
             "unexpected DaisyUI reference in runtime path #{path}"
    end)
  end

  test "test references to DaisyUI are confined to UI reset guardrails" do
    offenders =
      "test/**/*.{exs,md}"
      |> Path.wildcard()
      |> Enum.reject(&File.dir?/1)
      |> Enum.reject(&String.contains?(&1, "ui_reset"))
      |> Enum.filter(&(File.read!(&1) =~ @daisy_re))
      |> Enum.sort()

    assert offenders == []
  end

  test "retained Vue islands are mounted through vue_surface with explicit server event handoff" do
    Enum.each(@retained_islands, fn {component, %{host: host, events: events}} ->
      source = File.read!(host)

      assert source =~ "<.vue_surface",
             "#{component} should be mounted through the product vue_surface boundary"

      assert source =~ ~s(component="#{component}"),
             "#{component} should be explicitly mounted by #{host}"

      Enum.each(events, fn {emit, handler} ->
        assert source =~ ~s("#{emit}" => "#{handler}"),
               "#{component} should map #{emit} to LiveView event #{handler}"
      end)
    end)
  end

  test "retained Vue islands import generated shadcn-vue primitives directly" do
    Enum.each(@retained_islands, fn {component, _contract} ->
      path = "lib/jido_code_web/live/#{component}.vue"
      source = File.read!(path)

      assert source =~ ~S|@/vue/components/ui/|,
             "#{component} should import generated shadcn-vue primitives"

      imports =
        ~r/^import .* from ["']([^"']+)["'];?$/m
        |> Regex.scan(source, capture: :all_but_first)
        |> List.flatten()

      assert imports != []

      Enum.each(imports, fn import_path ->
        assert import_path == "vue" or String.starts_with?(import_path, "@/vue/components/ui/"),
               "#{component} has non-boundary import #{inspect(import_path)}"
      end)
    end)
  end

  test "old operator shell and broad Vue discovery are absent from product mounts" do
    product_sources =
      ["lib/jido_code_web/live/**/*.{ex,heex}", "lib/jido_code_web/components/**/*.{ex,heex}"]
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.reject(&String.ends_with?(&1, "operator_shell_components.ex"))
      |> Enum.sort()

    Enum.each(product_sources, fn path ->
      refute File.read!(path) =~ "OperatorShellComponents",
             "old operator shell should not be imported by #{path}"
    end)

    registry = File.read!("assets/vue/index.ts")

    refute registry =~ "import.meta.glob"
    refute registry =~ "components/ui"

    assert registry =~ "export const liveVueComponents"
  end
end
