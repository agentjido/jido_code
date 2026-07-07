defmodule JidoCodeWeb.UIResetPhase101ResilienceTest do
  use ExUnit.Case, async: true

  @hardened_runtime_files ~w[
    lib/jido_code_web/components/layouts.ex
    lib/jido_code_web/components/live_vue_components.ex
    lib/jido_code_web/components/operator_state_components.ex
    lib/jido_code_web/live/operator_root_live.ex
  ]

  @legacy_class_token_re ~r/(?<![A-Za-z0-9_.:-])(?:base-(?:100|200|300|content)|(?:text|bg|border)-(?:success|warning|error|info)(?:\/[0-9]+)?|text-primary-content)(?![A-Za-z0-9_-])/

  test "hardened shell and fallback surfaces do not retain legacy status classes" do
    Enum.each(@hardened_runtime_files, fn file ->
      path = Path.expand("../../#{file}", __DIR__)
      source = File.read!(path)

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_number} -> class_candidate_line?(line) end)
      |> Enum.each(fn {line, line_number} ->
        refute line =~ @legacy_class_token_re,
               "legacy UI status class in #{file}:#{line_number}: #{line}"
      end)
    end)
  end

  test "root area shell exposes accessible landmarks, selected state, and focus handling" do
    source = read_runtime!("lib/jido_code_web/components/layouts.ex")

    assert source =~ ~s(id="operator-area-menu")
    assert source =~ ~s(aria-label="Product areas")
    assert source =~ ~s(aria-current={if item.area == @active_area, do: "page", else: nil})
    assert source =~ ~s(id="operator-status-strip")
    assert source =~ ~s(role="status")
    assert source =~ ~s(aria-live="polite")
    assert source =~ ~s(aria-label="Operator shell status")
    assert source =~ ~s(role="group")
    assert source =~ ~s(aria-label="Theme preference")
    assert source =~ "focus-visible:outline-ring"
    assert source =~ "truncate"
  end

  test "LiveVue fallback panels expose bounded degradation evidence" do
    source = read_runtime!("lib/jido_code_web/components/live_vue_components.ex")

    assert source =~ ~s(role="status")
    assert source =~ ~s(aria-live="polite")
    assert source =~ ~s(data-vue-surface-component={@component})
    assert source =~ ~s(data-vue-surface-delivery={@delivery.mode})
    assert source =~ ~s(data-vue-surface-reason={@delivery.reason})
    assert source =~ "Fallback mode reason: {humanize_reason(@delivery.reason)}"
    assert source =~ "assign(:fallback_detail, assigns.fallback_detail || delivery.detail)"
    assert source =~ "{render_slot(@inner_block)}"
  end

  test "operator notices and root route map preserve accessibility under degraded state" do
    notice_source = read_runtime!("lib/jido_code_web/components/operator_state_components.ex")
    root_source = read_runtime!("lib/jido_code_web/live/operator_root_live.ex")

    assert notice_source =~ ~S|role={notice_role(@kind)}|
    assert notice_source =~ ~S|aria-live={notice_aria_live(@kind)}|
    assert notice_source =~ "defp notice_role(:error)"
    assert notice_source =~ "break-words"

    assert root_source =~ ~s(aria-label="Product area route map")
    assert root_source =~ ~s(aria-current={if item.area == @active_area, do: "page", else: nil})
    assert root_source =~ "focus-visible:outline-ring"
    assert root_source =~ "truncate"
  end

  defp read_runtime!(relative_path) do
    Path.expand("../../#{relative_path}", __DIR__)
    |> File.read!()
  end

  defp class_candidate_line?(line) do
    String.contains?(line, "class") or Regex.match?(~r/\b(?:&&|do:|=>)\s*"/, line)
  end
end
