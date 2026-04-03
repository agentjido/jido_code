defmodule JidoCode.Mix.FrontendStart do
  # covers: developer.workflow.host_postgres_defaults
  # covers: package.jido_code.package_quality_mix_surface_aligned
  # covers: architecture.frontend_stack.vite_and_ssr_are_standard_live_vue_tooling
  @moduledoc false

  @manifest_path "priv/static/.vite/manifest.json"
  @ssr_output_path "priv/static/server.mjs"
  @package_json_path "package.json"
  @package_lock_path "package-lock.json"
  @node_modules_path "node_modules"
  @node_modules_lock_path "node_modules/.package-lock.json"

  def prepare!(entrypoint, opts \\ []) do
    env = Keyword.get(opts, :env, Mix.env())
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    for task <- plan(env, cwd: cwd) do
      Mix.shell().info("[frontend] running #{task} before #{entrypoint}")
      Mix.Task.reenable(task)
      Mix.Task.run(task)
    end

    :ok
  end

  def plan(env \\ Mix.env(), opts \\ []) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())
    deps_task = if browser_dependencies_missing_or_stale?(cwd), do: ["assets.setup"], else: []

    case env do
      :test ->
        []

      :dev ->
        build_task = if frontend_bundle_missing?(cwd), do: ["assets.build"], else: []
        deps_task ++ build_task

      _other ->
        deps_task ++ ["frontend.verify"]
    end
  end

  defp browser_dependencies_missing_or_stale?(cwd) do
    node_modules = Path.join(cwd, @node_modules_path)
    lock_stamp = Path.join(cwd, @node_modules_lock_path)

    cond do
      not File.dir?(node_modules) ->
        true

      not File.exists?(lock_stamp) ->
        true

      newer_than?(Path.join(cwd, @package_json_path), lock_stamp) ->
        true

      newer_than?(Path.join(cwd, @package_lock_path), lock_stamp) ->
        true

      true ->
        false
    end
  end

  defp frontend_bundle_missing?(cwd) do
    not File.exists?(Path.join(cwd, @manifest_path)) or
      not File.exists?(Path.join(cwd, @ssr_output_path))
  end

  defp newer_than?(source, target) do
    with {:ok, source_stat} <- File.stat(source),
         {:ok, target_stat} <- File.stat(target) do
      source_stat.mtime > target_stat.mtime
    else
      _other -> false
    end
  end
end
