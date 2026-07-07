defmodule JidoCodeWeb.UIResetPhase100CoreComponentsTest do
  use ExUnit.Case, async: true

  @phase_100_surface_files ~w[
    lib/jido_code/workbench/inventory_surface.ex
    lib/jido_code_web/components/core_components.ex
    lib/jido_code_web/components/conversation_surface_components.ex
    lib/jido_code_web/components/managed_repo_inventory_components.ex
    lib/jido_code_web/components/memory_surface_components.ex
    lib/jido_code_web/live/agents_live.ex
    lib/jido_code_web/live/dashboard_live.ex
    lib/jido_code_web/live/decision_detail_live.ex
    lib/jido_code_web/live/evidence_detail_live.ex
    lib/jido_code_web/live/project_detail_live.ex
    lib/jido_code_web/live/project_inventory_live.ex
    lib/jido_code_web/live/run_detail_live.ex
    lib/jido_code_web/live/settings_live.ex
    lib/jido_code_web/live/work_item_detail_live.ex
    lib/jido_code_web/live/workbench_live.ex
    lib/jido_code_web/live/workflows_live.ex
    lib/jido_code_web/operator_auth_settings.ex
  ]

  @legacy_class_token_re ~r/(?<![A-Za-z0-9_.:-])(?:btn(?:-[A-Za-z0-9_\-\/\[\].:]+)?|badge(?:-[A-Za-z0-9_\-\/\[\].:]+)?|alert(?:-[A-Za-z0-9_\-\/\[\].:]+)?|tabs?|join(?:-[A-Za-z0-9_\-\/\[\].:]+)?|rounded-box|base-(?:100|200|300|content)|select(?:-[A-Za-z0-9_\-\/\[\].:]+)?|textarea(?:-[A-Za-z0-9_\-\/\[\].:]+)?|input(?:-[A-Za-z0-9_\-\/\[\].:]+)?|checkbox(?:-[A-Za-z0-9_\-\/\[\].:]+)?|(?:text|bg|border)-(?:success|warning|error|info)(?:\/[0-9]+)?)(?![A-Za-z0-9_-])/

  test "phase 100 core surfaces no longer emit DaisyUI class primitives" do
    Enum.each(@phase_100_surface_files, fn file ->
      path = Path.expand("../../#{file}", __DIR__)
      source = File.read!(path)

      refute source =~ "daisyUI"

      source
      |> String.split("\n")
      |> Enum.with_index(1)
      |> Enum.filter(fn {line, _line_number} -> class_candidate_line?(line) end)
      |> Enum.each(fn {line, line_number} ->
        refute line =~ @legacy_class_token_re,
               "legacy UI class token in #{file}:#{line_number}: #{line}"
      end)
    end)
  end

  defp class_candidate_line?(line) do
    not String.contains?(line, "doc:") and
      (String.contains?(line, "class") or Regex.match?(~r/\b(?:&&|do:|=>)\s*"/, line))
  end
end
