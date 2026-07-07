defmodule JidoCodeWeb.UIResetPhase98LiveVueBoundaryTest do
  use ExUnit.Case, async: true

  @registry_path "assets/vue/index.ts"
  @ui_boundary_path "lib/jido_code_web/components/ui.ex"

  test "HEEx imports the app-owned SaladUI boundary without direct route imports" do
    web = File.read!("lib/jido_code_web.ex")
    ui_boundary = File.read!(@ui_boundary_path)

    assert web =~ "alias JidoCodeWeb.Components.UI"
    assert ui_boundary =~ "Application-owned boundary for HEEx components backed by SaladUI."
    assert ui_boundary =~ "defdelegate button(assigns), to: SaladUI.Button"
    assert ui_boundary =~ "defdelegate tabs(assigns), to: SaladUI.Tabs"
    refute ui_boundary =~ "defdelegate input(assigns)"
    refute ui_boundary =~ "defdelegate select(assigns)"

    for path <- first_party_heex_paths() -- [@ui_boundary_path] do
      refute File.read!(path) =~ "SaladUI.",
             "#{path} imports SaladUI directly instead of JidoCodeWeb.Components.UI"
    end
  end

  test "LiveVue registry is explicit and contains only production islands" do
    registry = File.read!(@registry_path)

    assert registry =~ "export const liveVueComponents"
    assert registry =~ "export function resolveLiveVueComponent"
    refute registry =~ "import.meta.glob"
    refute registry =~ "assets/vue/components/ui"

    for widget_path <- live_vue_widget_paths() do
      widget_name = widget_path |> Path.basename(".vue")

      assert registry =~ "import #{widget_name} from"
      assert registry =~ "../../#{widget_path}"
    end
  end

  test "routed LiveVue mount names are backed by the explicit production registry" do
    registry = File.read!(@registry_path)

    for component <- routed_component_names() do
      assert registry =~ "#{component}.vue"
    end
  end

  test "generated shadcn-vue primitives stay private to Vue islands" do
    registry = File.read!(@registry_path)
    utils = File.read!("assets/vue/lib/utils.ts")

    assert utils =~ "twMerge(clsx(inputs))"

    for primitive <- ["Button", "Dialog", "Table", "Tabs", "Command", "Select"] do
      refute registry =~ "components/ui/#{String.downcase(primitive)}"
      refute registry =~ "#{primitive}.vue"
    end
  end

  defp first_party_heex_paths do
    ["lib/jido_code_web/live/**/*.{ex,heex}", "lib/jido_code_web/components/**/*.{ex,heex}"]
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.sort()
  end

  defp live_vue_widget_paths do
    "lib/jido_code_web/live/*.vue"
    |> Path.wildcard()
    |> Enum.sort()
  end

  defp routed_component_names do
    first_party_heex_paths()
    |> Enum.flat_map(fn path ->
      ~r/component="([^"]+)"/
      |> Regex.scan(File.read!(path), capture: :all_but_first)
      |> List.flatten()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end
end
