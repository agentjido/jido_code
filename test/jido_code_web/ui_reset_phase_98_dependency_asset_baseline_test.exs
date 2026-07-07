defmodule JidoCodeWeb.UIResetPhase98DependencyAssetBaselineTest do
  use ExUnit.Case, async: true

  @primitive_dirs ~w(
    alert
    badge
    button
    command
    dialog
    empty
    input
    popover
    scroll-area
    select
    skeleton
    table
    tabs
    tooltip
  )

  test "components.json targets Phoenix assets and shadcn-vue aliases" do
    components = "components.json" |> File.read!() |> Jason.decode!()

    assert components["$schema"] == "https://shadcn-vue.com/schema.json"
    assert components["style"] == "new-york"
    assert components["typescript"] == true
    assert components["tailwind"]["css"] == "assets/css/app.css"
    assert components["tailwind"]["cssVariables"] == true

    assert components["aliases"] == %{
             "components" => "@/vue/components",
             "ui" => "@/vue/components/ui",
             "utils" => "@/vue/lib/utils",
             "lib" => "@/vue/lib",
             "composables" => "@/vue/composables"
           }
  end

  test "npm dependencies expose shadcn-vue primitives and SaladUI browser assets" do
    package = "package.json" |> File.read!() |> Jason.decode!()
    dependencies = package["dependencies"]

    assert dependencies["salad_ui"] in ["file:deps/salad_ui", "file:./deps/salad_ui"]

    for package_name <- [
          "@radix-icons/vue",
          "@vueuse/core",
          "class-variance-authority",
          "clsx",
          "reka-ui",
          "tailwind-merge",
          "tw-animate-css",
          "vue"
        ] do
      assert Map.has_key?(dependencies, package_name)
    end
  end

  test "SaladUI is a product dependency with a supervised merge cache" do
    mix = File.read!("mix.exs")
    application = File.read!("lib/jido_code/application.ex")

    assert mix =~ ~s({:salad_ui, "~> 1.0.0-beta.3"})
    assert mix =~ ~s({:igniter, "~> 0.7.9", override: true})
    assert application =~ "TwMerge.Cache"
  end

  test "app-owned HEEx UI boundary delegates selected SaladUI primitives" do
    web = File.read!("lib/jido_code_web.ex")
    ui = File.read!("lib/jido_code_web/components/ui.ex")

    assert web =~ "alias JidoCodeWeb.Components.UI"
    assert ui =~ "Application-owned boundary for HEEx components backed by SaladUI."

    for delegate <- [
          "button",
          "dialog",
          "dialog_content",
          "table",
          "badge",
          "alert",
          "separator",
          "scroll_area",
          "skeleton",
          "tooltip",
          "popover",
          "command",
          "collapsible",
          "tabs"
        ] do
      assert ui =~ "defdelegate #{delegate}(assigns)"
    end

    refute ui =~ "defdelegate input(assigns)"
    refute ui =~ "defdelegate select(assigns)"
  end

  test "LiveView JavaScript registers SaladUI hooks beside LiveVue hooks" do
    app_js = File.read!("assets/js/app.js")

    assert app_js =~ ~s(import SaladUI from "salad_ui")
    assert app_js =~ ~s(import "salad_ui/components/dialog")
    assert app_js =~ ~s(import "salad_ui/components/tabs")
    assert app_js =~ "SaladUI: SaladUI.SaladUIHook"
    assert app_js =~ "...getHooks(liveVueApp)"
  end

  test "Vite and TypeScript resolve generated Vue primitives through the assets alias" do
    vite = File.read!("assets/vite.config.mjs")
    tsconfig = "tsconfig.json" |> File.read!() |> Jason.decode!()

    assert vite =~ ~s("@": assetsRoot)
    assert vite =~ ~S|fileURLToPath(new URL(".", import.meta.url))|
    assert tsconfig["compilerOptions"]["paths"]["@/*"] == ["./assets/*"]
  end

  test "initial generated shadcn-vue primitive set exists under assets/vue/components/ui" do
    for primitive <- @primitive_dirs do
      assert File.dir?(Path.join(["assets/vue/components/ui", primitive]))
      assert File.exists?(Path.join(["assets/vue/components/ui", primitive, "index.ts"]))
    end

    assert File.exists?("assets/vue/lib/utils.ts")
    assert File.read!("assets/vue/lib/utils.ts") =~ "twMerge(clsx(inputs))"
  end
end
