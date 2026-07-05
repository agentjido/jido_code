defmodule JidoCode.EmbeddedStoreRemovalGateTest do
  use ExUnit.Case, async: true

  @runtime_paths ["lib", "config", "test/support", "test/e2e", "mix.exs"]

  @forbidden_runtime_patterns [
    {~r/\buse\s+Ash\.Resource\b/, "use Ash.Resource"},
    {~r/\buse\s+Ash\.Domain\b/, "use Ash.Domain"},
    {~r/\bAshAuthentication\b/, "AshAuthentication"},
    {~r/\bJidoCode\.Repo\b/, "JidoCode.Repo"},
    {~r/\bEcto\.Adapters\.SQL\.Sandbox\b/, "Ecto.Adapters.SQL.Sandbox"},
    {~r/\becto_repos\b/, "ecto_repos"},
    {~r/\bash_domains\b/, "ash_domains"},
    {~r/\bmix\s+ecto\./, "mix ecto.*"}
  ]

  @forbidden_direct_deps [
    :ash,
    :ash_postgres,
    :ash_json_api,
    :ash_authentication,
    :ash_authentication_phoenix,
    :ash_phoenix,
    :ecto_sql,
    :phoenix_ecto,
    :postgrex
  ]

  test "runtime and launch paths do not reference Ash, Repo, Ecto sandbox, or Ecto tasks" do
    assert [] = runtime_violations()
  end

  test "direct dependencies do not reintroduce Ash or Postgres packages" do
    direct_deps =
      Mix.Project.config()
      |> Keyword.fetch!(:deps)
      |> Enum.map(fn
        {name, _requirement} -> name
        {name, _requirement, _opts} -> name
      end)
      |> MapSet.new()

    forbidden = MapSet.new(@forbidden_direct_deps)

    assert MapSet.disjoint?(direct_deps, forbidden),
           "forbidden direct deps found: #{inspect(MapSet.intersection(direct_deps, forbidden) |> MapSet.to_list())}"
  end

  test "application config has no Ecto repo configuration" do
    assert Application.get_env(:jido_code, :ecto_repos) in [nil, []]
    refute Application.get_env(:jido_code, JidoCode.Repo)
  end

  defp runtime_violations do
    @runtime_paths
    |> Enum.flat_map(&path_files/1)
    |> Enum.flat_map(&file_violations/1)
  end

  defp path_files(path) do
    cond do
      File.regular?(path) ->
        [path]

      File.dir?(path) ->
        path
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.filter(&text_file?/1)

      true ->
        []
    end
  end

  defp text_file?(path) do
    Path.extname(path) in [".ex", ".exs", ".ts", ".js", ".json", ".md"]
  end

  defp file_violations(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, line_no} ->
      @forbidden_runtime_patterns
      |> Enum.filter(fn {pattern, _label} -> line =~ pattern end)
      |> Enum.map(fn {_pattern, label} -> "#{path}:#{line_no}: #{label}" end)
    end)
  end
end
