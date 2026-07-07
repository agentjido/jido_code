defmodule JidoCodeWeb.UIResetPhase101CleanupTest do
  use ExUnit.Case, async: true

  @deleted_runtime_paths ~w[
    lib/jido_code_web/components/operator_shell_components.ex
    lib/jido_code_web/operator_shell.ex
  ]

  @runtime_globs [
    "lib/jido_code_web/**/*.{ex,heex}",
    "assets/**/*.{css,js,ts,vue}",
    "package.json",
    "package-lock.json"
  ]

  @stale_asset_globs [
    "priv/static/assets/daisy*",
    "priv/static/assets/*operator_shell*",
    "priv/static/assets/*subject_tree*"
  ]

  test "deleted operator shell files stay removed" do
    Enum.each(@deleted_runtime_paths, fn path ->
      refute File.exists?(path), "#{path} should stay deleted after the area-shell reset"
    end)

    assert File.exists?("lib/jido_code_web/components/route_shell_components.ex")
    assert File.exists?("lib/jido_code_web/route_shell.ex")
  end

  test "runtime source no longer references removed shell contracts" do
    offenders =
      @runtime_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.reject(&File.dir?/1)
      |> Enum.filter(fn path ->
        source = File.read!(path)

        source =~ "OperatorShellComponents" or
          source =~ "operator_shell_components" or
          source =~ "subject_tree_shell" or
          source =~ "-parent-subjects"
      end)
      |> Enum.sort()

    assert offenders == []
  end

  test "current route frames use area-shell section terminology" do
    route_shell = File.read!("lib/jido_code_web/components/route_shell_components.ex")
    dashboard = File.read!("lib/jido_code_web/live/dashboard_live.ex")
    project_detail = File.read!("lib/jido_code_web/live/project_detail_live.ex")

    assert route_shell =~ "def route_section_shell"
    assert route_shell =~ ~S|id={"#{@id}-section-groups"}|
    assert route_shell =~ ~s(aria-label="Route section groups")
    assert dashboard =~ "<.route_section_shell"
    assert dashboard =~ "section_groups={dashboard_section_groups(assigns)}"
    assert project_detail =~ "<.route_section_shell"
    assert project_detail =~ "section_groups={project_detail_section_groups(assigns)}"
  end

  test "stale generated public assets for deleted shells are absent" do
    stale_assets =
      @stale_asset_globs
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.sort()

    assert stale_assets == []
  end
end
