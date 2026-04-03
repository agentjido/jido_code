defmodule JidoCodeWeb.FrontendAssets do
  # covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  @moduledoc false

  @test_manifest PhoenixVite.Manifest.parse(%{
                   "js/app.js" => %{
                     "file" => "assets/test.js",
                     "css" => ["assets/test.css"],
                     "imports" => []
                   },
                   "css/app.css" => %{
                     "file" => "assets/test.css",
                     "css" => [],
                     "imports" => []
                   }
                 })

  def vite_manifest do
    case Application.get_env(:jido_code, :runtime_mode) do
      :test -> @test_manifest
      _ -> {:jido_code, "priv/static/.vite/manifest.json"}
    end
  end
end
