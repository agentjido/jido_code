defmodule JidoCodeWeb.FrontendAssets do
  # covers: package.jido_code.version_controlled_quality_surfaces
  # covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  # covers: architecture.frontend_stack.testing_keeps_liveview_and_adds_live_vue_aware_helpers
  # covers: architecture.frontend_stack.hybrid_surfaces_fail_safe_when_richer_client_path_degrades
  # covers: architecture.frontend_stack.frontend_bridge_observability_stays_product_oriented
  @moduledoc false

  @manifest_path "priv/static/.vite/manifest.json"
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
  @fallback_manifest PhoenixVite.Manifest.parse(%{
                       "js/app.js" => %{
                         "file" => "assets/app.js",
                         "css" => ["assets/app.css"],
                         "imports" => []
                       },
                       "css/app.css" => %{
                         "file" => "assets/app.css",
                         "css" => [],
                         "imports" => []
                       }
                     })
  @fallback_title "Interactive summary temporarily unavailable"
  @fallback_detail "This page is running in server-rendered fallback mode. Core controls remain available below."

  def vite_manifest do
    case status() do
      %{manifest: manifest} -> manifest
      %{manifest_path: manifest_path} -> {:jido_code, manifest_path}
    end
  end

  def status do
    case Application.get_env(:jido_code, :frontend_assets_override) do
      nil -> compute_status()
      override -> normalize_override(override)
    end
  end

  def vue_surface_delivery(component) do
    status = status()

    delivery =
      case status.mode do
        :ready ->
          %{
            mode: :ready,
            reason: nil,
            ssr: nil,
            title: nil,
            detail: nil
          }

        :client_only ->
          %{
            mode: :client_only,
            reason: status.reason,
            ssr: false,
            title: nil,
            detail: nil
          }

        :fallback ->
          %{
            mode: :fallback,
            reason: status.reason,
            ssr: false,
            title: status.title,
            detail: status.detail
          }
      end

    observe_vue_surface_delivery(component, delivery)
    delivery
  end

  defp compute_status do
    runtime_mode = Application.get_env(:jido_code, :runtime_mode, :prod)
    ssr_enabled? = Application.get_env(:live_vue, :ssr, false)
    dev_server? = PhoenixVite.Components.has_vite_watcher?(JidoCodeWeb.Endpoint)

    cond do
      runtime_mode == :test ->
        %{mode: :ready, reason: nil, manifest: @test_manifest}

      dev_server? and ssr_enabled? ->
        %{mode: :ready, reason: nil, manifest_path: @manifest_path}

      dev_server? ->
        %{mode: :client_only, reason: :ssr_disabled, manifest_path: @manifest_path}

      File.exists?(Path.join(File.cwd!(), @manifest_path)) and ssr_available?(runtime_mode, ssr_enabled?) ->
        %{mode: :ready, reason: nil, manifest_path: @manifest_path}

      File.exists?(Path.join(File.cwd!(), @manifest_path)) ->
        %{
          mode: :client_only,
          reason: :ssr_unavailable,
          manifest_path: @manifest_path
        }

      true ->
        %{
          mode: :fallback,
          reason: :asset_manifest_unavailable,
          manifest: @fallback_manifest,
          title: @fallback_title,
          detail: @fallback_detail
        }
    end
  end

  defp ssr_available?(_runtime_mode, false), do: true
  defp ssr_available?(:dev, true), do: true
  defp ssr_available?(:test, _ssr_enabled), do: true
  defp ssr_available?(_runtime_mode, true), do: is_pid(Process.whereis(NodeJS.Supervisor))

  defp normalize_override(override) when is_map(override) do
    case Map.get(override, :mode) || Map.get(override, "mode") do
      :ready ->
        %{mode: :ready, reason: nil, manifest: override_manifest(override, @test_manifest)}

      :client_only ->
        %{
          mode: :client_only,
          reason: override_reason(override, :ssr_unavailable),
          manifest: override_manifest(override, @test_manifest)
        }

      :fallback ->
        %{
          mode: :fallback,
          reason: override_reason(override, :asset_manifest_unavailable),
          manifest: override_manifest(override, @fallback_manifest),
          title: override_detail(override, :title, @fallback_title),
          detail: override_detail(override, :detail, @fallback_detail)
        }

      other ->
        raise ArgumentError, "unsupported frontend_assets_override mode: #{inspect(other)}"
    end
  end

  defp normalize_override(other) do
    raise ArgumentError, "expected :frontend_assets_override to be a map, got: #{inspect(other)}"
  end

  defp override_manifest(override, default) do
    Map.get(override, :manifest) || Map.get(override, "manifest") || default
  end

  defp override_reason(override, default) do
    Map.get(override, :reason) || Map.get(override, "reason") || default
  end

  defp override_detail(override, key, default) do
    Map.get(override, key) || Map.get(override, Atom.to_string(key)) || default
  end

  defp observe_vue_surface_delivery(_component, %{mode: :ready}), do: :ok

  defp observe_vue_surface_delivery(component, delivery) do
    :telemetry.execute(
      [:jido_code, :frontend, :live_vue_surface, :degraded],
      %{count: 1},
      %{
        component: component,
        delivery_mode: delivery.mode,
        reason: delivery.reason,
        title: delivery.title,
        detail: delivery.detail
      }
    )
  end
end
