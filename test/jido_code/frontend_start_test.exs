defmodule JidoCode.FrontendStartTest do
  # covers: developer.workflow.phoenix_mix_surface
  # covers: package.jido_code.package_quality_mix_surface_aligned
  # covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  use ExUnit.Case, async: false

  alias JidoCode.Mix.FrontendStart

  setup do
    tmp_dir =
      System.tmp_dir!()
      |> Path.join("jido-code-frontend-start-#{System.unique_integer([:positive, :monotonic])}")

    File.mkdir_p!(tmp_dir)

    on_exit(fn ->
      File.rm_rf!(tmp_dir)
    end)

    %{tmp_dir: tmp_dir}
  end

  test "plan skips browser preparation in test env", %{tmp_dir: tmp_dir} do
    assert FrontendStart.plan(:test, cwd: tmp_dir) == []
  end

  test "plan prepares browser dependencies and bundle in dev when both are missing", %{tmp_dir: tmp_dir} do
    assert FrontendStart.plan(:dev, cwd: tmp_dir) == ["assets.setup", "assets.build"]
  end

  test "plan only refreshes browser dependencies in dev when the install stamp is stale", %{
    tmp_dir: tmp_dir
  } do
    write_fresh_frontend_tree!(tmp_dir)

    node_modules_lock = Path.join(tmp_dir, "node_modules/.package-lock.json")
    package_json = Path.join(tmp_dir, "package.json")

    set_mtime!(node_modules_lock, {{2026, 4, 1}, {0, 0, 0}})
    set_mtime!(package_json, {{2026, 4, 1}, {0, 0, 5}})

    assert FrontendStart.plan(:dev, cwd: tmp_dir) == ["assets.setup"]
  end

  test "plan stays quiet in dev when browser dependencies and bundles are already current", %{
    tmp_dir: tmp_dir
  } do
    write_fresh_frontend_tree!(tmp_dir)

    assert FrontendStart.plan(:dev, cwd: tmp_dir) == []
  end

  test "plan routes non-dev environments through frontend verification", %{tmp_dir: tmp_dir} do
    write_fresh_frontend_tree!(tmp_dir)

    assert FrontendStart.plan(:prod, cwd: tmp_dir) == ["frontend.verify"]
  end

  test "frontend.start mix task is a safe no-op in test env" do
    assert :ok = Mix.Tasks.Frontend.Start.run([])
  end

  defp write_fresh_frontend_tree!(tmp_dir) do
    node_modules_dir = Path.join(tmp_dir, "node_modules")
    vite_dir = Path.join(tmp_dir, "priv/static/.vite")

    File.mkdir_p!(node_modules_dir)
    File.mkdir_p!(vite_dir)
    File.write!(Path.join(tmp_dir, "package.json"), "{}\n")
    File.write!(Path.join(tmp_dir, "package-lock.json"), "{}\n")
    File.write!(Path.join(node_modules_dir, ".package-lock.json"), "{}\n")
    File.write!(Path.join(vite_dir, "manifest.json"), "{}\n")
    File.write!(Path.join(tmp_dir, "priv/static/server.mjs"), "export default {};\n")
  end

  defp set_mtime!(path, time) do
    assert :ok = :file.change_time(String.to_charlist(path), time)
  end
end
