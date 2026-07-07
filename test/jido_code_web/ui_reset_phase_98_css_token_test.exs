defmodule JidoCodeWeb.UIResetPhase98CSSTokenTest do
  use ExUnit.Case, async: true

  @baseline_path ".planning/ui-reset-daisyui-class-baseline.json"
  @legacy_token_re ~r/(?<![A-Za-z0-9_-])(?:btn(?:-[A-Za-z0-9_\-\/\[\].:]+)?|badge(?:-[A-Za-z0-9_\-\/\[\].:]+)?|alert(?:-[A-Za-z0-9_\-\/\[\].:]+)?|tabs|join(?:-[A-Za-z0-9_\-\/\[\].:]+)?|rounded-box|base-(?:100|200|300|content))(?![A-Za-z0-9_-])/
  @string_literal_re ~r/"([^"\\]*(?:\\.[^"\\]*)*)"/
  @scan_globs [
    "lib/jido_code_web/**/*.{ex,heex,vue}",
    "assets/vue/**/*.{ts,vue}",
    "assets/css/**/*.css",
    "test/jido_code_web/**/*.exs"
  ]
  @ignored_prefixes ["assets/vue/components/ui/"]
  @ignored_paths [__ENV__.file |> Path.relative_to(File.cwd!())]

  test "CSS uses the shadcn token foundation without DaisyUI plugin or theme blocks" do
    css = File.read!("assets/css/app.css")

    assert css =~ ~S|@import "tailwindcss" source(none);|
    assert css =~ ~S|@import "tw-animate-css";|
    assert css =~ ~S|@source "../css";|
    assert css =~ ~S|@source "../js";|
    assert css =~ ~S|@source "../vue";|
    assert css =~ ~S|@source "../../lib/jido_code_web";|
    assert css =~ ~S|@source "../../deps/live_toast/lib";|
    assert css =~ ~S|@plugin "../vendor/heroicons";|

    refute css =~ ~S|@plugin "daisyui"|
    refute css =~ ~S|@plugin "daisyui/theme"|
    refute css =~ "--color-base-100"
    refute css =~ "--color-base-200"
    refute css =~ "--color-base-300"
    refute css =~ "--color-base-content"
  end

  test "CSS exposes light dark and system-compatible shadcn token variables" do
    css = File.read!("assets/css/app.css")

    assert css =~ ":root[data-theme=\"light\"]"
    assert css =~ "@media (prefers-color-scheme: dark)"
    assert css =~ ":root[data-theme=\"dark\"]"
    assert css =~ "@theme inline"

    for token <- [
          "background",
          "foreground",
          "card",
          "popover",
          "primary",
          "secondary",
          "muted",
          "accent",
          "destructive",
          "border",
          "input",
          "ring",
          "sidebar"
        ] do
      assert css =~ "--#{token}:"
      assert css =~ "--color-#{token}:"
    end

    assert css =~ "--radius:"
    assert css =~ "--radius-md:"
  end

  test "CSS provides app-owned ui utility classes for HEEx-only stable styling" do
    css = File.read!("assets/css/app.css")

    for class <- [
          ".ui-card",
          ".ui-badge",
          ".ui-button",
          ".ui-tabs",
          ".ui-join",
          ".ui-alert",
          ".ui-input",
          ".ui-select",
          ".ui-textarea"
        ] do
      assert css =~ class
    end
  end

  test "DaisyUI npm removal stays gated while existing runtime class references remain" do
    package = "package.json" |> File.read!() |> Jason.decode!()
    current_counts = current_legacy_class_counts()
    total_references = current_counts |> Map.values() |> Enum.sum()

    assert total_references > 0
    assert package["devDependencies"]["daisyui"]
  end

  test "first-party legacy DaisyUI class references cannot increase" do
    baseline = @baseline_path |> File.read!() |> Jason.decode!()
    current = current_legacy_class_counts()

    for {token, count} <- current do
      assert count <= Map.get(baseline, token, 0),
             "#{token} has #{count} references, above the baseline #{Map.get(baseline, token, 0)}"
    end

    for token <- Map.keys(baseline) -- Map.keys(current) do
      assert Map.get(current, token, 0) <= baseline[token]
    end
  end

  defp current_legacy_class_counts do
    @scan_globs
    |> Enum.flat_map(&Path.wildcard/1)
    |> Enum.reject(&ignored_path?/1)
    |> Enum.sort()
    |> Enum.reduce(%{}, &count_legacy_tokens/2)
  end

  defp ignored_path?(path) do
    path in @ignored_paths or Enum.any?(@ignored_prefixes, &String.starts_with?(path, &1))
  end

  defp count_legacy_tokens(path, counts) do
    scan_text =
      path
      |> File.read!()
      |> scannable_text(Path.extname(path))

    @legacy_token_re
    |> Regex.scan(scan_text)
    |> Enum.map(&List.first/1)
    |> Enum.reduce(counts, fn token, acc -> Map.update(acc, token, 1, &(&1 + 1)) end)
  end

  defp scannable_text(content, ".css"), do: content

  defp scannable_text(content, _extension) do
    @string_literal_re
    |> Regex.scan(content, capture: :all_but_first)
    |> List.flatten()
    |> Enum.reject(&(String.contains?(&1, "(") or String.contains?(&1, ")")))
    |> Enum.join("\n")
  end
end
